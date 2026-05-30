#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# setup.sh — Configuración inicial del MLflow Production Stack
#
# Ejecutar UNA SOLA VEZ en el servidor tras clonar el repositorio.
# El TLS y el certificado Let's Encrypt los gestiona Coolify automáticamente
# a través de su proxy Traefik — no es necesario ningún paso manual de certbot.
#
# Pasos que realiza:
#   1. Verifica prerequisitos (docker, docker compose)
#   2. Valida que .env esté configurado correctamente
#   3. Arranca el stack completo
#
# Uso: ./scripts/setup.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Navegar al directorio raíz del proyecto (independiente de desde dónde se ejecute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── 1. Verificar prerequisitos ────────────────────────────────────────────────
echo "[1/3] Verificando prerequisitos..."

command -v docker >/dev/null 2>&1 \
    || { echo "ERROR: Docker no está instalado."; exit 1; }

docker compose version >/dev/null 2>&1 \
    || { echo "ERROR: Docker Compose v2 no está disponible."; exit 1; }

# Verificar que la red de Coolify existe (necesaria para que Traefik enrute el tráfico)
docker network inspect coolify >/dev/null 2>&1 \
    || { echo "ERROR: La red 'coolify' no existe. ¿Está Coolify instalado en este servidor?"; exit 1; }

echo "  OK"

# ── 2. Validar configuración .env ─────────────────────────────────────────────
echo "[2/3] Validando configuración..."

if [ ! -f .env ]; then
    cp .env.example .env
    echo ""
    echo "  Se ha creado .env a partir de .env.example."
    echo "  Rellena todos los valores CHANGE_ME en .env y vuelve a ejecutar setup.sh."
    exit 0
fi

# Cargar variables de entorno del fichero .env
set -a
# shellcheck source=../.env
source .env
set +a

# Verificar que no queden valores por defecto sin cambiar
REQUIRED_VARS=(
    DOMAIN
    POSTGRES_PASSWORD
    MLFLOW_ADMIN_USERNAME MLFLOW_ADMIN_PASSWORD MLFLOW_SECRET_KEY
    MINIO_ROOT_PASSWORD
)

for var in "${REQUIRED_VARS[@]}"; do
    val="${!var:-}"
    if [[ -z "$val" || "$val" == *"CHANGE_ME"* ]]; then
        echo "ERROR: La variable $var no está configurada o todavía tiene el valor por defecto en .env."
        exit 1
    fi
done

mkdir -p backups

echo "  OK"

# ── 3. Arrancar el stack completo ─────────────────────────────────────────────
echo "[3/3] Arrancando el stack..."
docker compose up -d --build

# Esperar a que MLflow esté listo
echo "  Esperando a que MLflow esté disponible..."
MAX_RETRIES=24
for i in $(seq 1 $MAX_RETRIES); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:5000/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" -eq 200 ] 2>/dev/null; then
        echo "  MLflow listo"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "  AVISO: MLflow no respondió en 120s. Revisa los logs:"
        echo "    docker compose logs mlflow"
    fi
    sleep 5
done

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo "  Setup completado"
echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "  Stack arrancado. Coolify gestionará el certificado TLS"
echo "  automáticamente la primera vez que se acceda al dominio."
echo ""
echo "  UI de MLflow:  https://${DOMAIN}"
echo "  Admin user:    ${MLFLOW_ADMIN_USERNAME}"
echo ""
echo "  Gestión de usuarios:"
echo "    Añadir:  ./scripts/add-user.sh <usuario> <password>"
echo "    Listar:  ./scripts/list-users.sh"
echo "    Backup:  ./scripts/backup.sh"
echo ""
echo "  Para conectar desde el CPD:"
echo "    export MLFLOW_TRACKING_URI=https://${DOMAIN}"
echo "    export MLFLOW_TRACKING_USERNAME=<usuario>"
echo "    export MLFLOW_TRACKING_PASSWORD=<password>"
echo "══════════════════════════════════════════════════════════════════"
