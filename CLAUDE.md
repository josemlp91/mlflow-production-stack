# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production deployment of an MLflow tracking server using Docker Compose. The stack uses Nginx for TLS termination (Let's Encrypt), MLflow's native multi-user authentication, PostgreSQL for metadata persistence, and MinIO for S3-compatible artifact storage.

## Architecture

```
Internet / External CPD
        │
        ▼
   Nginx :443  (TLS — xapilopex.es)
        │
        ▼
   MLflow :5000  ──────►  PostgreSQL :5432
        │
        ▼
   MinIO :9000
```

Only Nginx exposes ports to the outside world (80 and 443). All other services communicate on an internal Docker bridge network (`mlflow_net`).

## Repository Structure

```
├── docker-compose.yml          # Primary entrypoint — defines all services
├── .env.example                # Required environment variable template
├── mlflow/
│   ├── Dockerfile              # Custom MLflow image (python:3.12-slim base)
│   └── entrypoint.sh           # Generates auth config, runs DB migrations, starts server
├── nginx/
│   ├── conf.d/mlflow.conf      # HTTP→HTTPS redirect, ACME challenge, TLS proxy
│   └── certbot/www/            # Webroot for Let's Encrypt ACME challenge (bind-mounted)
└── scripts/
    ├── setup.sh                # First-time setup: TLS cert + full stack bootstrap
    ├── add-user.sh             # Create MLflow user via REST API
    ├── remove-user.sh          # Delete MLflow user via REST API
    ├── list-users.sh           # List all MLflow users
    ├── backup.sh               # PostgreSQL dump → ./backups/
    └── renew-certs.sh          # Certbot renewal + Nginx reload (for crontab)
```

## Service Versions

| Service   | Image                                      |
|-----------|--------------------------------------------|
| MLflow    | Custom build — `mlflow==2.20.0` on `python:3.12-slim` |
| PostgreSQL| `postgres:16-alpine`                       |
| MinIO     | `minio/minio:RELEASE.2025-04-22T22-12-26Z` |
| Nginx     | `nginx:1.27-alpine`                        |
| Certbot   | `certbot/certbot:latest`                   |

## Key Design Decisions

- **Authentication**: MLflow native auth (`--app-name basic-auth`), not Nginx HTTP Basic Auth. Users have individual credentials with per-experiment permission levels (READ / EDIT / MANAGE).
- **Artifact storage**: MinIO (S3-compatible, self-hosted). MLflow connects via `MLFLOW_S3_ENDPOINT_URL=http://minio:9000`.
- **Auth config**: `mlflow/entrypoint.sh` generates `/tmp/basic_auth.ini` at container start from env vars. The admin password in the ini is only used on first boot to seed the user database.
- **TLS bootstrap**: `setup.sh` creates a temporary self-signed certificate so Nginx can start, then obtains the real Let's Encrypt certificate via certbot webroot method, then reloads Nginx.
- **Certbot profile**: The `certbot` service uses `profiles: [certbot]` — it does NOT start with `docker compose up`. Only invoked from `setup.sh` and `renew-certs.sh`.
- **Healthchecks**: All services with dependants declare healthchecks. `depends_on: condition: service_healthy` ensures correct startup order.

## Key Constraints

- TLS certificates are in `./certbot/conf/` (bind-mounted, gitignored). Nginx and Certbot both mount this directory.
- All credentials are in `.env` (gitignored). Never hardcode secrets.
- The domain `xapilopex.es` is hardcoded in `nginx/conf.d/mlflow.conf`. If the domain changes, update that file and re-run `setup.sh`.
- Nginx `client_max_body_size` is set to `512m` to allow uploading large ML artifacts.
- Proxy timeouts are set to `600s` to handle long-running training jobs reporting metrics.

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

# Certificate renewal
./scripts/renew-certs.sh
```

## Connecting from an External CPD

```bash
export MLFLOW_TRACKING_URI=https://xapilopex.es
export MLFLOW_TRACKING_USERNAME=<username>
export MLFLOW_TRACKING_PASSWORD=<password>
```

## Environment Variables

All required variables are documented in `.env.example`. Key ones:

| Variable              | Purpose                                              |
|-----------------------|------------------------------------------------------|
| `DOMAIN`              | Public domain (xapilopex.es)                         |
| `CERTBOT_EMAIL`       | Let's Encrypt notification email                     |
| `POSTGRES_*`          | PostgreSQL credentials                               |
| `MLFLOW_ADMIN_*`      | Initial MLflow admin user                            |
| `MLFLOW_SECRET_KEY`   | Flask session signing key (generate with `secrets.token_hex(32)`) |
| `MINIO_ROOT_*`        | MinIO admin credentials (also used as S3 access keys)|
| `MINIO_BUCKET`        | Artifact bucket name (`mlflow-artifacts`)            |
