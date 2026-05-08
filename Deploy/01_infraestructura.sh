#!/usr/bin/env bash
# Deploy/01_infraestructura.sh
# ============================================================
# FLUX CNC IoT — Práctica 3
# Provisionamiento de infraestructura Azure (idempotente)
#
# Crea:
#   - Resource Group
#   - Azure IoT Hub (F1 free tier)
#   - Dispositivo IoT (ESP32)
#   - Cosmos DB account + base de datos + contenedor
#   - Storage Account para Azure Functions
#   - Storage Account para Static Website (frontend)
#
# Prerequisitos:
#   az login && az account set --subscription "<ID>"
# ============================================================
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
RG_NAME="rg-cnc-iot"
LOCATION="centralus"
IOT_HUB_NAME="cnc-iot-hub"
COSMOS_NAME="cnc-iot-cosmos"
COSMOS_DB="cnc_iot"
COSMOS_CONTAINER="lecturas"
IOT_DEVICE_ID="esp32-cnc1"

# Nombres de storage accounts (3-24 chars, solo minúsculas y números)
FUNC_STORAGE="${FUNC_STORAGE:-cnciotfunc$(head -c4 /dev/urandom | xxd -p)}"
FRONTEND_SA="${FRONTEND_SA:-cnciotfront$(head -c4 /dev/urandom | xxd -p)}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[01_infra] $*"; }
ok()   { echo "[01_infra] ✓ $*"; }
warn() { echo "[01_infra] ⚠ $*"; }

# ── 1. Resource Group ─────────────────────────────────────────────────────────
log "Verificando resource group '$RG_NAME'..."
if az group show --name "$RG_NAME" &>/dev/null; then
  warn "Resource group '$RG_NAME' ya existe — omitiendo creación."
else
  az group create --name "$RG_NAME" --location "$LOCATION" --output none
  ok "Resource group '$RG_NAME' creado en '$LOCATION'."
fi

# ── 2. IoT Hub ────────────────────────────────────────────────────────────────
log "Verificando IoT Hub '$IOT_HUB_NAME'..."
if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RG_NAME" &>/dev/null; then
  warn "IoT Hub '$IOT_HUB_NAME' ya existe — omitiendo creación."
else
  az iot hub create \
    --name "$IOT_HUB_NAME" \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --sku F1 \
    --partition-count 2 \
    --output none
  ok "IoT Hub '$IOT_HUB_NAME' creado (SKU F1)."
fi

# ── 3. Dispositivo IoT ────────────────────────────────────────────────────────
log "Verificando dispositivo '$IOT_DEVICE_ID' en IoT Hub..."
if az iot hub device-identity show \
     --hub-name "$IOT_HUB_NAME" \
     --device-id "$IOT_DEVICE_ID" &>/dev/null; then
  warn "Dispositivo '$IOT_DEVICE_ID' ya existe — omitiendo creación."
else
  az iot hub device-identity create \
    --hub-name "$IOT_HUB_NAME" \
    --device-id "$IOT_DEVICE_ID" \
    --output none
  ok "Dispositivo '$IOT_DEVICE_ID' registrado en IoT Hub."
fi

# ── 4. Cosmos DB ──────────────────────────────────────────────────────────────
log "Verificando cuenta Cosmos DB '$COSMOS_NAME'..."
if az cosmosdb show --name "$COSMOS_NAME" --resource-group "$RG_NAME" &>/dev/null; then
  warn "Cosmos DB '$COSMOS_NAME' ya existe — omitiendo creación de cuenta."
else
  az cosmosdb create \
    --name "$COSMOS_NAME" \
    --resource-group "$RG_NAME" \
    --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=false \
    --default-consistency-level Session \
    --output none
  ok "Cuenta Cosmos DB '$COSMOS_NAME' creada."
fi

log "Verificando base de datos Cosmos '$COSMOS_DB'..."
if az cosmosdb sql database show \
     --account-name "$COSMOS_NAME" \
     --resource-group "$RG_NAME" \
     --name "$COSMOS_DB" &>/dev/null; then
  warn "Base de datos Cosmos '$COSMOS_DB' ya existe — omitiendo."
