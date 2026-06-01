# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production deployment of an MLflow tracking server using Docker Compose. The stack uses Coolify (Traefik) for TLS termination and reverse proxying, MLflow's native multi-user authentication, PostgreSQL for metadata persistence, and MinIO for S3-compatible artifact storage.

## Architecture

```
Internet / External CPD
        │
        ▼
   Coolify :443  (TLS — mlflow.pathologyprediction.es)
        │
        ▼
   MLflow :5000  ──────►  PostgreSQL :5432
        │
        ▼
   MinIO :9000
```

All services communicate on an internal Docker bridge network (`mlflow_net`). Coolify handles TLS termination and routes traffic to MLflow.

## Repository Structure

```
├── docker-compose.yml          # Primary entrypoint — defines all services (prod: GHCR image)
├── docker-compose.dev.yml      # Local dev override — adds build context
├── .env.example                # Required environment variable template
├── Makefile                    # Maintenance operations (local + SSH to Coolify)
├── .github/
│   └── workflows/ci.yml        # CI/CD: shellcheck lint + build + push to GHCR
├── mlflow/
│   ├── Dockerfile              # Custom MLflow image (python:3.12-slim base)
│   └── entrypoint.sh           # Generates auth config, runs DB migrations, starts server
└── scripts/
    ├── setup.sh                # First-time setup: validates env, starts stack
    ├── add-user.sh             # Create MLflow user via REST API
    ├── remove-user.sh          # Delete MLflow user via REST API
    ├── list-users.sh           # List all MLflow users
    └── backup.sh               # PostgreSQL dump → ./backups/
```

## Service Versions

| Service   | Image                                      |
|-----------|--------------------------------------------|
| MLflow    | Prebuilt via CI — `ghcr.io/josemlp91/mlflow-production-stack/mlflow:latest` (base: `python:3.12-slim`) |
| PostgreSQL| `postgres:16-alpine`                       |
| MinIO     | `minio/minio:RELEASE.2025-04-22T22-12-26Z` |

## Key Design Decisions

- **Authentication**: MLflow native auth (`--app-name basic-auth`), not Nginx HTTP Basic Auth. Users have individual credentials with per-experiment permission levels (READ / EDIT / MANAGE).
- **Artifact storage**: MinIO (S3-compatible, self-hosted). MLflow connects via `MLFLOW_S3_ENDPOINT_URL=http://minio:9000`.
- **Auth config**: `mlflow/entrypoint.sh` generates `/tmp/basic_auth.ini` at container start from env vars. The admin password in the ini is only used on first boot to seed the user database.
- **TLS**: Coolify manages Let's Encrypt certificates automatically via its Traefik proxy. No manual certbot setup is needed.
- **Image delivery**: A GitHub Actions workflow (`.github/workflows/ci.yml`) runs shellcheck on bash scripts, builds the MLflow Docker image, and pushes it to GitHub Container Registry (`ghcr.io/josemlp91/mlflow-production-stack/mlflow`). Coolify pulls the prebuilt image — it never builds the Dockerfile.
- **Local dev**: `docker-compose.dev.yml` adds a `build:` context. Use `make up` (which composes both files) for local development.
- **Healthchecks**: All services with dependants declare healthchecks. `depends_on: condition: service_healthy` ensures correct startup order.

## Key Constraints

- TLS certificates are managed automatically by Coolify (Traefik).
- All credentials are in `.env` (gitignored). Never hardcode secrets.

## Common Operations

```bash
# First-time setup (run once on the server)
./scripts/setup.sh

# Start / stop
docker compose up -d
docker compose down

# Logs
docker compose logs -f [service]

# User management
./scripts/add-user.sh <username> <password>
./scripts/list-users.sh
./scripts/remove-user.sh <username>

# Backup
./scripts/backup.sh

```

## Connecting from an External CPD

```bash
export MLFLOW_TRACKING_URI=https://mlflow.pathologyprediction.es
export MLFLOW_TRACKING_USERNAME=<username>
export MLFLOW_TRACKING_PASSWORD=<password>
```

## Environment Variables

All required variables are documented in `.env.example`. Key ones:

| Variable              | Purpose                                              |
|-----------------------|------------------------------------------------------|
| `DOMAIN`              | Public domain (mlflow.pathologyprediction.es)                         |
| `CERTBOT_EMAIL`       | Let's Encrypt notification email                     |
| `POSTGRES_*`          | PostgreSQL credentials                               |
| `MLFLOW_ADMIN_*`      | Initial MLflow admin user                            |
| `MLFLOW_SECRET_KEY`   | Flask session signing key (generate with `secrets.token_hex(32)`) |
| `MINIO_ROOT_*`        | MinIO admin credentials (also used as S3 access keys)|
| `MINIO_BUCKET`        | Artifact bucket name (`mlflow-artifacts`)            |
