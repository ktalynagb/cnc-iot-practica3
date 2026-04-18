# 🏭 CNC IoT Backend — Monitoreo de Máquina CNC

Proyecto de la **Especialización en Inteligencia Artificial aplicada a IoT**  
Universidad Autónoma de Occidente · Práctica 1

## Integrantes
| Rol | Persona | Responsabilidad |
|-----|---------|-----------------|
| Hardware & Firmware | Valentina | ESP32-CAM + MPU-6050 + DHT22 |
| Backend & BD | Katalyna | FastAPI + PostgreSQL + CSV |
| Dashboard + AWS | David | Frontend + despliegue en nube |

## Caso de uso
Monitoreo en tiempo real de una **máquina CNC** para detectar:
- 🌡️ Temperatura y humedad del entorno (DHT22)
- 📳 Vibración en ejes X, Y, Z (MPU-6050)
- 🚨 Alertas cuando los valores salen de rangos normales

## Stack tecnológico
- **Firmware:** Arduino C++ en ESP32-CAM
- **Backend:** Python 3.11 + FastAPI + SQLAlchemy
- **Base de datos:** PostgreSQL 15
- **Almacenamiento adicional:** CSV con timestamp
- **Nube:** AWS (EC2 + RDS)

## Estructura del repositorio
```
cnc-iot-backend/
├── app/
│   ├── main.py           # Entrada FastAPI
│   ├── database.py       # Conexión PostgreSQL
│   ├── csv_writer.py     # Escritura en CSV
│   ├── models/           # Modelos SQLAlchemy
│   │   └── lectura.py
│   ├── schemas/          # Schemas Pydantic
│   │   └── lectura.py
│   └── routers/          # Endpoints
│       ├── datos.py
│       └── alertas.py
├── data/                 # Archivos CSV generados
├── tests/                # Pruebas de integración
├── .env.example          # Variables de entorno
├── requirements.txt
├── Makefile              # Comandos útiles
└── README.md
```

## JSON que envía el ESP32
```json
{
  "temperatura": 28.5,
  "humedad": 65.2,
  "accel_x": 0.12,
  "accel_y": -0.03,
  "accel_z": 9.81
}
```
> El timestamp lo agrega el servidor automáticamente.

## Umbrales de alerta
| Variable | Mínimo | Máximo |
|----------|--------|--------|
| Temperatura (°C) | 15 | 45 |
| Humedad (%) | 20 | 80 |
| Vibración \|accel\| (m/s²) | — | 2.0 |

## Inicio rápido
```bash
# Clonar, configurar y levantar todo
make setup
make run

# Ver todos los comandos disponibles
make help
```
