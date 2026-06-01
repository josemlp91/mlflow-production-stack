#!/bin/sh
set -e

# ── Validar variables de entorno requeridas ───────────────────────────────────
for var in MLFLOW_BACKEND_STORE_URI MINIO_BUCKET MLFLOW_ADMIN_USERNAME MLFLOW_ADMIN_PASSWORD; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: required environment variable $var is not set" >&2
        exit 1
    fi
done

# ── Esperar a que PostgreSQL esté listo ───────────────────────────────────────
# El módulo basic-auth conecta a la BD durante la inicialización del worker.
# Si PostgreSQL no está listo en ese momento, el worker falla en el arranque.
echo "Waiting for PostgreSQL..."
python3 << 'PYEOF'
import time, sys, os
import psycopg2

uri = os.environ["MLFLOW_BACKEND_STORE_URI"]
for i in range(30):
    try:
        conn = psycopg2.connect(uri)
        conn.close()
        print("PostgreSQL is ready", flush=True)
        sys.exit(0)
    except Exception as e:
        print(f"Waiting for PostgreSQL ({i+1}/30): {e}", flush=True)
        time.sleep(2)
print("ERROR: PostgreSQL not available after 60 seconds", flush=True)
sys.exit(1)
PYEOF

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
    --gunicorn-opts "--timeout 120 --graceful-timeout 60 --capture-output --preload --log-level debug"
