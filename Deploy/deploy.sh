#!/usr/bin/env bash
# Deploy/deploy.sh
# ============================================================
# FLUX CNC IoT — Práctica 3
# ORQUESTADOR PRINCIPAL — Ejecuta todos los módulos en orden:
#
#   1. 01_infraestructura.sh  → crea recursos Azure
#   2. 02_backend.sh          → despliega Azure Functions
#   3. 03_frontend_hosting.sh → publica el dashboard estático
#
# Uso:
#   ./deploy.sh                        # deploy completo
#   ./deploy.sh --skip-infra           # omite paso 1 (infra ya existe)
#   ./deploy.sh --skip-backend         # omite paso 2
#   ./deploy.sh --skip-frontend        # omite paso 3
#   ./deploy.sh --only-infra           # solo paso 1
#   ./deploy.sh --only-backend         # solo paso 2
#   ./deploy.sh --only-frontend        # solo paso 3
#
# Variables de entorno opcionales (anular nombres generados):
#   FUNC_STORAGE    — nombre del storage account para Functions
#   FRONTEND_SA     — nombre del storage account para el frontend
#   FUNC_APP_NAME   — nombre de la Function App
#
# Prerequisitos:
#   az login && az account set --subscription "<SUBSCRIPTION_ID>"
#   npm install -g azure-functions-core-tools@4   (para --skip-infra no)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parseo de argumentos ──────────────────────────────────────────────────────
RUN_INFRA=true
RUN_BACKEND=true
RUN_FRONTEND=true

for arg in "$@"; do
  case "$arg" in
    --skip-infra)    RUN_INFRA=false ;;
    --skip-backend)  RUN_BACKEND=false ;;
    --skip-frontend) RUN_FRONTEND=false ;;
    --only-infra)    RUN_BACKEND=false; RUN_FRONTEND=false ;;
    --only-backend)  RUN_INFRA=false;   RUN_FRONTEND=false ;;
    --only-frontend) RUN_INFRA=false;   RUN_BACKEND=false ;;
    --help|-h)
      sed -n '/^# Uso:/,/^#$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "[deploy] Argumento desconocido: '$arg'. Usa --help para ver opciones." >&2
      exit 1
      ;;
  esac
done

log()  { echo ""; echo "══════════════════════════════════════════════════"; echo "[deploy] $*"; echo "══════════════════════════════════════════════════"; }
ok()   { echo "[deploy] ✓ $*"; }
err()  { echo "[deploy] ✗ ERROR: $*" >&2; }

# ── Verificar az CLI autenticado ──────────────────────────────────────────────
if ! az account show &>/dev/null; then
  err "No estás autenticado en Azure CLI."
  echo "  Ejecuta: az login && az account set --subscription '<ID>'"
  exit 1
fi

ACCOUNT=$(az account show --query "name" --output tsv)
ok "Azure CLI autenticado — suscripción: '$ACCOUNT'"

START_TIME=$(date +%s)

# ── Paso 1: Infraestructura ───────────────────────────────────────────────────
if [[ "$RUN_INFRA" == "true" ]]; then
  log "PASO 1/3 — Provisionando infraestructura Azure..."
  bash "$SCRIPT_DIR/01_infraestructura.sh"
  ok "Infraestructura lista."
else
  echo "[deploy] ⚠ Paso 1 (infraestructura) omitido."
fi

# ── Paso 2: Backend (Azure Functions) ────────────────────────────────────────
if [[ "$RUN_BACKEND" == "true" ]]; then
  log "PASO 2/3 — Desplegando backend (Azure Functions)..."
  bash "$SCRIPT_DIR/02_backend.sh"
  ok "Backend desplegado."
else
  echo "[deploy] ⚠ Paso 2 (backend) omitido."
fi

# ── Paso 3: Frontend (Static Website) ────────────────────────────────────────
if [[ "$RUN_FRONTEND" == "true" ]]; then
  log "PASO 3/3 — Publicando frontend (Static Website)..."
  bash "$SCRIPT_DIR/03_frontend_hosting.sh"
  ok "Frontend publicado."
else
  echo "[deploy] ⚠ Paso 3 (frontend) omitido."
fi

# ── Resumen final ─────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

ENV_FILE="$SCRIPT_DIR/infra_outputs.env"
echo ""
echo "══════════════════════════════════════════════════"
echo "[deploy] ✓ DEPLOY COMPLETO en ${ELAPSED}s"
echo "══════════════════════════════════════════════════"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  echo ""
  echo "  🌐 Frontend (Dashboard):  ${FRONTEND_URL:-n/a}"
  echo "  ⚡ Backend (API base):    ${FUNC_BASE_URL:-n/a}"
  echo "  📡 IoT Hub:               ${IOT_HUB_NAME:-n/a}"
  echo "  🗄  Cosmos DB:             ${COSMOS_NAME:-n/a}"
  echo ""
  echo "  Los connection strings y URLs están en:"
  echo "  $ENV_FILE"
fi
echo ""
echo "  Para limpiar todos los recursos:"
echo "  bash $SCRIPT_DIR/04_cleanup.sh"
echo "══════════════════════════════════════════════════"
