#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# remove-user.sh — Eliminar un usuario de MLflow
#
# Uso: ./scripts/remove-user.sh <usuario>
#
# ADVERTENCIA: Esta acción es irreversible. Los runs y experimentos del usuario
# no se eliminan, pero el usuario perderá el acceso inmediatamente.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <usuario>"
    exit 1
fi

TARGET_USER="$1"

# Cargar credenciales de admin desde .env
set -a
# shellcheck source=../.env
source "${PROJECT_DIR}/.env"
set +a

# Evitar eliminar al administrador accidentalmente
if [ "$TARGET_USER" = "$MLFLOW_ADMIN_USERNAME" ]; then
    echo "ERROR: No se puede eliminar al usuario administrador ('${MLFLOW_ADMIN_USERNAME}')."
    exit 1
fi

MLFLOW_URL="https://${DOMAIN}"

echo "Eliminando usuario '${TARGET_USER}' de ${MLFLOW_URL}..."

# Confirmación interactiva para evitar eliminaciones accidentales
read -r -p "¿Confirmas la eliminación del usuario '${TARGET_USER}'? [s/N] " confirm
if [[ ! "$confirm" =~ ^[sS]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

HTTP_CODE=$(curl -s -o /tmp/mlflow_remove_user_response.json -w "%{http_code}" \
    -X DELETE "${MLFLOW_URL}/api/2.0/mlflow/users/delete" \
    -H "Content-Type: application/json" \
    -u "${MLFLOW_ADMIN_USERNAME}:${MLFLOW_ADMIN_PASSWORD}" \
    -d "{\"username\": \"${TARGET_USER}\"}")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "Usuario '${TARGET_USER}' eliminado correctamente."
else
    echo "ERROR: No se pudo eliminar el usuario '${TARGET_USER}'."
    echo "  HTTP status: ${HTTP_CODE}"
    echo "  Respuesta:"
    cat /tmp/mlflow_remove_user_response.json
    echo ""
    exit 1
fi
