import os
import requests
import pytest

BASE = os.getenv("BACKEND_URL", "http://localhost:8000").rstrip("/")

def send_lectura(temperatura, humedad, accel_x, accel_y, accel_z, timeout=5):
    payload = {
        "temperatura": temperatura,
        "humedad": humedad,
        "accel_x": accel_x,
        "accel_y": accel_y,
        "accel_z": accel_z,
    }
    return requests.post(f"{BASE}/datos/", json=payload, timeout=timeout)

def test_health_check():
    r = requests.get(f"{BASE}/")
    assert r.status_code == 200
    body = r.json()
    assert body.get("status") == "ok"

@pytest.mark.parametrize("t,h,ax,ay,az", [
    (28.5, 50.0, 0.12, -0.03, 9.81),
    (15.0, 20.0, 0.0, 0.0, 9.8),        # borde inferior temp = 15 (umbral de alerta en config)
    (45.0, 80.0, 1.5, -0.5, 9.7),       # borde superior temp = 45 (umbral de alerta en config)
])
def test_post_lectura_success(t, h, ax, ay, az):
    r = send_lectura(t, h, ax, ay, az)
    assert r.status_code == 201, f"Expected 201, got {r.status_code}: {r.text}"
    data = r.json()
    # campos esperados en LecturaSalida
    assert "id" in data
    assert "timestamp" in data
    assert data["temperatura"] == pytest.approx(t, rel=1e-3)
    assert data["humedad"] == pytest.approx(h, rel=1e-3)
    assert "vibracion_total" in data
    assert "alerta" in data

def test_post_lectura_validation_error_temp_out_of_range():
    # temperatura menor que -40 => validación pydantic/fastapi debe devolver 422
    r = send_lectura(-50.0, 50.0, 0.0, 0.0, 9.8)
    assert r.status_code == 422

def test_post_lectura_validation_error_humedad_out_of_range():
    # humedad > 100 => 422
    r = send_lectura(25.0, 150.0, 0.0, 0.0, 9.8)
    assert r.status_code == 422