# ──────────────────────────────────────────────────────────────────────────────
# Makefile — MLflow Production Stack
#
# Operaciones de mantenimiento locales y remotas (vía SSH a Coolify).
#
# Uso:
#   make [target] [VAR=value]
#
#   Local:      make up | make logs | make user-list | make backup
#   Remoto:     make remote-ps | make remote-logs | make remote-backup
#   SSH:        make ssh
# ──────────────────────────────────────────────────────────────────────────────

SHELL  := /bin/bash

# ── Remote server (Coolify) ────────────────────────────────────────────────────
SSH_HOST    ?= deploy@xapilopex.es
REMOTE_PATH ?= /home/deploy/mlflow-production-stack
SSH_CMD     := ssh $(SSH_HOST)
REMOTE_RUN  := $(SSH_CMD) "cd $(REMOTE_PATH) &&"

# ── Docker compose ─────────────────────────────────────────────────────────────
# Local: usa docker-compose.dev.yml para build local de la imagen
# Coolify: solo docker-compose.yml (imagen prebuilt de GHCR)
COMPOSE := docker compose -f docker-compose.yml -f docker-compose.dev.yml

# ── Load .env for local operations ─────────────────────────────────────────────
ENVFILE := .env
ifeq ($(wildcard $(ENVFILE)),$(ENVFILE))
include $(ENVFILE)
export
endif

.DEFAULT_GOAL := help

# ═══════════════════════════════════════════════════════════════════════════════
# Help
# ═══════════════════════════════════════════════════════════════════════════════

help: ## Show this help message
	@echo "MLflow Production Stack — $$([ -f .env ] && . .env && echo $$DOMAIN || echo 'no .env loaded')"
	@echo ""
	@echo "Usage: make [target] [VAR=value]"
	@echo ""
	@grep -E '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'

# ═══════════════════════════════════════════════════════════════════════════════
# Stack lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

up:         ## Start the full stack (build + up)
	$(COMPOSE) up -d --build

down:       ## Stop all containers
	$(COMPOSE) down

restart:    ## Stop and restart all services
	$(COMPOSE) down && $(COMPOSE) up -d --build

build:      ## Rebuild images (no cache)
	$(COMPOSE) build --no-cache

pull:       ## Pull latest base images
	$(COMPOSE) pull

# ═══════════════════════════════════════════════════════════════════════════════
# Status & Monitoring
# ═══════════════════════════════════════════════════════════════════════════════

ps:         ## Show container status
	$(COMPOSE) ps

logs:       ## Follow all logs (SERVICE=name to filter)
	$(COMPOSE) logs -f $(SERVICE)

logs-mlflow:   ## Follow MLflow logs
	$(COMPOSE) logs -f mlflow

logs-postgres: ## Follow PostgreSQL logs
	$(COMPOSE) logs -f postgres

logs-minio:    ## Follow MinIO logs
	$(COMPOSE) logs -f minio

stats:      ## Show container CPU/mem usage
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $$(docker compose ps -q)

health:     ## Check health endpoints
	@echo -n "MLflow:       "
	@curl -sSf -o /dev/null -w '%{http_code}\n' http://localhost:5000/health 2>/dev/null || echo "DOWN"
	@echo -n "MinIO:        "
	@curl -sSf -o /dev/null -w '%{http_code}\n' http://localhost:9000/minio/health/live 2>/dev/null || echo "DOWN"
	@echo -n "PostgreSQL:   "
	@$(COMPOSE) exec -T postgres pg_isready -U $(POSTGRES_USER) -d $(POSTGRES_DB) 2>/dev/null || echo "DOWN"

# ═══════════════════════════════════════════════════════════════════════════════
# User management
# ═══════════════════════════════════════════════════════════════════════════════

user-add:   ## Create MLflow user (USER=name PASS=password required)
	@test -n "$(USER)" || { echo "ERROR: USER is required — make user-add USER=john PASS=secret"; exit 1; }
	@test -n "$(PASS)" || { echo "ERROR: PASS is required — make user-add USER=john PASS=secret"; exit 1; }
	./scripts/add-user.sh "$(USER)" "$(PASS)"

user-del:   ## Delete MLflow user (USER=name required)
	@test -n "$(USER)" || { echo "ERROR: USER is required — make user-del USER=john"; exit 1; }
	./scripts/remove-user.sh "$(USER)"

user-list:  ## List all MLflow users
	./scripts/list-users.sh

# ═══════════════════════════════════════════════════════════════════════════════
# Backup
# ═══════════════════════════════════════════════════════════════════════════════

backup:     ## Dump PostgreSQL to backups/ (timestamped .sql.gz)
	./scripts/backup.sh

backup-minio: ## Mirror MinIO artifacts to backups/minio/
	./scripts/backup-minio.sh

backup-all: backup backup-minio ## Run both PostgreSQL and MinIO backups
	@echo "Full backup completed."

backup-ls:  ## List local backup files
	@if ls backups/mlflow_*.sql.gz >/dev/null 2>&1; then \
		ls -lh backups/mlflow_*.sql.gz; \
	else \
		echo "No backups found in backups/"; \
	fi

# ═══════════════════════════════════════════════════════════════════════════════
# Shell & Debugging
# ═══════════════════════════════════════════════════════════════════════════════

