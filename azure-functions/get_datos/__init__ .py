"""
azure-functions/get_datos/__init__.py
======================================
FLUX CNC IoT · Práctica 3

Trigger: HTTP GET /api/datos?limit=100&dispositivo=cnc1
Acción:  Consulta las últimas N lecturas de Cosmos DB y las devuelve como JSON.
         El dashboard consume este endpoint para mostrar datos en tiempo real.
"""

import json
import logging
import os
import sys

import azure.functions as func
from azure.cosmos import CosmosClient

COSMOS_CONN = os.getenv("COSMOS_CONNECTION_STRING", "")
COSMOS_DB   = os.getenv("COSMOS_DATABASE", "cnc_iot")
COSMOS_CONT = os.getenv("COSMOS_CONTAINER", "lecturas")

log = logging.getLogger("get_datos")


def main(req: func.HttpRequest) -> func.HttpResponse:
    limit       = int(req.params.get("limit", 100))
    dispositivo = req.params.get("dispositivo", "cnc1")

    try:
        cosmos     = CosmosClient.from_connection_string(COSMOS_CONN)
        container  = cosmos.get_database_client(COSMOS_DB).get_container_client(COSMOS_CONT)

        query = (
            "SELECT * FROM c "
            "WHERE c.dispositivo = @dispositivo "
            "ORDER BY c.timestamp DESC "
            f"OFFSET 0 LIMIT {limit}"
        )
        items = list(container.query_items(
            query=query,
            parameters=[{"name": "@dispositivo", "value": dispositivo}],
            enable_cross_partition_query=False,
        ))

        # Limpiar campos internos de Cosmos
        clean = [{k: v for k, v in item.items() if not k.startswith("_")} for item in items]

        log.info("GET /datos → %d registros para dispositivo=%s", len(clean), dispositivo)

        return func.HttpResponse(
            body=json.dumps(clean, ensure_ascii=False),
            status_code=200,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )

    except Exception as e:
        log.error("Error en get_datos: %s", e)
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )
