"""
azure-functions/control_actuador/__init__.py
=============================================
FLUX CNC IoT · Práctica 3

Trigger: HTTP POST /api/actuador
Body:    {"dispositivo": "cnc1", "comando": "ON"} o {"comando": "OFF"}
Acción:  Intenta invoke_device_method; si falla, fallback a C2D (enviar texto plano).
         Si el envío C2D por la SDK falla, se intenta un fallback HTTP (REST) contra el IoT Hub.
Variables de entorno requeridas:
  IOTHUB_SERVICE_CONNECTION_STRING — connection string con permisos ServiceConnect
  IOT_DEVICE_ID                    — ID del dispositivo registrado en IoT Hub
"""
import base64
import hmac
import hashlib
import json
import logging
import os
import time
import urllib.parse
import urllib.request

import azure.functions as func
from azure.iot.hub import IoTHubRegistryManager
from azure.iot.hub.models import CloudToDeviceMethod

IOTHUB_SERVICE_CONN = os.getenv("IOTHUB_SERVICE_CONNECTION_STRING", "")
IOT_DEVICE_ID = os.getenv("IOT_DEVICE_ID", "esp32-cnc1")

log = logging.getLogger("control_actuador")

COMANDOS_VALIDOS = {"ON", "OFF", "RESET"}


def _parse_connection_string(conn_str: str):
    """
    Parse an IoT Hub connection string into a dict with keys HostName, SharedAccessKeyName, SharedAccessKey
    """
    parts = dict(kv.split("=", 1) for kv in conn_str.split(";") if "=" in kv)
    return parts


def _build_sas_token(hostname: str, key_name: str, key: str, target: str, ttl: int = 60 * 60):
    """
    Build a SharedAccessSignature token for the given target resource.
    target should be the resource URI (e.g. "<host>/devices/<deviceId>/messages/deviceBound")
    """
    expiry = int(time.time()) + ttl
    sr = urllib.parse.quote_plus(target)
    sign_target = f"{target}\n{expiry}"
    key_bytes = base64.b64decode(key)
    signature = hmac.new(key_bytes, sign_target.encode("utf-8"), hashlib.sha256).digest()
    sig = urllib.parse.quote_plus(base64.b64encode(signature))
    # if key_name is empty, omit skn parameter
    if key_name:
        token = f"SharedAccessSignature sr={sr}&sig={sig}&se={expiry}&skn={urllib.parse.quote_plus(key_name)}"
    else:
        token = f"SharedAccessSignature sr={sr}&sig={sig}&se={expiry}"
    return token


def _send_c2d_rest(conn_str: str, device_id: str, payload: str, timeout: int = 10):
    """
    Send a C2D message using the IoT Hub service REST API as a fallback.
    Returns True on success, False otherwise (and logs details).
    """
    try:
        parts = _parse_connection_string(conn_str)
        host = parts.get("HostName")
        key_name = parts.get("SharedAccessKeyName", "")
        key = parts.get("SharedAccessKey")
        if not host or not key:
            log.error("REST fallback: connection string missing HostName or SharedAccessKey")
            return False

        # Resource target for SAS (unencoded)
        resource_uri = f"{host}/devices/{device_id}/messages/deviceBound"
        sas = _build_sas_token(host, key_name, key, resource_uri)

        url = f"https://{host}/devices/{urllib.parse.quote(device_id)}/messages/deviceBound?api-version=2020-09-30"
        data = payload.encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Authorization", sas)
        # Prefer plain text payload for simplicity
        req.add_header("Content-Type", "text/plain; charset=utf-8")
        req.add_header("Content-Length", str(len(data)))

        log.info("REST fallback: Sending C2D via HTTP to %s (len=%d)", url, len(data))
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = resp.getcode()
            log.info("REST fallback: response status=%s", status)
            # IoT Hub returns 204 No Content on success for C2D REST
            return status in (200, 201, 202, 204)
    except Exception as e:
        log.exception("REST fallback send failed: %s", e)
        return False


def _respond_json(body_obj, status_code=200):
    return func.HttpResponse(
        body=json.dumps(body_obj),
        status_code=status_code,
        mimetype="application/json",
        headers={"Access-Control-Allow-Origin": "*"},
    )


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
        return _respond_json({"error": f"Comando inválido. Válidos: {COMANDOS_VALIDOS}"}, status_code=400)

    if not IOTHUB_SERVICE_CONN:
        return _respond_json({"error": "IOTHUB_SERVICE_CONNECTION_STRING no configurada"}, status_code=500)

    # Instrumentación mínima: confirmar que la Function ve la connstring (pero sin imprimirla)
    log.info(
        "control_actuador: device_id=%s len(IOTHUB_SERVICE_CONNECTION_STRING)=%d",
        device_id,
        len(IOTHUB_SERVICE_CONN or ""),
    )

    try:
        registry = IoTHubRegistryManager.from_connection_string(IOTHUB_SERVICE_CONN)
    except Exception as e:
        log.exception("No se pudo crear IoTHubRegistryManager")
        return _respond_json({"error": str(e)}, status_code=500)

    # 1) Intentar método directo (invoke), útil si el dispositivo lo implementa y está en línea.
    try:
        method = CloudToDeviceMethod(method_name="actuador", payload={"comando": comando})
        result = registry.invoke_device_method(device_id, method)
        status = getattr(result, "status", None)
        if status and int(status) < 400:
            log.info("invoke_device_method OK device=%s comando=%s status=%s", device_id, comando, status)
            return _respond_json({"ok": True, "delivered": "method", "status": status}, status_code=200)
        log.warning("invoke_device_method retornó status no-OK (%s) — fallback a C2D", status)
    except Exception as ex:
        log.warning("invoke_device_method falló (se usará C2D): %s", ex)

    # 2) Fallback: enviar Cloud-to-Device (C2D) usando la SDK (payload como texto plano)
    try:
        payload = comando  # enviar texto plano: "ON" / "OFF" / "RESET"
        log.info("Attempting SDK C2D send to device=%s payload=%s", device_id, payload)
        registry.send_c2d_message(device_id, payload)
        log.info("C2D (SDK) encolado device=%s comando=%s", device_id, comando)
        return _respond_json({"ok": True, "delivered": "c2d", "queued": True}, status_code=200)
    except Exception as e:
        log.exception("send_c2d_message (SDK) falló: %s", e)
        # intentar fallback REST
        try:
            log.info("Intentando fallback REST para enviar C2D...")
            ok_rest = _send_c2d_rest(IOTHUB_SERVICE_CONN, device_id, payload)
            if ok_rest:
                log.info("C2D (REST) encolado OK device=%s comando=%s", device_id, comando)
                return _respond_json({"ok": True, "delivered": "c2d_rest", "queued": True}, status_code=200)
            else:
                log.error("C2D (REST) falló también")
                return _respond_json({"error": "C2D message send failure (SDK and REST failed)"}, status_code=500)
        except Exception as e2:
            log.exception("Fallback REST lanzó excepción: %s", e2)
            return _respond_json({"error": str(e2)}, status_code=500)