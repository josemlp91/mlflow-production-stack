#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# setup.sh — Configuración inicial del MLflow Production Stack
#
# Ejecutar UNA SOLA VEZ en el servidor tras clonar el repositorio.
# Pasos que realiza:
#   1. Verifica prerequisitos (docker, openssl)
#   2. Valida que .env esté configurado correctamente
#   3. Crea un certificado TLS autofirmado temporal para que Nginx pueda arrancar
#   4. Arranca Nginx para servir el challenge ACME de Let's Encrypt
#   5. Obtiene el certificado real de Let's Encrypt (método webroot)
#   6. Arranca el stack completo
#
# Uso: ./scripts/setup.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Navegar al directorio raíz del proyecto (independiente de desde dónde se ejecute)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── 1. Verificar prerequisitos ────────────────────────────────────────────────
echo "[1/6] Verificando prerequisitos..."

command -v docker >/dev/null 2>&1 \
    || { echo "ERROR: Docker no está instalado. Instálalo desde https://docs.docker.com/engine/install/"; exit 1; }

docker compose version >/dev/null 2>&1 \
    || { echo "ERROR: Docker Compose v2 no está disponible. Actualiza Docker Desktop o instala el plugin."; exit 1; }

command -v openssl >/dev/null 2>&1 \
    || { echo "ERROR: openssl no está instalado (necesario para el certificado temporal)."; exit 1; }

echo "  OK"

# ── 2. Validar configuración .env ─────────────────────────────────────────────
echo "[2/6] Validando configuración..."

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
    DOMAIN CERTBOT_EMAIL
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

echo "  OK"

# ── 3. Crear certificado TLS autofirmado temporal ─────────────────────────────
# Nginx necesita que los ficheros de certificado existan para arrancar.
# Usamos un certificado autofirmado de 1 día como placeholder hasta obtener
# el certificado real de Let's Encrypt en el paso siguiente.
echo "[3/6] Creando certificado TLS temporal..."

CERT_DIR="./certbot/conf/live/${DOMAIN}"
mkdir -p "$CERT_DIR" nginx/certbot/www backups

if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "${CERT_DIR}/privkey.pem" \
        -out "${CERT_DIR}/fullchain.pem" \
        -subj "/CN=${DOMAIN}" 2>/dev/null
    echo "  Certificado temporal creado en ${CERT_DIR}"
else
    echo "  Certificado ya existe, omitiendo."
fi

# ── 4. Arrancar Nginx para el challenge ACME ──────────────────────────────────
# Nginx sirve /.well-known/acme-challenge/ desde nginx/certbot/www/
# Let's Encrypt accederá a http://${DOMAIN}/.well-known/acme-challenge/<token>
echo "[4/6] Arrancando Nginx para el challenge ACME..."

docker compose up -d nginx

# Esperar a que Nginx responda en el puerto 80
MAX_WAIT=30
for i in $(seq 1 $MAX_WAIT); do
    if curl -sf "http://localhost:80/" -o /dev/null 2>&1 || \
       curl -sf "http://localhost:80/" -o /dev/null --max-time 2 2>&1; then
        break
    fi
    # Nginx puede devolver 301 (redirect a HTTPS), eso también es señal de que está listo
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:80/" 2>/dev/null || true)
    if [[ "$HTTP_CODE" == "301" || "$HTTP_CODE" == "200" ]]; then
        break
    fi
    if [ "$i" -eq "$MAX_WAIT" ]; then
        echo "ERROR: Nginx no respondió a tiempo. Revisa los logs:"
        echo "  docker compose logs nginx"
        exit 1
    fi
    sleep 2
done
echo "  Nginx listo"

# ── 5. Obtener certificado real de Let's Encrypt ──────────────────────────────
echo "[5/6] Obteniendo certificado Let's Encrypt para ${DOMAIN}..."
echo "  (Asegúrate de que el DNS de ${DOMAIN} apunta a este servidor)"

docker compose --profile certbot run --rm certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --domain "$DOMAIN" \
    --email "$CERTBOT_EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal

# Recargar Nginx para que use el certificado real
docker compose exec nginx nginx -s reload
echo "  Certificado obtenido y Nginx recargado"

# ── 6. Arrancar el stack completo ─────────────────────────────────────────────
echo "[6/6] Arrancando el stack completo..."
docker compose up -d --build

# Esperar a que MLflow esté listo (puede tardar hasta 60s en aplicar migraciones)
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
echo "  Setup completado con éxito"
echo "══════════════════════════════════════════════════════════════════"
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
