# mlflow-production-stack

Stack de producción para el servidor de tracking MLflow. Orquestado con Docker Compose, protegido por Nginx con TLS (Let's Encrypt) y autenticación nativa multi-usuario de MLflow, con PostgreSQL como backend de metadatos y MinIO como almacenamiento de artefactos S3-compatible.

## Arquitectura

```
Internet / CPD externo
        │
        ▼
   Nginx :443  (TLS xapilopex.es)
        │
        ▼
   MLflow :5000  ──────►  PostgreSQL :5432
        │
        ▼
   MinIO :9000
```

Solo Nginx expone puertos al exterior (80 y 443). El resto de servicios se comunican en una red Docker interna (`mlflow_net`).

## Servicios

| Servicio    | Imagen                                       | Función                              |
|-------------|----------------------------------------------|--------------------------------------|
| postgres    | `postgres:16-alpine`                         | Backend de metadatos MLflow          |
| minio       | `minio/minio:RELEASE.2025-04-22T22-12-26Z`   | Almacenamiento de artefactos (S3)    |
| minio-init  | `minio/mc:latest`                            | Crea el bucket en el primer arranque |
| mlflow      | `mlflow_server:local` (build local)          | Tracking server con auth nativa      |
| nginx       | `nginx:1.27-alpine`                          | Reverse proxy + TLS                  |
| certbot     | `certbot/certbot:latest`                     | Gestión de certificados Let's Encrypt|

## Requisitos del servidor

- Docker Engine 24+
- Docker Compose v2
- `openssl` instalado en el host
- Puerto 80 y 443 accesibles desde internet
- DNS del dominio apuntando al servidor

## Primer despliegue

```bash
# 1. Clonar el repositorio
git clone <repo-url>
cd mlflow-production-stack

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env: rellenar todos los valores CHANGE_ME
# Generar MLFLOW_SECRET_KEY con:
#   python3 -c "import secrets; print(secrets.token_hex(32))"

# 3. Ejecutar el setup inicial (obtiene certificado TLS y arranca el stack)
chmod +x scripts/*.sh
./scripts/setup.sh
```

La UI de MLflow estará disponible en `https://xapilopex.es`.

## Operación diaria

```bash
# Arrancar el stack
docker compose up -d

# Ver logs en tiempo real
docker compose logs -f

# Parar el stack
docker compose down
```

## Gestión de usuarios

```bash
# Añadir usuario
./scripts/add-user.sh <usuario> <password>

# Listar usuarios
./scripts/list-users.sh

# Eliminar usuario
./scripts/remove-user.sh <usuario>
```

Los permisos por experimento (READ / EDIT / MANAGE) se asignan desde la UI de MLflow o via su API REST.

## Backup

```bash
# Backup de PostgreSQL (metadatos de experimentos)
./scripts/backup.sh
# → Guarda en ./backups/mlflow_YYYYMMDD_HHMMSS.sql.gz

# Restaurar un backup
gunzip -c backups/mlflow_YYYYMMDD_HHMMSS.sql.gz \
  | docker compose exec -T postgres psql -U mlflow -d mlflow
```

Los artefactos (modelos, plots) están en MinIO. Para respaldarlos:
```bash
docker compose exec minio mc mirror local/mlflow-artifacts ./backups/minio/
```

## Renovación de certificados TLS

```bash
# Renovar manualmente (certbot solo renueva si expira en < 30 días)
./scripts/renew-certs.sh

# Configurar renovación automática en crontab (recomendado)
# crontab -e
0 3 * * * /ruta/proyecto/scripts/renew-certs.sh >> /var/log/certbot-renew.log 2>&1
```

## Conectar desde un servidor externo (CPD)

```bash
pip install mlflow

export MLFLOW_TRACKING_URI=https://xapilopex.es
export MLFLOW_TRACKING_USERNAME=<usuario>
export MLFLOW_TRACKING_PASSWORD=<password>
```

```python
import mlflow

mlflow.set_tracking_uri("https://xapilopex.es")
mlflow.set_experiment("mi-experimento")

with mlflow.start_run():
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_artifact("modelo.pkl")
```

## Actualizar el stack

```bash
git pull
docker compose build mlflow   # reconstruir imagen si cambió el Dockerfile
docker compose up -d
```

## Estructura del repositorio

```
├── docker-compose.yml          # Orquestación de servicios
├── .env.example                # Plantilla de variables de entorno
├── mlflow/
│   ├── Dockerfile              # Imagen custom MLflow (python:3.12-slim)
│   └── entrypoint.sh           # Genera auth config, migra BD y arranca servidor
├── nginx/
│   └── conf.d/mlflow.conf      # Reverse proxy HTTPS + ACME challenge
└── scripts/
    ├── setup.sh                # Setup inicial (primera vez)
    ├── add-user.sh             # Añadir usuario MLflow
    ├── remove-user.sh          # Eliminar usuario MLflow
    ├── list-users.sh           # Listar usuarios MLflow
    ├── backup.sh               # Backup de PostgreSQL
    └── renew-certs.sh          # Renovación de certificados TLS
```
