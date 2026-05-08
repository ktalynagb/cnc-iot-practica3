#!/usr/bin/env bash
# Deploy/03_frontend_hosting.sh
# ============================================================
# FLUX CNC IoT — Práctica 3
# Publica el frontend estático en Azure Blob Storage (Static Website)
#
# Acciones:
#   - Habilita Static Website en el storage account del frontend
#   - Sube los archivos de frontend/ al contenedor $web
#   - Inyecta la URL del backend en app.js antes de subir
#   - Muestra la URL pública del sitio
#
# Prerequisitos:
#   - 01_infraestructura.sh y 02_backend.sh ejecutados
#   - infra_outputs.env presente con FRONTEND_SA y FUNC_BASE_URL
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/infra_outputs.env"
FRONTEND_SRC="$REPO_ROOT/frontend"
FRONTEND_WEB_CONTAINER="\$web"

# ── Cargar outputs de infraestructura ─────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[03_frontend] ERROR: '$ENV_FILE' no encontrado. Ejecuta 01_infraestructura.sh primero." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

log()  { echo "[03_frontend] $*"; }
ok()   { echo "[03_frontend] ✓ $*"; }
warn() { echo "[03_frontend] ⚠ $*"; }

# ── Validar que existe el directorio frontend ─────────────────────────────────
if [[ ! -d "$FRONTEND_SRC" ]]; then
  echo "[03_frontend] ERROR: Directorio '$FRONTEND_SRC' no encontrado." >&2
  exit 1
fi

# ── 1. Habilitar Static Website ───────────────────────────────────────────────
log "Habilitando Static Website en '$FRONTEND_SA'..."
az storage blob service-properties update \
  --account-name "$FRONTEND_SA" \
  --static-website \
  --index-document "index.html" \
  --404-document "index.html" \
  --output none
ok "Static Website habilitado."

# ── 2. Preparar archivos con URL del backend ──────────────────────────────────
TMP_FRONTEND="$(mktemp -d)"
trap 'rm -rf "$TMP_FRONTEND"' EXIT

log "Copiando archivos de frontend a directorio temporal..."
cp -r "$FRONTEND_SRC"/. "$TMP_FRONTEND/"

# Sustituir placeholder de API_BASE_URL en app.js si existe FUNC_BASE_URL
if [[ -n "${FUNC_BASE_URL:-}" ]]; then
  log "Inyectando API_BASE_URL='${FUNC_BASE_URL}' en app.js..."
  sed -i "s|__API_BASE_URL__|${FUNC_BASE_URL}|g" "$TMP_FRONTEND/app.js"
  ok "URL del backend inyectada en app.js."
else
  warn "FUNC_BASE_URL no definida. Ejecuta 02_backend.sh antes de este script para inyectar la URL automáticamente."
fi

# ── 3. Subir archivos al contenedor $web ─────────────────────────────────────
log "Subiendo archivos de frontend al contenedor '$FRONTEND_WEB_CONTAINER'..."
az storage blob upload-batch \
  --account-name "$FRONTEND_SA" \
  --source "$TMP_FRONTEND" \
  --destination "$FRONTEND_WEB_CONTAINER" \
  --overwrite true \
  --output none
ok "Archivos de frontend subidos correctamente."

# ── 4. Obtener y mostrar URL del sitio ────────────────────────────────────────
FRONTEND_URL=$(az storage account show \
  --name "$FRONTEND_SA" \
  --resource-group "$RG_NAME" \
  --query "primaryEndpoints.web" \
  --output tsv)

# Actualizar infra_outputs.env con la URL del frontend
{
  grep -v "^FRONTEND_URL=" "$ENV_FILE" || true
} > "$ENV_FILE.tmp"
{
  cat "$ENV_FILE.tmp"
  echo "FRONTEND_URL=\"${FRONTEND_URL}\""
} > "$ENV_FILE"
rm -f "$ENV_FILE.tmp"

ok "Dashboard disponible en: $FRONTEND_URL"
log "============================================================"
log "03_frontend_hosting.sh completado exitosamente."
log "============================================================"
