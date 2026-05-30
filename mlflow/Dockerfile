# ──────────────────────────────────────────────────────────────────────────────
# Imagen del servidor MLflow Tracking
#
# Basada en python:3.12-slim para minimizar la superficie de ataque.
# Instala MLflow con los backends necesarios:
#   - psycopg2-binary: conector PostgreSQL para el backend store
#   - boto3: cliente S3 para comunicarse con MinIO (artefactos)
# ──────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Instalar curl para el healthcheck del contenedor
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Pinear versiones explícitas para garantizar reproducibilidad en producción
RUN pip install --no-cache-dir \
    mlflow==2.20.0 \
    psycopg2-binary==2.9.9 \
    boto3==1.35.0

WORKDIR /app

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 5000

# El healthcheck permite que docker compose espere a que MLflow esté listo
# antes de arrancar Nginx (evita 502 al inicio)
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
    CMD curl -sf http://localhost:5000/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
