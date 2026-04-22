#!/usr/bin/env python3
import os
import argparse
import requests
import json

# Actualizado con la IP Pública de tu Application Gateway en Azure
BASE = os.getenv("BACKEND_URL", "http://20.12.182.114").rstrip("/")

def send(temperatura, humedad, accel_x, accel_y, accel_z):
    payload = {
        "temperatura": temperatura,
        "humedad": humedad,
        "accel_x": accel_x,
        "accel_y": accel_y,
        "accel_z": accel_z,
    }
    try:
        r = requests.post(f"{BASE}/datos/", json=payload, timeout=5)
    except Exception as e:
        print("Error al conectar con el backend:", e)
        return
    print("--- REQUEST ---")
    print(json.dumps(payload, indent=2))
    print("--- RESPONSE ---")
    print(f"HTTP {r.status_code}")
    try:
        print(json.dumps(r.json(), indent=2, ensure_ascii=False))
    except Exception:
        print(r.text)

def prompt_float(prompt_text, default=None):
    raw = input(f"{prompt_text} [{default}]: ").strip()
    if raw == "" and default is not None:
        return default
    try:
        return float(raw)
    except ValueError:
        print("Valor no válido, intente de nuevo.")
        return prompt_float(prompt_text, default)

def interactive_loop(defaults):
    while True:
        print("\nIntroduce los valores de la lectura (enter para usar default). Ctrl+C para salir.")
        t = prompt_float("temperatura (°C) -40..80", defaults["temperatura"])
        h = prompt_float("humedad (%) 0..100", defaults["humedad"])
        ax = prompt_float("accel_x (m/s²)", defaults["accel_x"])
        ay = prompt_float("accel_y (m/s²)", defaults["accel_y"])
        az = prompt_float("accel_z (m/s²)", defaults["accel_z"])
        send(t, h, ax, ay, az)
        cont = input("Enviar otra lectura? (y/n) [y]: ").strip().lower()
        if cont and cont[0] != "y":
            break

def main():
    parser = argparse.ArgumentParser(description="Enviar lecturas al backend CNC IoT")
    parser.add_argument("--temperatura", type=float, help="Temperatura °C")
    parser.add_argument("--humedad", type=float, help="Humedad %")
    parser.add_argument("--accel-x", type=float, help="accel_x m/s²")
    parser.add_argument("--accel-y", type=float, help="accel_y m/s²")
    parser.add_argument("--accel-z", type=float, help="accel_z m/s²")
    parser.add_argument("--single", action="store_true", help="Enviar una sola vez y salir (sin modo interactivo)")
    parser.add_argument("--backend", type=str, help="URL del backend, por ejemplo http://20.29.102.93")
    args = parser.parse_args()

    global BASE
    if args.backend:
        BASE = args.backend.rstrip("/")

    defaults = {
        "temperatura": args.temperatura if args.temperatura is not None else 28.5,
        "humedad": args.humedad if args.humedad is not None else 50.0,
        "accel_x": args.accel_x if args.accel_x is not None else 0.12,
        "accel_y": args.accel_y if args.accel_y is not None else -0.03,
        "accel_z": args.accel_z if args.accel_z is not None else 9.81,
    }

    if args.single:
        send(defaults["temperatura"], defaults["humedad"], defaults["accel_x"], defaults["accel_y"], defaults["accel_z"])
        return

    print(f"Conectando a {BASE} ...")
    try:
        r = requests.get(f"{BASE}/", timeout=3)
        print("Health:", r.status_code, r.text)
    except Exception as e:
        print("No se pudo consultar la ruta /:", e)

    interactive_loop(defaults)

if __name__ == "__main__":
    main()