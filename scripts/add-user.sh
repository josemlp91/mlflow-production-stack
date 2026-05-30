#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# add-user.sh — Crear un nuevo usuario en MLflow
#
# Usa la API REST de MLflow para registrar el usuario. El admin puede
# después asignar permisos por experimento desde la UI o via API.
#
# Uso: ./scripts/add-user.sh <usuario> <password>
#
# Permisos disponibles (asignables por experimento vía UI):
#   READ    — solo lectura
#   EDIT    — puede registrar runs y métricas
#   MANAGE  — puede administrar el experimento y sus permisos
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <usuario> <password>"
    exit 1
fi

NEW_USERNAME="$1"
NEW_PASSWORD="$2"

# Cargar credenciales de admin desde .env
set -a
# shellcheck source=../.env
source "${PROJECT_DIR}/.env"
set +a

MLFLOW_URL="https://${DOMAIN}"

echo "Creando usuario '${NEW_USERNAME}' en ${MLFLOW_URL}..."

HTTP_CODE=$(curl -s -o /tmp/mlflow_add_user_response.json -w "%{http_code}" \
    -X POST "${MLFLOW_URL}/api/2.0/mlflow/users/create" \
    -H "Content-Type: application/json" \
    -u "${MLFLOW_ADMIN_USERNAME}:${MLFLOW_ADMIN_PASSWORD}" \
    -d "{\"username\": \"${NEW_USERNAME}\", \"password\": \"${NEW_PASSWORD}\"}")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "Usuario '${NEW_USERNAME}' creado correctamente."
    echo ""
    echo "Para asignar permisos a un experimento específico, usa la UI de MLflow"
    echo "o el script set-permission.sh (si está disponible)."
else
    echo "ERROR: No se pudo crear el usuario '${NEW_USERNAME}'."
    echo "  HTTP status: ${HTTP_CODE}"
    echo "  Respuesta:"
    cat /tmp/mlflow_add_user_response.json
    echo ""
    exit 1
fi
