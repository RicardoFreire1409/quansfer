# Build de dependencias (capa offline de wheels para acelerar)
FROM python:3.12-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ git && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip wheel --wheel-dir=/wheels -r requirements.txt

# Runtime no-root (USER 1001 por políticas de OpenShift)
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8000
WORKDIR /app
# usuario no-root
RUN useradd -u 1001 -m appuser
COPY --from=builder /wheels /wheels
RUN pip install --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
# copia código
COPY . .
# carpeta de datos (escrita por no-root)
RUN mkdir -p /data/uploads && chown -R 1001:0 /data && chmod -R g+rwX /data
USER 1001
ENV UPLOAD_DIR=/data/uploads
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
