#!/usr/bin/env bash
# Deploy/04_cleanup.sh
# ============================================================
# FLUX CNC IoT — Práctica 3
# Elimina todos los recursos Azure creados por 01_infraestructura.sh
#
# ⚠ ADVERTENCIA: Esta operación es destructiva e irreversible.
#   Se eliminará el Resource Group completo y todos sus recursos.
#
# Prerequisitos:
#   - az CLI autenticado
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/infra_outputs.env"

# ── Variables (valores por defecto o desde env file) ─────────────────────────
RG_NAME="${RG_NAME:-rg-cnc-iot}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

log()  { echo "[04_cleanup] $*"; }
warn() { echo "[04_cleanup] ⚠ $*"; }

# ── Confirmación interactiva ──────────────────────────────────────────────────
warn "Esta operación eliminará el resource group '$RG_NAME' y TODOS sus recursos."
warn "Esto incluye: IoT Hub, Cosmos DB, Function App y Storage Accounts."
echo ""

if [[ "${FORCE_CLEANUP:-}" != "true" ]]; then
  read -r -p "[04_cleanup] ¿Confirmas la eliminación? (escribe 'si' para continuar): " CONFIRM
  if [[ "$CONFIRM" != "si" ]]; then
    log "Operación cancelada por el usuario."
    exit 0
  fi
fi

# ── Eliminar Resource Group ───────────────────────────────────────────────────
log "Verificando si existe el resource group '$RG_NAME'..."
if ! az group show --name "$RG_NAME" &>/dev/null; then
  warn "Resource group '$RG_NAME' no existe. Nada que eliminar."
  exit 0
fi

log "Eliminando resource group '$RG_NAME' (puede tardar varios minutos)..."
az group delete \
  --name "$RG_NAME" \
  --yes \
  --no-wait
echo "[04_cleanup] ✓ Eliminación de '$RG_NAME' iniciada en background."
log "  Puedes verificar el estado con:"
log "  az group show --name '$RG_NAME'"

# ── Limpiar archivo de outputs local ─────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  rm -f "$ENV_FILE"
  echo "[04_cleanup] ✓ Archivo '$ENV_FILE' eliminado."
fi

log "============================================================"
log "04_cleanup.sh completado."
log "Los recursos se eliminarán en background en Azure."
log "============================================================"
