from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import uuid, base64, json, mimetypes

from Crypto.Cipher import AES        # AES-CBC
from qkd_protocol import QKDProtocol # simulador BB84

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)

import os
from pathlib import Path

UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", "/data/uploads"))
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# Guardamos metadatos: transfer_id -> {
#   key_hex, iv_b64, filename_enc, filename_original, path
# }
TRANSFERS = {}

# Instancia simulador BB84
qkd = QKDProtocol()

@app.get("/qkd/key")
def get_qkd_key():
    key_bytes = qkd.generate_shared_key(target_bits=128)
    key_hex = ''.join(f'{b:02x}' for b in key_bytes)
    return {"ok": True, "key_hex": key_hex}

@app.post("/upload")
async def upload(
    file: UploadFile = File(...),
    iv_b64: str = Form(...),
    key_hex: str = Form(...),
):
    # Validaciones mínimas
    try:
        key = bytes.fromhex(key_hex)
    except ValueError:
        raise HTTPException(status_code=400, detail="key_hex inválida")
    if len(key) not in (16, 24, 32):
        raise HTTPException(status_code=400, detail="key debe ser 16/24/32 bytes")

    try:
        iv = base64.b64decode(iv_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="iv_b64 inválido")
    if len(iv) != 16:
        raise HTTPException(status_code=400, detail="IV debe ser 16 bytes")

    # Guardar cifrado en disco tal cual llega
    tid = uuid.uuid4().hex[:8]
    filename_enc = file.filename or "file.enc"
    save_path = UPLOAD_DIR / filename_enc
    with open(save_path, "wb") as f:
        f.write(await file.read())

    # Derivar nombre original (quitando un .enc final si existe)
    filename_original = filename_enc[:-4] if filename_enc.lower().endswith(".enc") else filename_enc

    TRANSFERS[tid] = {
        "key_hex": key_hex,
        "iv_b64": iv_b64,
        "filename_enc": filename_enc,
        "filename_original": filename_original,
        "path": save_path,
    }
    return {"ok": True, "transfer_id": tid, "filename_original": filename_original, "filename_enc": filename_enc}

@app.get("/transfer/{tid}")
def get_transfer(tid: str):
    meta = TRANSFERS.get(tid)
    if not meta:
        raise HTTPException(status_code=404, detail="not found")
    return {
        "ok": True,
        "key_hex": meta["key_hex"],
        "iv_b64": meta["iv_b64"],
        "filename_enc": meta["filename_enc"],
        "filename_original": meta["filename_original"],
        "download_url": f"/download/{tid}",
    }

@app.get("/download/{tid}")
def download_encrypted(tid: str):
    meta = TRANSFERS.get(tid)
    if not meta:
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(
        meta["path"],
        media_type="application/octet-stream",
        filename=meta["filename_enc"],
    )

def _pkcs7_unpad(data: bytes) -> bytes:
    if not data:
        raise HTTPException(status_code=400, detail="bloque vacío")
    pad = data[-1]
    # Validación PKCS#7
    if pad < 1 or pad > 16 or len(data) < pad:
        raise HTTPException(status_code=400, detail="padding inválido")
    if data[-pad:] != bytes([pad]) * pad:
        raise HTTPException(status_code=400, detail="padding inválido")
    return data[:-pad]

@app.get("/decrypt_by_id/{tid}")
def decrypt_by_id(tid: str):
    meta = TRANSFERS.get(tid)
    if not meta:
        raise HTTPException(status_code=404, detail="not found")

    enc_data = meta["path"].read_bytes()
    key = bytes.fromhex(meta["key_hex"])
    iv = base64.b64decode(meta["iv_b64"])

    cipher = AES.new(key, AES.MODE_CBC, iv)
    plain = cipher.decrypt(enc_data)
    plain = _pkcs7_unpad(plain)

    out_name = meta["filename_original"]
    # Content-Type basado en la extensión original (best-effort)
    ctype, _ = mimetypes.guess_type(out_name)
    headers = {"Content-Disposition": f'attachment; filename="{out_name}"'}

    return StreamingResponse(
        iter([plain]),
        media_type=ctype or "application/octet-stream",
        headers=headers,
    )