else
  az cosmosdb sql database create \
    --account-name "$COSMOS_NAME" \
    --resource-group "$RG_NAME" \
    --name "$COSMOS_DB" \
    --output none
  ok "Base de datos Cosmos '$COSMOS_DB' creada."
fi

log "Verificando contenedor Cosmos '$COSMOS_CONTAINER'..."
if az cosmosdb sql container show \
     --account-name "$COSMOS_NAME" \
     --resource-group "$RG_NAME" \
     --database-name "$COSMOS_DB" \
     --name "$COSMOS_CONTAINER" &>/dev/null; then
  warn "Contenedor '$COSMOS_CONTAINER' ya existe — omitiendo."
else
  az cosmosdb sql container create \
    --account-name "$COSMOS_NAME" \
    --resource-group "$RG_NAME" \
    --database-name "$COSMOS_DB" \
    --name "$COSMOS_CONTAINER" \
    --partition-key-path "/dispositivo" \
    --throughput 400 \
    --output none
  ok "Contenedor Cosmos '$COSMOS_CONTAINER' creado (partition key: /dispositivo)."
fi

# ── 5. Storage Account para Azure Functions ───────────────────────────────────
log "Verificando storage account para Functions '$FUNC_STORAGE'..."
if az storage account show --name "$FUNC_STORAGE" --resource-group "$RG_NAME" &>/dev/null; then
  warn "Storage account '$FUNC_STORAGE' ya existe — omitiendo."
else
  az storage account create \
    --name "$FUNC_STORAGE" \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output none
  ok "Storage account '$FUNC_STORAGE' creado."
fi

# ── 6. Storage Account para Static Website (frontend) ────────────────────────
log "Verificando storage account para frontend '$FRONTEND_SA'..."
if az storage account show --name "$FRONTEND_SA" --resource-group "$RG_NAME" &>/dev/null; then
  warn "Storage account '$FRONTEND_SA' ya existe — omitiendo."
else
  az storage account create \
    --name "$FRONTEND_SA" \
    --resource-group "$RG_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output none
  ok "Storage account '$FRONTEND_SA' creado."
fi

# ── 7. Exportar outputs ───────────────────────────────────────────────────────
IOTHUB_CONN=$(az iot hub connection-string show \
  --hub-name "$IOT_HUB_NAME" \
  --resource-group "$RG_NAME" \
  --policy-name service \
  --query connectionString \
  --output tsv)

COSMOS_CONN=$(az cosmosdb keys list \
  --name "$COSMOS_NAME" \
  --resource-group "$RG_NAME" \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" \
  --output tsv)

IOTHUB_EVENTHUB_CONN=$(az iot hub connection-string show \
  --hub-name "$IOT_HUB_NAME" \
  --resource-group "$RG_NAME" \
  --policy-name iothubowner \
  --default-eventhub \
  --query connectionString \
  --output tsv)

FRONTEND_URL=$(az storage account show \
  --name "$FRONTEND_SA" \
  --resource-group "$RG_NAME" \
  --query "primaryEndpoints.web" \
  --output tsv 2>/dev/null || echo "pending-static-website-enable")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_OUT="$SCRIPT_DIR/infra_outputs.env"

cat > "$ENV_OUT" <<EOF
# Auto-generado por 01_infraestructura.sh — $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# NO subir este archivo al repositorio (contiene secretos)
RG_NAME="${RG_NAME}"
LOCATION="${LOCATION}"
IOT_HUB_NAME="${IOT_HUB_NAME}"
COSMOS_NAME="${COSMOS_NAME}"
COSMOS_DB="${COSMOS_DB}"
COSMOS_CONTAINER="${COSMOS_CONTAINER}"
IOT_DEVICE_ID="${IOT_DEVICE_ID}"
FUNC_STORAGE="${FUNC_STORAGE}"
FRONTEND_SA="${FRONTEND_SA}"
IOTHUB_SERVICE_CONNECTION_STRING="${IOTHUB_CONN}"
IOTHUB_CONNECTION_STRING="${IOTHUB_EVENTHUB_CONN}"
COSMOS_CONNECTION_STRING="${COSMOS_CONN}"
FRONTEND_URL="${FRONTEND_URL}"
EOF

ok "Variables exportadas → $ENV_OUT"
log "============================================================"
log "01_infraestructura.sh completado exitosamente."
log "============================================================"
