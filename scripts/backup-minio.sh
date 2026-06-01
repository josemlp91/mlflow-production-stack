#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# backup-minio.sh — Mirror incremental de artefactos MinIO a disco local
#
# Usa mc mirror sobre el bucket de MLflow. Solo transfiere objetos nuevos
# o modificados. No requiere parar MinIO.
#
# Los backups se guardan en ./backups/minio/ con la misma estructura de
# carpetas que el bucket original.
#
# Para restaurar:
#   docker compose exec -T minio mc mirror --overwrite \
#       /ruta/backup/minio/ local/${MINIO_BUCKET}
#
# Para hacer un backup remoto:
#   make remote-backup-minio
#
# Uso: ./scripts/backup-minio.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

set -a
# shellcheck source=../.env
source .env
set +a

BACKUP_DIR="${PROJECT_DIR}/backups/minio"

mkdir -p "$BACKUP_DIR"

echo "Iniciando mirror de MinIO..."
echo "  Bucket:   ${MINIO_BUCKET}"
echo "  Destino:  ${BACKUP_DIR}"

CONTAINER_ID=$(docker compose ps -q minio 2>/dev/null)
if [ -z "$CONTAINER_ID" ]; then
    echo "ERROR: El contenedor de MinIO no está corriendo."
    exit 1
fi

NETWORK=$(docker inspect "$CONTAINER_ID" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{printf "%s" $k}}{{end}}')

if [ -z "$NETWORK" ]; then
    echo "ERROR: No se pudo determinar la red de MinIO."
    exit 1
fi

docker run --rm \
    --network "$NETWORK" \
    -v "${BACKUP_DIR}:/backup" \
    -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
    -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
    -e "MINIO_BUCKET=${MINIO_BUCKET}" \
    --entrypoint /bin/sh \
    minio/minio:RELEASE.2025-04-22T22-12-26Z \
    -c "
        mc alias set local http://minio:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD >/dev/null 2>&1
        mc mirror --overwrite local/\$MINIO_BUCKET /backup/
    "

BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
echo "  Mirror completado: ${BACKUP_SIZE}"
echo ""
echo "Para ver los objetos respaldados:"
echo "  find ${BACKUP_DIR} -type f | head"
