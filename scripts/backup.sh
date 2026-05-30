#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# backup.sh — Backup de la base de datos PostgreSQL de MLflow
#
# Realiza un pg_dump completo del esquema y datos, comprimido con gzip.
# Los artefactos (modelos, plots) están en MinIO y no se respaldan aquí;
# para ellos usa: mc mirror local/mlflow-artifacts ./backups/minio/
#
# Los backups se guardan en ./backups/ con timestamp:
#   backups/mlflow_20260530_143022.sql.gz
#
# Para restaurar un backup:
#   gunzip -c backups/mlflow_YYYYMMDD_HHMMSS.sql.gz \
#     | docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
#
# Uso: ./scripts/backup.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Cargar variables de entorno desde .env
set -a
# shellcheck source=../.env
source .env
set +a

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${PROJECT_DIR}/backups"
BACKUP_FILE="${BACKUP_DIR}/mlflow_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Iniciando backup de PostgreSQL..."
echo "  Base de datos: ${POSTGRES_DB}"
echo "  Destino:       ${BACKUP_FILE}"

# Ejecutar pg_dump dentro del contenedor de postgres y comprimir con gzip
docker compose exec -T postgres pg_dump \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --no-password \
    | gzip > "$BACKUP_FILE"

BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "  Backup completado: ${BACKUP_SIZE}"
echo ""
echo "Para listar los backups disponibles:"
echo "  ls -lh ${BACKUP_DIR}/"
