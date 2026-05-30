#!/bin/sh
# ──────────────────────────────────────────────────────────────────────────────
# entrypoint.sh — Arranque del servidor MLflow con autenticación nativa
#
# Genera el fichero de configuración de autenticación a partir de las
# variables de entorno, ejecuta las migraciones de base de datos y arranca
# el servidor. Este script se ejecuta cada vez que el contenedor arranca.
# ──────────────────────────────────────────────────────────────────────────────
set -e

# ── Generar configuración de autenticación ────────────────────────────────────
# MLflow lee este fichero al arrancar para inicializar el sistema de usuarios.
# El admin_password solo se usa en el primer arranque (cuando el usuario aún
# no existe en la base de datos); después se ignora y prevalece el de la BD.
cat > /tmp/basic_auth.ini << EOF
[mlflow]
default_permission = READ
database_uri = ${MLFLOW_BACKEND_STORE_URI}
admin_username = ${MLFLOW_ADMIN_USERNAME}
admin_password = ${MLFLOW_ADMIN_PASSWORD}
EOF

export MLFLOW_AUTH_CONFIG_PATH=/tmp/basic_auth.ini

# ── Ejecutar migraciones de base de datos ────────────────────────────────────
# Idempotente: aplica los cambios de esquema pendientes sin afectar datos existentes.
# Es necesario ejecutarlo antes de arrancar el servidor al actualizar MLflow.
echo "Running database migrations..."
mlflow db upgrade "${MLFLOW_BACKEND_STORE_URI}"

# ── Arrancar el servidor MLflow ──────────────────────────────────────────────
echo "Starting MLflow tracking server..."
exec mlflow server \
    --host 0.0.0.0 \
    --port 5000 \
    --backend-store-uri "${MLFLOW_BACKEND_STORE_URI}" \
    --artifacts-destination "s3://${MINIO_BUCKET}" \
    --app-name basic-auth
