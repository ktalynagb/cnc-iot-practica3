/**
 * frontend/app.js
 * FLUX CNC IoT Dashboard — Práctica 3
 *
 * Consume las Azure Functions:
 *   GET  <API_BASE_URL>/datos?limit=N&dispositivo=D  → lecturas recientes
 *   GET  <API_BASE_URL>/datos/csv?dispositivo=D      → descarga CSV
 *   POST <API_BASE_URL>/actuador                     → control C2D
 *
 * La variable __API_BASE_URL__ es reemplazada por 03_frontend_hosting.sh
 * con la URL real de la Function App antes de subir al blob storage.
 */

// URL base de la API — reemplazada en build por 03_frontend_hosting.sh
const API_BASE_URL = "__API_BASE_URL__";

// Intervalo de refresco automático (ms)
const REFRESH_INTERVAL_MS = 15000;

// Umbrales locales para colorear tarjetas (deben coincidir con las env vars del backend)
const THRESHOLDS = {
  tempMin:  15.0,
  tempMax:  45.0,
  humMin:   20.0,
  humMax:   80.0,
  accelMax:  2.0,
};

// ── Ciclo de polling ──────────────────────────────────────────────────────────
let refreshTimer = null;

document.addEventListener("DOMContentLoaded", () => {
  fetchData();
  refreshTimer = setInterval(fetchData, REFRESH_INTERVAL_MS);
});

