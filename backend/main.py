# backend/main.py (añade estas importaciones)
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel
import os, io, base64, binascii

from qkd_protocol import QKDProtocol
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend

app = FastAPI()
qkd = QKDProtocol(key_length=20)

class KeyResponse(BaseModel):
    key_hex: str

@app.get("/qkd/key", response_model=KeyResponse)
def get_qkd_key():
    key_bytes = qkd.generate_shared_key(target_bits=128)  # 16 bytes
    return {"key_hex": key_bytes.hex()}

@app.post("/upload")
async def upload_file(file: UploadFile = File(...), iv_b64: str = Form(...)):
    os.makedirs("uploads", exist_ok=True)
    dest = os.path.join("uploads", file.filename)
    with open(dest, "wb") as f:
        f.write(await file.read())
    return JSONResponse({"ok": True, "saved_as": dest, "iv_b64": iv_b64})

def aes_cbc_pkcs7_decrypt(cipher_bytes: bytes, key_bytes: bytes, iv_bytes: bytes) -> bytes:
    cipher = Cipher(algorithms.AES(key_bytes), modes.CBC(iv_bytes), backend=default_backend())
    decryptor = cipher.decryptor()
    padded = decryptor.update(cipher_bytes) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    plain = unpadder.update(padded) + unpadder.finalize()
    return plain

@app.post("/decrypt")
async def decrypt_file(
    file: UploadFile = File(...),            # archivo .enc
    iv_b64: str = Form(...),                # IV en base64 (mismo que usaste al cifrar)
    key_hex: str = Form(...),               # clave en hex (16 bytes = 32 hex chars)
    original_name: str = Form(None)         # opcional: nombre original para la descarga
):
    try:
        cipher_bytes = await file.read()
        iv_bytes = base64.b64decode(iv_b64)
        key_bytes = binascii.unhexlify(key_hex)
        if len(key_bytes) not in (16, 24, 32):
            return JSONResponse({"ok": False, "error": "La clave debe ser 16/24/32 bytes"}, status_code=400)
        if len(iv_bytes) != 16:
            return JSONResponse({"ok": False, "error": "IV debe ser 16 bytes"}, status_code=400)

        plain = aes_cbc_pkcs7_decrypt(cipher_bytes, key_bytes, iv_bytes)

        # Nombre de salida
        out_name = original_name or file.filename
        if out_name.endswith(".enc"):
            out_name = out_name[:-4]
        # Responder como archivo descargable
        return StreamingResponse(
            io.BytesIO(plain),
            media_type="application/octet-stream",
            headers={"Content-Disposition": f'attachment; filename="{out_name}"'}
        )
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
