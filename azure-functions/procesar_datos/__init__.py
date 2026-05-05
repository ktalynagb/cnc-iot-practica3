"""
azure-functions/procesar_datos/__init__.py
==========================================
FLUX CNC IoT · Práctica 3

Trigger: Azure IoT Hub (Event Hub compatible)
Acción:  Parsea el mensaje del ESP32, calcula vibración,
         evalúa alertas y guarda en Cosmos DB.

Variables de entorno requeridas:
  IOTHUB_CONNECTION_STRING  — Event Hub-compatible endpoint del IoT Hub
  COSMOS_CONNECTION_STRING  — Connection string de Cosmos DB
  COSMOS_DATABASE           — Nombre de la base de datos (default: cnc_iot)
  COSMOS_CONTAINER          — Nombre del contenedor (default: lecturas)
"""

import json
import logging
import os
import sys
from datetime import datetime, timezone

import azure.functions as func
from azure.cosmos import CosmosClient

# Importar lógica compartida
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))
from alertas import calcular_vibracion, evaluar_alerta

# ── Config ────────────────────────────────────────────────────────────────────
COSMOS_CONN   = os.getenv("COSMOS_CONNECTION_STRING", "")
COSMOS_DB     = os.getenv("COSMOS_DATABASE", "cnc_iot")
COSMOS_CONT   = os.getenv("COSMOS_CONTAINER", "lecturas")

log = logging.getLogger("procesar_datos")


def main(events: list[func.EventHubEvent]) -> None:
    """
    Se ejecuta por cada lote de mensajes que llega al IoT Hub.
    Azure puede agrupar varios mensajes en un solo lote.
    """
    cosmos = CosmosClient.from_connection_string(COSMOS_CONN)
    container = cosmos.get_database_client(COSMOS_DB).get_container_client(COSMOS_CONT)

    for event in events:
        try:
            _procesar_evento(event, container)
        except Exception as e:
            log.error("Error procesando evento: %s", e)


def _procesar_evento(event: func.EventHubEvent, container) -> None:
    payload_str = event.get_body().decode("utf-8")
    log.info("Mensaje recibido: %s", payload_str)

    data = json.loads(payload_str)

    # Campos esperados del ESP32
    temperatura = float(data["temperatura"])
    humedad     = float(data["humedad"])
    accel_x     = float(data.get("accel_x", 0.0))
    accel_y     = float(data.get("accel_y", 0.0))
    accel_z     = float(data.get("accel_z", 0.0))

    # Lógica reutilizada de la entrega anterior
    vibracion        = calcular_vibracion(accel_x, accel_y, accel_z)
    alerta, motivo   = evaluar_alerta(temperatura, humedad, vibracion)

    ts = datetime.now(timezone.utc)

    # Documento para Cosmos DB
    doc = {
        "id":              ts.strftime("%Y%m%d%H%M%S%f"),   # único por timestamp
        "dispositivo":     data.get("dispositivo", "cnc1"),  # partition key
        "timestamp":       ts.isoformat(),
        "temperatura":     temperatura,
        "humedad":         humedad,
        "accel_x":         accel_x,
        "accel_y":         accel_y,
        "accel_z":         accel_z,
        "vibracion_total": vibracion,
        "alerta":          alerta,
        "motivo_alerta":   motivo or "",
    }

    container.upsert_item(doc)
    log.info(
        "Guardado en Cosmos DB — T=%.2f°C H=%.2f%% Vib=%.4f Alerta=%s",
        temperatura, humedad, vibracion, alerta
    )
    if alerta:
        log.warning("⚠ ALERTA: %s", motivo)
