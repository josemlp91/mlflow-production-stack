#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# renew-certs.sh — Renovación de certificados TLS de Let's Encrypt
#
# Usa el método webroot: Nginx sirve el challenge ACME desde nginx/certbot/www/
# sin necesidad de detener el servidor.
#
# Certbot renueva automáticamente solo si el certificado expira en < 30 días,
# por lo que es seguro ejecutar este script con mayor frecuencia.
#
# Configuración de crontab recomendada (ejecutar como root o el usuario del deploy):
#   0 3 * * * /ruta/al/proyecto/scripts/renew-certs.sh >> /var/log/certbot-renew.log 2>&1
#
# Uso: ./scripts/renew-certs.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando renovación de certificados..."

# Intentar renovación (certbot decide si es necesario renovar o no)
docker compose --profile certbot run --rm certbot renew \
    --webroot \
    --webroot-path /var/www/certbot \
    --quiet

# Recargar Nginx para que cargue los nuevos certificados si se renovaron
# nginx -s reload es una recarga en caliente: no hay downtime
docker compose exec nginx nginx -s reload

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Renovación completada y Nginx recargado."
