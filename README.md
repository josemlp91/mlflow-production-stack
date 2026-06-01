# mlflow-production-stack

Stack de producción para el servidor de tracking MLflow. Orquestado con Docker Compose, TLS gestionado por Coolify (Traefik) y autenticación nativa multi-usuario de MLflow, con PostgreSQL como backend de metadatos y MinIO como almacenamiento de artefactos S3-compatible.

## Arquitectura

```
Internet / CPD externo
        │
        ▼
   Coolify :443  (TLS — tu dominio)
        │
        ▼
   MLflow :5000  ──────►  PostgreSQL :5432
        │
        ▼
   MinIO :9000
```

Coolify gestiona la terminación TLS y enruta el tráfico hacia MLflow. El resto de servicios se comunican en una red Docker interna (`mlflow_net`).

## Servicios

| Servicio    | Imagen                                       | Función                              |
|-------------|----------------------------------------------|--------------------------------------|
| postgres    | `postgres:16-alpine`                         | Backend de metadatos MLflow          |
| minio       | `minio/minio:RELEASE.2025-04-22T22-12-26Z`   | Almacenamiento de artefactos (S3)    |
| minio-init  | `minio/mc:latest`                            | Crea el bucket en el primer arranque |
| mlflow      | `ghcr.io/.../mlflow:latest` (CI/CD build) | Tracking server con auth nativa      |

## Requisitos del servidor

- Docker Engine 24+
- Docker Compose v2
- Coolify configurado con el dominio apuntando al servidor

## Primer despliegue

```bash
# 1. Clonar el repositorio en el servidor Coolify
git clone <repo-url>
cd mlflow-production-stack

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env: rellenar todos los valores CHANGE_ME
# Generar MLFLOW_SECRET_KEY con:
#   python3 -c "import secrets; print(secrets.token_hex(32))"

# 3. Ejecutar el setup inicial
make setup
```

El setup valida los prerequisitos, comprueba que `.env` esté correctamente configurado, arranca el stack y espera a que MLflow esté listo.

La imagen de MLflow se construye automáticamente vía GitHub Actions y se publica en GitHub Container Registry. Coolify simplemente hace pull de la imagen — no necesita hacer build del Dockerfile. Para desarrollo local, `make up` usa `docker-compose.dev.yml` que añade el build local.

La UI de MLflow estará disponible en `https://<DOMAIN>` (el valor de la variable `DOMAIN` en tu `.env`).

## Operación diaria — vía Makefile

```bash
# Arrancar / parar / reiniciar
make up
make down
make restart

# Ver estado y logs
make ps
make logs                  # todos los servicios
make logs-mlflow           # solo MLflow
make stats                 # uso de CPU/memoria
make health                # healthcheck de todos los servicios

# Gestión de usuarios
make user-add USER=john PASS=secret
make user-list
make user-del USER=john

# Backup
make backup                # PostgreSQL → backups/
make backup-ls             # listar backups locales
make backup-minio          # mirror de artefactos MinIO
```

## Gestión de usuarios

Cada científico de datos o servicio tiene sus propias credenciales. Los permisos (READ / EDIT / MANAGE) se asignan por experimento desde la UI de MLflow.

### Crear usuarios

```bash
# Vía Makefile
make user-add USER=alicia PASS=secreto123
make user-add USER=bruno  PASS=clave456
make user-list
make user-del USER=bruno

# O directamente con los scripts
./scripts/add-user.sh <usuario> <password>
./scripts/list-users.sh
./scripts/remove-user.sh <usuario>
```

### Flujo completo: usuario nuevo + permisos + SDK

```bash
# 1. El admin crea el usuario
make user-add USER=carlos PASS=clave_segura

# 2. El admin asigna permisos en la UI de MLflow:
#    https://<DOMAIN>
#    → Experimentos → seleccionar experimento → Permissions → Add user
#    → carlos: READ / EDIT / MANAGE

# 3. Carlos configura su cliente y ya puede trabajar
export MLFLOW_TRACKING_URI=https://<DOMAIN>
export MLFLOW_TRACKING_USERNAME=carlos
export MLFLOW_TRACKING_PASSWORD=clave_segura

python train.py
```

### Niveles de permiso

| Permiso | UI | SDK |
|---|---|---|
| **READ** | Ver experimentos, runs y métricas | `mlflow.search_runs()`, `mlflow.load_model()` |
| **EDIT** | Todo lo de READ + registrar runs | `mlflow.log_metric()`, `mlflow.log_artifact()` |
| **MANAGE** | Todo lo de EDIT + gestionar permisos | `mlflow.register_model()`, asignar permisos via API |

Si un usuario con solo READ intenta loggear métricas, MLflow devuelve un error 403.

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

## Operaciones remotas (SSH a Coolify)

```bash
# Conectarse al servidor
make ssh

# Ver estado en producción
make remote-ps
make remote-logs
make remote-health

# Gestión de usuarios en producción
make remote-user-add USER=john PASS=secret
make remote-user-list
make remote-user-del USER=john

# Backup en producción y descargarlo
make remote-backup
make remote-fetch-backup

# Reiniciar / redesplegar en producción
make remote-restart
make remote-deploy
```

Configurar credenciales SSH y ruta remota si difieren de los defaults:
```bash
make remote-ps SSH_HOST=user@other-host REMOTE_PATH=/opt/mlflow
```

