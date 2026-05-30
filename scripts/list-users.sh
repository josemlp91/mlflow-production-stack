#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# list-users.sh — Listar todos los usuarios registrados en MLflow
#
# Uso: ./scripts/list-users.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Cargar credenciales de admin desde .env
set -a
# shellcheck source=../.env
source "${PROJECT_DIR}/.env"
set +a

MLFLOW_URL="https://${DOMAIN}"

echo "Usuarios registrados en ${MLFLOW_URL}:"
echo ""

HTTP_CODE=$(curl -s -o /tmp/mlflow_list_users_response.json -w "%{http_code}" \
    -X GET "${MLFLOW_URL}/api/2.0/mlflow/users" \
    -u "${MLFLOW_ADMIN_USERNAME}:${MLFLOW_ADMIN_PASSWORD}")

if [ "$HTTP_CODE" -eq 200 ]; then
    # Mostrar usuarios en formato legible. Requiere python3 (disponible en la mayoría de servidores)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
data = json.load(open('/tmp/mlflow_list_users_response.json'))
users = data.get('users', [])
if not users:
    print('  (ningún usuario encontrado)')
else:
    print(f'  {'Usuario':<20} {'Admin':<8} {'ID'}')
    print(f'  {'-'*40}')
    for u in users:
        admin = 'sí' if u.get('is_admin') else 'no'
        print(f\"  {u['username']:<20} {admin:<8} {u.get('id', '-')}\")
print()
print(f'Total: {len(users)} usuario(s)')
"
    else
        cat /tmp/mlflow_list_users_response.json
    fi
else
    echo "ERROR: No se pudo obtener la lista de usuarios."
    echo "  HTTP status: ${HTTP_CODE}"
    cat /tmp/mlflow_list_users_response.json
    exit 1
fi
