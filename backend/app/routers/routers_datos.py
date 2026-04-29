"""
routers/datos.py  —  FLUX CNC IoT · Entrega 2
===============================================
CAMBIOS vs entrega anterior:
  ✗  POST /datos/  →  ELIMINADO (datos llegan por MQTT, no HTTP)
  ✓  GET  /datos/  →  Conservado, ahora lee de InfluxDB
  ✓  GET  /datos/descargar/  →  Conservado, sirve el CSV igual que antes

El bridge mqtt_bridge.py es quien recibe, procesa y almacena los datos.
"""

from datetime import datetime, timezone
from pathlib import Path
from typing import List

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.database import get_query_api, fila_a_lectura, INFLUX_BUCKET, INFLUX_ORG
from app.schemas.lectura import LecturaSalida      # reutilizado sin cambios
from app.config import settings                    # reutilizado sin cambios

router = APIRouter(prefix="/datos", tags=["Datos"])


# ── GET /datos/ ───────────────────────────────────────────────────────────────

@router.get("/", response_model=List[LecturaSalida])
def obtener_datos(
    limit: int = Query(100, ge=1, le=1000, description="Número máximo de registros"),
):
    """
    **BE-3** — Retorna las últimas `limit` lecturas desde InfluxDB,
    más recientes primero. Compatible con el frontend existente.
    """
    query_api = get_query_api()

    # Query Flux: pivot para tener todos los fields en una sola fila por timestamp
    flux_query = f"""
        from(bucket: "{INFLUX_BUCKET}")
          |> range(start: -7d)
          |> filter(fn: (r) => r._measurement == "cnc_sensores")
          |> pivot(
               rowKey: ["_time"],
               columnKey: ["_field"],
               valueColumn: "_value"
             )
          |> sort(columns: ["_time"], desc: true)
          |> limit(n: {limit})
    """

    try:
        tablas = query_api.query(flux_query, org=INFLUX_ORG)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Error consultando InfluxDB: {e}")

    lecturas = []
    for tabla in tablas:
        for record in tabla.records:
            lecturas.append(fila_a_lectura(record))

    return lecturas


# ── GET /datos/descargar/ ─────────────────────────────────────────────────────

@router.get("/descargar/", tags=["Datos"])
def descargar_csv():
    """
    **BE-4** — Sirve el archivo CSV de lecturas como descarga directa.
    El CSV es escrito por mqtt_bridge.py usando csv_writer.py (sin cambios).
    """
    csv_path = Path(settings.CSV_PATH)
    if not csv_path.exists():
        raise HTTPException(
            status_code=404,
            detail="El archivo CSV no existe aún. Espera a que lleguen lecturas del ESP32.",
        )

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename  = f"lecturas_cnc_{timestamp}.csv"

    return FileResponse(
        path=str(csv_path),
        media_type="text/csv",
        filename=filename,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