## Uso con el SDK de Python

Cada usuario usa sus propias credenciales (ver [Gestión de usuarios](#gestión-de-usuarios)). Necesitarás al menos permiso **EDIT** sobre el experimento para registrar runs.

### Configuración del cliente

```bash
pip install mlflow

# Credenciales del usuario (creado previamente con make user-add)
export MLFLOW_TRACKING_URI=https://<DOMAIN>
export MLFLOW_TRACKING_USERNAME=carlos
export MLFLOW_TRACKING_PASSWORD=clave_segura
```

### Ejemplo básico: tracking de un experimento

```python
import mlflow

mlflow.set_tracking_uri("https://<DOMAIN>")

# El experimento se crea automáticamente si no existe.
# El usuario necesita permiso EDIT para registrar runs en él.
mlflow.set_experiment("classification-breast-cancer")

with mlflow.start_run(run_name="baseline-random-forest"):
    # Hiperparámetros
    mlflow.log_params({
        "model_type": "random_forest",
        "n_estimators": 100,
        "max_depth": 10,
    })

    # Métricas (puedes loggear varias iteraciones)
    for epoch in range(10):
        mlflow.log_metrics({
            "accuracy": 0.75 + epoch * 0.02,
            "f1_score": 0.73 + epoch * 0.02,
            "loss": 0.5 - epoch * 0.04,
        }, step=epoch)

    # Artefactos: modelos, plots, informes...
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots()
    ax.plot([0.75 + i * 0.02 for i in range(10)], label="accuracy")
    ax.set_xlabel("epoch")
    ax.legend()
    fig.savefig("training_curve.png")
    mlflow.log_artifact("training_curve.png")

    # Guardar el modelo entrenado
    from sklearn.ensemble import RandomForestClassifier
    model = RandomForestClassifier(n_estimators=100, max_depth=10)
    # model.fit(X_train, y_train)  # en un caso real
    mlflow.sklearn.log_model(model, "model")

print(f"Run registrado: {mlflow.active_run().info.run_id}")
```

### Registrar un modelo en el Model Registry

```python
import mlflow

mlflow.set_tracking_uri("https://<DOMAIN>")

client = mlflow.tracking.MlflowClient()

# Buscar el mejor run por métrica
runs = client.search_runs(
    experiment_ids=["1"],
    order_by=["metrics.accuracy DESC"],
    max_results=1,
)

if runs:
    best_run = runs[0]
    model_uri = f"runs:/{best_run.info.run_id}/model"
    result = mlflow.register_model(model_uri, "breast-cancer-classifier")
    print(f"Modelo registrado v{result.version}: {result.name}")

    # Transicionar a producción
    client.transition_model_version_stage(
        name="breast-cancer-classifier",
        version=result.version,
        stage="Production",
    )
```

### Cargar un modelo desde el registry y servir inferencia

```python
import mlflow

mlflow.set_tracking_uri("https://<DOMAIN>")

# Cargar la última versión en producción
model = mlflow.pyfunc.load_model("models:/breast-cancer-classifier/Production")

# Inferencia
import numpy as np
sample = np.array([[5.1, 3.5, 1.4, 0.2]])
prediction = model.predict(sample)
print(f"Predicción: {prediction}")
```

Consulta los experimentos, runs y modelos registrados en la UI: `https://<DOMAIN>`.

## Actualizar el stack

```bash
git pull
make build                   # reconstruir imagen MLflow localmente
make up
```

En producción, cada push a `main` dispara el workflow de GitHub Actions: shellcheck → build → push a GHCR → notificar a Coolify para redesplegar automáticamente.

### Configurar el auto-deploy en Coolify

Añade estas variables en **Settings → Secrets and variables → Actions** del repositorio:

| Variable | Tipo | Descripción |
|---|---|---|
| `COOLIFY_DEPLOY_UUID` | Variable | UUID del deployment en Coolify (en la URL del servicio) |
| `COOLIFY_URL` | Variable | URL base de la API de Coolify (ej: `https://coolify.tu-servidor.com`) |
| `COOLIFY_TOKEN` | Secret | Token de API de Coolify (Settings → API Tokens) |

Si no se configuran `COOLIFY_DEPLOY_UUID` y `COOLIFY_URL`, el paso de deploy se salta y Coolify deberá detectar el cambio por polling o webhook propio.

## Estructura del repositorio

```
├── docker-compose.yml          # Orquestación de servicios (producción, imagen GHCR)
├── docker-compose.dev.yml      # Override de desarrollo (build local)
├── Makefile                    # Operaciones de mantenimiento (local + remoto vía SSH)
├── .env.example                # Plantilla de variables de entorno
├── .github/
│   └── workflows/ci.yml        # CI/CD: shellcheck + build + push a GHCR
├── mlflow/
│   ├── Dockerfile              # Imagen custom MLflow (python:3.12-slim)
│   └── entrypoint.sh           # Genera auth config, migra BD y arranca servidor
└── scripts/
    ├── setup.sh                # Setup inicial (primera vez)
    ├── add-user.sh             # Añadir usuario MLflow
    ├── remove-user.sh          # Eliminar usuario MLflow
    ├── list-users.sh           # Listar usuarios MLflow
    └── backup.sh               # Backup de PostgreSQL
```
