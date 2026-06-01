#!/bin/sh
# ──────────────────────────────────────────────────────────────────────────────
# entrypoint.sh — Arranque del servidor MLflow con autenticación nativa
#
# Genera el fichero de configuración de autenticación a partir de las
# variables de entorno, ejecuta las migraciones de base de datos y arranca
# el servidor. Este script se ejecuta cada vez que el contenedor arranca.
# ──────────────────────────────────────────────────────────────────────────────
set -e

# ── Validar variables de entorno requeridas ───────────────────────────────────
for var in MLFLOW_BACKEND_STORE_URI MINIO_BUCKET MLFLOW_ADMIN_USERNAME MLFLOW_ADMIN_PASSWORD; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: required environment variable $var is not set" >&2
        exit 1
    fi
done

# ── Generar configuración de autenticación ────────────────────────────────────
cat > /tmp/basic_auth.ini << EOF
[mlflow]
default_permission = READ
database_uri = ${MLFLOW_BACKEND_STORE_URI}
admin_username = ${MLFLOW_ADMIN_USERNAME}
admin_password = ${MLFLOW_ADMIN_PASSWORD}
EOF

export MLFLOW_AUTH_CONFIG_PATH=/tmp/basic_auth.ini

# ── Arrancar el servidor MLflow ──────────────────────────────────────────────
echo "Starting MLflow tracking server..."
exec mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --workers 1 \
    --backend-store-uri "${MLFLOW_BACKEND_STORE_URI}" \
    --artifacts-destination "s3://${MINIO_BUCKET}" \
    --app-name basic-auth \
    --gunicorn-opts "--timeout 120 --graceful-timeout 60 --log-level debug"