// ── Obtener y renderizar lecturas ─────────────────────────────────────────────
async function fetchData() {
  const limit = document.getElementById("limit-select").value;
  const dispositivo = document.getElementById("device-select").value;

  setStatus("loading");

  try {
    const url = `${API_BASE_URL}/datos?limit=${encodeURIComponent(limit)}&dispositivo=${encodeURIComponent(dispositivo)}`;
    const res = await fetch(url);

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${res.statusText}`);
    }

    const data = await res.json();

    setStatus("ok");
    renderMetrics(data);
    renderTable(data);
    updateTimestamp();
  } catch (err) {
    setStatus("error");
    console.error("[fetchData] Error:", err);
    showTableError(err.message);
  }
}

// ── Renderizar tarjetas de métricas (última lectura) ──────────────────────────
function renderMetrics(data) {
  if (!data || data.length === 0) {
    ["temp", "hum", "vib"].forEach((k) => {
      setText(`val-${k}`, "—");
      setBadge(`badge-${k}`, "", "");
    });
    setText("val-state", "Sin datos");
    setText("val-motive", "");
    return;
  }

  const latest = data[0];

  // Temperatura
  const temp = parseFloat(latest.temperatura);
  setText("val-temp", isNaN(temp) ? "—" : temp.toFixed(1));
  const tempAlert = temp < THRESHOLDS.tempMin || temp > THRESHOLDS.tempMax;
  setBadge("badge-temp", tempAlert ? "⚠ Fuera de rango" : "✓ Normal", tempAlert ? "alert" : "ok");
  setCardState("card-temp", tempAlert);

  // Humedad
  const hum = parseFloat(latest.humedad);
  setText("val-hum", isNaN(hum) ? "—" : hum.toFixed(1));
  const humAlert = hum < THRESHOLDS.humMin || hum > THRESHOLDS.humMax;
  setBadge("badge-hum", humAlert ? "⚠ Fuera de rango" : "✓ Normal", humAlert ? "alert" : "ok");
  setCardState("card-hum", humAlert);

  // Vibración
  const vib = parseFloat(latest.vibracion_total);
  setText("val-vib", isNaN(vib) ? "—" : vib.toFixed(4));
  const vibAlert = vib > THRESHOLDS.accelMax;
  setBadge("badge-vib", vibAlert ? "⚠ Alta vibración" : "✓ Normal", vibAlert ? "alert" : "ok");
  setCardState("card-vib", vibAlert);

  // Estado general
  const alerta = latest.alerta === true || latest.alerta === "True" || latest.alerta === "true";
  setText("val-state", alerta ? "⚠ ALERTA" : "✓ OK");
  setText("val-motive", latest.motivo_alerta || "");
  setCardState("card-alert", alerta);
}

// ── Renderizar tabla de lecturas ──────────────────────────────────────────────
function renderTable(data) {
  const tbody = document.getElementById("readings-tbody");

  if (!data || data.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" class="table-empty">No hay lecturas disponibles.</td></tr>';
    return;
  }

  tbody.innerHTML = data.map((row) => {
    const alerta = row.alerta === true || row.alerta === "True" || row.alerta === "true";
    const ts = row.timestamp ? new Date(row.timestamp).toLocaleString("es-CO") : "—";
    const rowClass = alerta ? "row-alert" : "";
    return `<tr class="${rowClass}">
      <td>${ts}</td>
      <td>${fmt(row.temperatura, 1)}</td>
      <td>${fmt(row.humedad, 1)}</td>
      <td>${fmt(row.vibracion_total, 4)}</td>
      <td>${alerta ? "⚠ Sí" : "✓ No"}</td>
      <td class="td-motive">${escapeHtml(row.motivo_alerta || "")}</td>
    </tr>`;
  }).join("");
}

// ── Descargar CSV ─────────────────────────────────────────────────────────────
async function downloadCSV(event) {
  event.preventDefault();
  const dispositivo = document.getElementById("device-select").value;
  const url = `${API_BASE_URL}/datos/csv?dispositivo=${encodeURIComponent(dispositivo)}`;

  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const blob = await res.blob();
    const disposition = res.headers.get("Content-Disposition") || "";
    const match = disposition.match(/filename="?([^"]+)"?/);
    const filename = match ? match[1] : `lecturas_cnc_${Date.now()}.csv`;

    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
  } catch (err) {
    console.error("[downloadCSV] Error:", err);
    alert(`Error al descargar el CSV: ${err.message}`);
  }
}

// ── Enviar comando al actuador ────────────────────────────────────────────────
async function sendCommand(comando) {
  const dispositivo = document.getElementById("device-select").value;
  const responseEl = document.getElementById("actuator-response");

  ["btn-on", "btn-off", "btn-reset"].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.disabled = true;
  });

  responseEl.textContent = `Enviando '${comando}'…`;
  responseEl.className = "actuator-response actuator-response--loading";

  try {
    const res = await fetch(`${API_BASE_URL}/actuador`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dispositivo, comando }),
    });

    const json = await res.json();

    if (res.ok && json.ok) {
      responseEl.textContent = `✓ Comando '${comando}' enviado correctamente al dispositivo '${json.dispositivo}'.`;
      responseEl.className = "actuator-response actuator-response--ok";
    } else {
      const msg = json.error || `HTTP ${res.status}`;
      responseEl.textContent = `✗ Error: ${msg}`;
      responseEl.className = "actuator-response actuator-response--error";
    }
  } catch (err) {
    responseEl.textContent = `✗ Error de red: ${err.message}`;
    responseEl.className = "actuator-response actuator-response--error";
  } finally {
    ["btn-on", "btn-off", "btn-reset"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.disabled = false;
    });
  }
}

// ── Helpers de UI ─────────────────────────────────────────────────────────────
function setStatus(state) {
  const dot   = document.getElementById("status-dot");
  const label = document.getElementById("status-label");

  dot.className = "status-dot";
  switch (state) {
    case "ok":
      dot.classList.add("status-ok");
      label.textContent = "En línea";
      break;
    case "error":
      dot.classList.add("status-error");
      label.textContent = "Error de conexión";
      break;
    case "loading":
    default:
      dot.classList.add("status-connecting");
      label.textContent = "Actualizando…";
  }
}

function setText(id, text) {
  const el = document.getElementById(id);
  if (el) el.textContent = text;
}

function setBadge(id, text, cls) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
  el.className = `metric-badge${cls ? ` badge-${cls}` : ""}`;
}

function setCardState(id, isAlert) {
  const el = document.getElementById(id);
  if (!el) return;
  el.classList.toggle("metric-card--alert", isAlert);
  el.classList.toggle("metric-card--ok", !isAlert);
}

function showTableError(msg) {
  const tbody = document.getElementById("readings-tbody");
  tbody.innerHTML = `<tr><td colspan="6" class="table-empty table-error">Error: ${escapeHtml(msg)}</td></tr>`;
}

function updateTimestamp() {
  const el = document.getElementById("last-update");
  if (el) el.textContent = `Última actualización: ${new Date().toLocaleString("es-CO")}`;
}

function fmt(value, decimals) {
  const n = parseFloat(value);
  return isNaN(n) ? "—" : n.toFixed(decimals);
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