shell-mlflow:   ## Open bash in MLflow container
	$(COMPOSE) exec mlflow bash

shell-postgres: ## Open bash in PostgreSQL container
	$(COMPOSE) exec postgres bash

shell-minio:    ## Open sh in MinIO container
	$(COMPOSE) exec minio sh

db-cli:     ## Open psql session to MLflow database
	$(COMPOSE) exec postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

db-size:    ## Show PostgreSQL database size
	$(COMPOSE) exec -T postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database WHERE datname='$(POSTGRES_DB)';"

db-top:     ## Show running queries and connections
	$(COMPOSE) exec -T postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		-c "SELECT pid, state, query_start, LEFT(query, 80) FROM pg_stat_activity WHERE datname='$(POSTGRES_DB)' AND state != 'idle' ORDER BY query_start;"

# ═══════════════════════════════════════════════════════════════════════════════
# Remote operations (Coolify via SSH)
# ═══════════════════════════════════════════════════════════════════════════════

ssh:        ## Open SSH session to production server
	$(SSH_CMD)

remote-ps:  ## Show container status on production
	$(REMOTE_RUN) docker compose ps"

remote-logs: ## Follow logs on production (SERVICE=name optional)
	$(REMOTE_RUN) docker compose logs -f $(SERVICE)"

remote-health: ## Check health on production
	$(REMOTE_RUN) \
		curl -sf -o /dev/null -w 'MLflow: %{http_code}\n' http://localhost:5000/health; \
		curl -sf -o /dev/null -w 'MinIO:  %{http_code}\n' http://localhost:9000/minio/health/live"

remote-stats: ## Show container resource usage on production
	$(REMOTE_RUN) docker stats --no-stream"

remote-user-list: ## List MLflow users on production
	$(REMOTE_RUN) ./scripts/list-users.sh"

remote-user-add: ## Create user on production (USER=name PASS=password)
	@test -n "$(USER)" || { echo "ERROR: USER is required"; exit 1; }
	@test -n "$(PASS)" || { echo "ERROR: PASS is required"; exit 1; }
	$(REMOTE_RUN) ./scripts/add-user.sh $(USER) $(PASS)"

remote-user-del: ## Delete user on production (USER=name)
	@test -n "$(USER)" || { echo "ERROR: USER is required"; exit 1; }
	$(REMOTE_RUN) ./scripts/remove-user.sh $(USER)"

remote-backup: ## Run database backup on production
	$(REMOTE_RUN) ./scripts/backup.sh"

remote-backup-minio: ## Mirror MinIO artifacts on production
	$(REMOTE_RUN) ./scripts/backup-minio.sh"

remote-fetch-backup: ## Download latest database backup from production
	@mkdir -p backups
	@LATEST=$$($(SSH_CMD) "ls -t $(REMOTE_PATH)/backups/mlflow_*.sql.gz 2>/dev/null | head -1"); \
	if [ -n "$$LATEST" ]; then \
		scp "$(SSH_HOST):$$LATEST" backups/; \
		echo "Fetched: $$(basename $$LATEST)"; \
	else \
		echo "No backups found on production"; \
	fi

remote-fetch-minio: ## Rsync MinIO backup from production
	@mkdir -p backups/minio
	rsync -avz --progress $(SSH_HOST):$(REMOTE_PATH)/backups/minio/ backups/minio/

remote-restart: ## Restart the stack on production
	$(REMOTE_RUN) docker compose down && docker compose up -d --build"

remote-deploy:  ## Full rebuild and restart on production
	$(REMOTE_RUN) docker compose down && docker compose build --no-cache && docker compose up -d"

remote-tail-logs: ## Tail last 200 log lines on production (SERVICE=name)
	$(REMOTE_RUN) docker compose logs --tail=200 $(SERVICE)"

# ═══════════════════════════════════════════════════════════════════════════════
# Cleanup
# ═══════════════════════════════════════════════════════════════════════════════

clean:      ## Stop containers and REMOVE volumes (DESTRUCTIVE!)
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║  WARNING: This removes ALL data (PostgreSQL + MinIO)!      ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@read -r -p "Type 'yes' to confirm: " c; \
	if [ "$$c" != "yes" ]; then echo "Cancelled."; exit 1; fi
	$(COMPOSE) down -v
	@echo "Volumes removed."

prune:      ## Remove unused Docker data (images, containers, networks)
	docker system prune -f

# ═══════════════════════════════════════════════════════════════════════════════
# Setup
# ═══════════════════════════════════════════════════════════════════════════════

setup:      ## Run first-time setup (validates .env, starts stack)
	./scripts/setup.sh

init-env:   ## Copy .env.example → .env if missing
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo ".env created from .env.example — edit it before running 'make setup'"; \
	else \
		echo ".env already exists, skipping."; \
	fi

# ═══════════════════════════════════════════════════════════════════════════════
# Linting & CI
# ═══════════════════════════════════════════════════════════════════════════════

lint:       ## Run ShellCheck on all scripts
	@command -v shellcheck >/dev/null 2>&1 || { echo "ERROR: shellcheck not installed. Install: apt install shellcheck"; exit 1; }
	shellcheck --severity=warning scripts/*.sh
	@echo "OK"
