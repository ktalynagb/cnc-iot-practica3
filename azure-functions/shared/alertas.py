"""
shared/alertas.py — FLUX CNC IoT · Práctica 3
==============================================
Reutilizado de la entrega anterior.
Adaptado para no depender de app.config (usa variables de entorno directamente).
"""
import math
import os
from typing import Optional, Tuple

TEMP_MIN  = float(os.getenv("TEMP_MIN",  "15.0"))
TEMP_MAX  = float(os.getenv("TEMP_MAX",  "45.0"))
HUM_MIN   = float(os.getenv("HUM_MIN",   "20.0"))
HUM_MAX   = float(os.getenv("HUM_MAX",   "80.0"))
ACCEL_MAX = float(os.getenv("ACCEL_MAX",  "2.0"))


def calcular_vibracion(ax: float, ay: float, az: float) -> float:
    """Magnitud del vector de aceleración en m/s²."""
    return round(math.sqrt(ax**2 + ay**2 + az**2), 4)


def evaluar_alerta(temperatura: float, humedad: float, vibracion: float) -> Tuple[bool, Optional[str]]:
    """
    Evalúa si los valores están fuera de los umbrales configurados.
    Retorna (hay_alerta, motivo).
    """
    motivos = []

    if temperatura < TEMP_MIN:
        motivos.append(f"Temperatura baja ({temperatura}°C < {TEMP_MIN}°C)")
    elif temperatura > TEMP_MAX:
        motivos.append(f"Temperatura alta ({temperatura}°C > {TEMP_MAX}°C)")

    if humedad < HUM_MIN:
        motivos.append(f"Humedad baja ({humedad}% < {HUM_MIN}%)")
    elif humedad > HUM_MAX:
        motivos.append(f"Humedad alta ({humedad}% > {HUM_MAX}%)")

    if vibracion > ACCEL_MAX:
        motivos.append(f"Vibración alta ({vibracion} m/s² > {ACCEL_MAX} m/s²)")

    if motivos:
        return True, " | ".join(motivos)
    return False, None
