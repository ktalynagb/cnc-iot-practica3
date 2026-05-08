#!/usr/bin/env bash
# Deploy/02_backend.sh
# ============================================================
# FLUX CNC IoT — Práctica 3
# Deploy de Azure Functions (backend serverless)
#
# Crea/actualiza:
#   - Azure Function App (Python 3.11, consumption plan)
#   - App settings con connection strings de IoT Hub y Cosmos DB
#   - Publica el código de azure-functions/ en la Function App
#
# Prerequisitos:
#   - 01_infraestructura.sh ejecutado (infra_outputs.env presente)
#   - Azure Functions Core Tools: npm install -g azure-functions-core-tools@4
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/infra_outputs.env"

# ── Cargar outputs de infraestructura ─────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[02_backend] ERROR: '$ENV_FILE' no encontrado. Ejecuta 01_infraestructura.sh primero." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ── Variables ─────────────────────────────────────────────────────────────────
FUNC_APP_NAME="${FUNC_APP_NAME:-cnc-iot-func}"
PYTHON_VERSION="3.11"
FUNC_SRC="$REPO_ROOT/azure-functions"

log()  { echo "[02_backend] $*"; }
ok()   { echo "[02_backend] ✓ $*"; }
warn() { echo "[02_backend] ⚠ $*"; }

# ── Validar herramientas ───────────────────────────────────────────────────────
if ! command -v func &>/dev/null; then
  echo "[02_backend] ERROR: 'func' (Azure Functions Core Tools) no está instalado." >&2
  echo "  Instala con: npm install -g azure-functions-core-tools@4" >&2
  exit 1
fi

# ── 1. Crear Function App ─────────────────────────────────────────────────────
log "Verificando Function App '$FUNC_APP_NAME'..."
if az functionapp show \
     --name "$FUNC_APP_NAME" \
     --resource-group "$RG_NAME" &>/dev/null; then
  warn "Function App '$FUNC_APP_NAME' ya existe — omitiendo creación."
else
  az functionapp create \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RG_NAME" \
    --storage-account "$FUNC_STORAGE" \
    --consumption-plan-location "$LOCATION" \
    --runtime python \
    --runtime-version "$PYTHON_VERSION" \
    --functions-version 4 \
    --os-type Linux \
    --output none
  ok "Function App '$FUNC_APP_NAME' creada (Python $PYTHON_VERSION, consumption plan)."
fi

# ── 2. Configurar App Settings (connection strings y umbrales) ────────────────
log "Configurando app settings en '$FUNC_APP_NAME'..."
az functionapp config appsettings set \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RG_NAME" \
  --settings \
    "IOTHUB_CONNECTION_STRING=${IOTHUB_CONNECTION_STRING}" \
    "IOTHUB_SERVICE_CONNECTION_STRING=${IOTHUB_SERVICE_CONNECTION_STRING}" \
    "COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
    "COSMOS_DATABASE=${COSMOS_DB}" \
    "COSMOS_CONTAINER=${COSMOS_CONTAINER}" \
    "IOT_DEVICE_ID=${IOT_DEVICE_ID}" \
    "TEMP_MIN=15.0" \
    "TEMP_MAX=45.0" \
    "HUM_MIN=20.0" \
    "HUM_MAX=80.0" \
    "ACCEL_MAX=2.0" \
  --output none
ok "App settings configurados."

# ── 3. Habilitar CORS en Function App ────────────────────────────────────────
log "Configurando CORS en Function App..."
# Si ya tenemos la URL del frontend, la usamos; de lo contrario usamos "*" como fallback
# para que el dashboard pueda cargarse antes de conocer la URL definitiva.
# Ejecutar 03_frontend_hosting.sh actualizará CORS con la URL real del frontend.
CORS_ORIGIN="${FRONTEND_URL:-*}"
az functionapp cors add \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RG_NAME" \
  --allowed-origins "$CORS_ORIGIN" \
  --output none
ok "CORS configurado (origen: $CORS_ORIGIN)."

# ── 4. Publicar código con func CLI ──────────────────────────────────────────
log "Publicando código desde '$FUNC_SRC'..."
if [[ ! -d "$FUNC_SRC" ]]; then
  echo "[02_backend] ERROR: Directorio '$FUNC_SRC' no encontrado." >&2
  exit 1
fi

cd "$FUNC_SRC"
func azure functionapp publish "$FUNC_APP_NAME" \
  --python \
  --build remote
ok "Código publicado en '$FUNC_APP_NAME'."

# ── 5. Mostrar URL base de la Function App ────────────────────────────────────
FUNC_URL=$(az functionapp show \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RG_NAME" \
  --query "defaultHostName" \
  --output tsv)

FUNC_BASE_URL="https://${FUNC_URL}/api"

# Actualizar infra_outputs.env con la URL del backend
{
  grep -v "^FUNC_APP_NAME=" "$ENV_FILE" | grep -v "^FUNC_BASE_URL=" || true
} > "$ENV_FILE.tmp"
{
  cat "$ENV_FILE.tmp"
  echo "FUNC_APP_NAME=\"${FUNC_APP_NAME}\""
  echo "FUNC_BASE_URL=\"${FUNC_BASE_URL}\""
} > "$ENV_FILE"
rm -f "$ENV_FILE.tmp"

ok "URL del backend: $FUNC_BASE_URL"
log "Endpoints disponibles:"
log "  GET  $FUNC_BASE_URL/datos"
log "  GET  $FUNC_BASE_URL/datos/csv"
log "  POST $FUNC_BASE_URL/actuador"
log "============================================================"
log "02_backend.sh completado exitosamente."
log "============================================================"
