#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# renew-certs.sh — Información sobre renovación de certificados TLS
#
# Este stack usa Coolify como proxy (Traefik). Coolify gestiona los certificados
# Let's Encrypt automáticamente: los obtiene la primera vez que se accede al
# dominio y los renueva antes de que caduquen sin intervención manual.
#
# No es necesario ejecutar este script ni configurar ningún crontab.
#
# Si necesitas forzar la renovación o ver el estado de los certificados,
# hazlo desde el panel de Coolify: Settings → SSL Certificates
# ──────────────────────────────────────────────────────────────────────────────

echo "Los certificados TLS son gestionados automáticamente por Coolify (Traefik)."
echo "No es necesaria ninguna acción manual."
echo ""
echo "Para ver el estado: panel de Coolify → Settings → SSL Certificates"
