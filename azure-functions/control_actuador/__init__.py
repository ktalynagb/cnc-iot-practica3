"""
azure-functions/control_actuador/__init__.py
=============================================
FLUX CNC IoT · Práctica 3

Trigger: HTTP POST /api/actuador
Body:    {"dispositivo": "cnc1", "comando": "ON"} o {"comando": "OFF"}
Acción:  Envía un mensaje cloud-to-device (C2D) al ESP32 via Azure IoT Hub.
         El ESP32 lo recibe y acciona el actuador (LED, relé, etc).

Variables de entorno requeridas:
  IOTHUB_SERVICE_CONNECTION_STRING — connection string con permisos ServiceConnect
  IOT_DEVICE_ID                    — ID del dispositivo registrado en IoT Hub
"""

import json
import logging
import os

import azure.functions as func
from azure.iot.hub import IoTHubRegistryManager
from azure.iot.hub.models import CloudToDeviceMethod

IOTHUB_SERVICE_CONN = os.getenv("IOTHUB_SERVICE_CONNECTION_STRING", "")
IOT_DEVICE_ID       = os.getenv("IOT_DEVICE_ID", "esp32-cnc1")

log = logging.getLogger("control_actuador")

COMANDOS_VALIDOS = {"ON", "OFF", "RESET"}


def main(req: func.HttpRequest) -> func.HttpResponse:
    # Manejar preflight CORS
    if req.method == "OPTIONS":
        return func.HttpResponse(
            status_code=200,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type",
            },
        )

    try:
        body      = req.get_json()
        comando   = str(body.get("comando", "")).upper()
        device_id = body.get("dispositivo", IOT_DEVICE_ID)

        if comando not in COMANDOS_VALIDOS:
            return func.HttpResponse(
                body=json.dumps({"error": f"Comando inválido. Válidos: {COMANDOS_VALIDOS}"}),
                status_code=400,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"},
            )

        # Enviar comando C2D al ESP32
        registry = IoTHubRegistryManager.from_connection_string(IOTHUB_SERVICE_CONN)
        method   = CloudToDeviceMethod(method_name="actuador", payload={"comando": comando})
        result   = registry.invoke_device_method(device_id, method)

        log.info("Comando '%s' enviado a dispositivo '%s' — status: %s", comando, device_id, result.status)

        return func.HttpResponse(
            body=json.dumps({
                "ok":         True,
                "dispositivo": device_id,
                "comando":    comando,
                "status":     result.status,
            }),
            status_code=200,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )

    except Exception as e:
        log.error("Error en control_actuador: %s", e)
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )
