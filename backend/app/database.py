"""
database.py  —  FLUX CNC IoT · Entrega 2
=========================================
Reemplaza SQLAlchemy + PostgreSQL por el cliente de InfluxDB 2.x.

Los GET endpoints de FastAPI ahora consultan InfluxDB en vez de Postgres.
El POST fue eliminado (los datos llegan por MQTT via mqtt_bridge.py).
"""

import os
from datetime import datetime, timezone

from influxdb_client import InfluxDBClient
from influxdb_client.client.write_api import SYNCHRONOUS

# ── Configuración (desde variables de entorno) ────────────────────────────────
INFLUX_URL    = os.getenv("INFLUX_URL",    "http://localhost:8086")
INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN",  "")
INFLUX_ORG    = os.getenv("INFLUX_ORG",    "flux")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "flux_cnc")

# ── Cliente singleton ─────────────────────────────────────────────────────────
_client: InfluxDBClient | None = None


def get_influx_client() -> InfluxDBClient:
    """Devuelve el cliente InfluxDB (singleton)."""
    global _client
    if _client is None:
        _client = InfluxDBClient(
            url=INFLUX_URL,
            token=INFLUX_TOKEN,
            org=INFLUX_ORG,
        )
    return _client


def get_query_api():
    """Devuelve la Query API de InfluxDB para los endpoints GET."""
    return get_influx_client().query_api()


def get_write_api():
    """Devuelve la Write API (usada solo por el bridge, no por FastAPI)."""
    return get_influx_client().write_api(write_options=SYNCHRONOUS)


# ── Helper: convertir fila Flux → dict compatible con LecturaSalida ───────────

def fila_a_lectura(record) -> dict:
    """
    Convierte un registro de la query Flux en un dict
    compatible con el schema LecturaSalida existente.
    """
    return {
        "id":              int(record.get_time().timestamp()),
        "timestamp":       record.get_time(),
        "temperatura":     record.values.get("temperatura",     0.0),
        "humedad":         record.values.get("humedad",         0.0),
        "accel_x":         record.values.get("accel_x",         0.0),
        "accel_y":         record.values.get("accel_y",         0.0),
        "accel_z":         record.values.get("accel_z",         0.0),
        "vibracion_total": record.values.get("vibracion_total", 0.0),
        "alerta":          record.values.get("alerta", "False") == "True",
        "motivo_alerta":   record.values.get("motivo_alerta") or None,
    }
