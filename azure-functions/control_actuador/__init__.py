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
    # CORS preflight
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
        body = req.get_json()
    except Exception:
        body = {}

    comando = str(body.get("comando", "")).upper()
    device_id = body.get("dispositivo", IOT_DEVICE_ID)

    if comando not in COMANDOS_VALIDOS:
        return func.HttpResponse(
            body=json.dumps({"error": f"Comando inválido. Válidos: {COMANDOS_VALIDOS}"}),
            status_code=400,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )

    if not IOTHUB_SERVICE_CONN:
        return func.HttpResponse(
            body=json.dumps({"error": "IOTHUB_SERVICE_CONNECTION_STRING no configurada"}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )

    try:
        registry = IoTHubRegistryManager.from_connection_string(IOTHUB_SERVICE_CONN)
    except Exception as e:
        log.exception("No se pudo crear IoTHubRegistryManager")
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )

    # 1) Intentar método directo (invoke), útil si el dispositivo lo implementa y está en línea.
    try:
        method = CloudToDeviceMethod(method_name="actuador", payload={"comando": comando})
        result = registry.invoke_device_method(device_id, method)
        status = getattr(result, "status", None)
        if status and int(status) < 400:
            log.info("invoke_device_method OK device=%s comando=%s status=%s", device_id, comando, status)
            return func.HttpResponse(
                body=json.dumps({"ok": True, "delivered": "method", "status": status}),
                status_code=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"},
            )
        # si status >= 400 caemos a fallback
        log.warning("invoke_device_method retornó status no-OK (%s) — fallback a C2D", status)
    except Exception as ex:
        # Loguear excepción e intentar fallback a C2D
        log.warning("invoke_device_method falló (se usará C2D): %s", ex)

    # 2) Fallback: enviar Cloud-to-Device (C2D) — se encola si el dispositivo está offline
    try:
        payload = json.dumps({"comando": comando})
        registry.send_c2d_message(device_id, payload)
        log.info("C2D encolado device=%s comando=%s", device_id, comando)
        return func.HttpResponse(
            body=json.dumps({"ok": True, "delivered": "c2d", "queued": True}),
            status_code=200,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )
    except Exception as e:
        log.exception("send_c2d_message falló")
        return func.HttpResponse(
            body=json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json",
            headers={"Access-Control-Allow-Origin": "*"},
        )