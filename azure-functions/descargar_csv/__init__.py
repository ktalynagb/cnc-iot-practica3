"""
azure-functions/descargar_csv/__init__.py
==========================================
FLUX CNC IoT · Práctica 3

Trigger: HTTP GET /api/datos/csv?dispositivo=cnc1
Acción:  Lee todos los registros de Cosmos DB y los devuelve
         como archivo CSV descargable.
"""

import csv
import io
import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
from azure.cosmos import CosmosClient

COSMOS_CONN = os.getenv("COSMOS_CONNECTION_STRING", "")
COSMOS_DB   = os.getenv("COSMOS_DATABASE", "cnc_iot")
COSMOS_CONT = os.getenv("COSMOS_CONTAINER", "lecturas")

CSV_HEADERS = [
    "id", "timestamp", "dispositivo",
    "temperatura", "humedad",
    "accel_x", "accel_y", "accel_z",
    "vibracion_total", "alerta", "motivo_alerta",
]

log = logging.getLogger("descargar_csv")


def main(req: func.HttpRequest) -> func.HttpResponse:
    dispositivo = req.params.get("dispositivo", "cnc1")

    try:
        cosmos    = CosmosClient.from_connection_string(COSMOS_CONN)
        container = cosmos.get_database_client(COSMOS_DB).get_container_client(COSMOS_CONT)

        query = (
            "SELECT * FROM c "
            "WHERE c.dispositivo = @dispositivo "
            "ORDER BY c.timestamp ASC"
        )
        items = list(container.query_items(
            query=query,
            parameters=[{"name": "@dispositivo", "value": dispositivo}],
            enable_cross_partition_query=False,
        ))

        # Generar CSV en memoria
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=CSV_HEADERS, extrasaction="ignore")
        writer.writeheader()
        for item in items:
            writer.writerow({h: item.get(h, "") for h in CSV_HEADERS})

        ts       = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        filename = f"lecturas_cnc_{ts}.csv"

        log.info("CSV generado con %d registros para dispositivo=%s", len(items), dispositivo)

        return func.HttpResponse(
            body=output.getvalue().encode("utf-8"),
            status_code=200,
            mimetype="text/csv",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "Access-Control-Allow-Origin": "*",
            },
        )

    except Exception as e:
        log.error("Error en descargar_csv: %s", e)
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )
