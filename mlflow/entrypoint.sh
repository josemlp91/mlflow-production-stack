#!/bin/sh
set -e

echo "MLflow Tracking Server entrypoint script starting..."

# ── Validar variables de entorno requeridas ───────────────────────────────────
for var in MLFLOW_BACKEND_STORE_URI MINIO_BUCKET MLFLOW_ADMIN_USERNAME MLFLOW_ADMIN_PASSWORD; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: required environment variable $var is not set" >&2
        exit 1
    fi
done

# ── Esperar a PostgreSQL y preparar la BD de auth ─────────────────────────────
# El módulo basic-auth y el backend principal comparten la misma tabla
# alembic_version si usan la misma BD, lo que provoca conflictos de migración.
# Solución: usar una BD separada para auth (mlflow_auth).
# Este bloque espera a que PostgreSQL esté listo y crea la BD de auth si no existe.
MLFLOW_AUTH_DB_URI=$(python3 << 'PYEOF'
import time, sys, os
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from urllib.parse import urlparse, urlunparse

main_uri = os.environ["MLFLOW_BACKEND_STORE_URI"]
parsed = urlparse(main_uri)
main_db = parsed.path.lstrip("/")
auth_db = os.environ.get("POSTGRES_AUTH_DB") or (main_db + "_auth")
auth_uri = urlunparse(parsed._replace(path="/" + auth_db))

# Wait for PostgreSQL
for i in range(30):
    try:
        conn = psycopg2.connect(main_uri)
        conn.close()
        print(f"PostgreSQL is ready", file=sys.stderr, flush=True)
        break
    except Exception as e:
        print(f"Waiting for PostgreSQL ({i+1}/30): {e}", file=sys.stderr, flush=True)
        time.sleep(2)
else:
    print("ERROR: PostgreSQL not available after 60 seconds", file=sys.stderr, flush=True)
    sys.exit(1)

# Create auth database if it doesn't exist
conn = psycopg2.connect(main_uri)
conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
cur = conn.cursor()
cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (auth_db,))
if not cur.fetchone():
    cur.execute(f'CREATE DATABASE "{auth_db}"')
    print(f"Created auth database: {auth_db}", file=sys.stderr, flush=True)
else:
    print(f"Auth database exists: {auth_db}", file=sys.stderr, flush=True)
conn.close()

# Print the auth URI to stdout so the shell captures it
print(auth_uri)
PYEOF
)

# ── Generar configuración de autenticación ────────────────────────────────────
cat > /tmp/basic_auth.ini << EOF
[mlflow]
default_permission = READ
database_uri = ${MLFLOW_AUTH_DB_URI}
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
