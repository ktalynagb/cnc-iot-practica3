# Deploy — FLUX CNC IoT · Práctica 3

Scripts de despliegue serverless en **Microsoft Azure** para el proyecto CNC IoT.  
Migración desde arquitectura VM (Mosquitto + InfluxDB + FastAPI) hacia Azure IoT Hub + Cosmos DB + Azure Functions + Static Website.

---

## Estructura

```
Deploy/
├── 01_infraestructura.sh   # Crea recursos Azure (RG, IoT Hub, Cosmos DB, Storage)
├── 02_backend.sh           # Despliega Azure Functions (backend serverless)
├── 03_frontend_hosting.sh  # Publica el dashboard en Azure Static Website
├── 04_cleanup.sh           # Elimina todos los recursos Azure
├── deploy.sh               # ← ORQUESTADOR: ejecuta los pasos 1-2-3 en orden
├── infra_outputs.env.template  # Plantilla de variables (no subir infra_outputs.env)
└── README.md               # Este archivo

frontend/                   # (raíz del repo) Dashboard web estático
├── index.html
├── app.js
└── style.css
```

---

## Prerequisitos

| Herramienta | Versión mínima | Instalación |
|---|---|---|
| Azure CLI | 2.50+ | https://learn.microsoft.com/cli/azure/install-azure-cli |
| Azure Functions Core Tools | 4.x | `npm install -g azure-functions-core-tools@4` |
| Python | 3.11 | https://python.org |

**Autenticación:**
```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

---

## Deploy completo (recomendado)

```bash
cd Deploy/
chmod +x deploy.sh 01_infraestructura.sh 02_backend.sh 03_frontend_hosting.sh 04_cleanup.sh
./deploy.sh
```

Al finalizar se mostrará:
- 🌐 URL del dashboard frontend
- ⚡ URL base de la API (Azure Functions)
- Todos los valores quedan en `Deploy/infra_outputs.env` (no subir al repo)

---

## Deploy por pasos (avanzado)

```bash
# Solo infraestructura
./deploy.sh --only-infra

# Solo backend (requiere infra ya creada)
./deploy.sh --only-backend

# Solo frontend (requiere backend ya desplegado)
./deploy.sh --only-frontend

# Omitir pasos específicos
./deploy.sh --skip-infra         # infra ya existe, re-deploy backend + frontend
./deploy.sh --skip-frontend      # solo infra + backend

# Ayuda
./deploy.sh --help
```

---

## Variables opcionales (sobrescribir nombres generados)

Antes de ejecutar, puedes exportar estas variables para usar nombres propios:

```bash
export FUNC_STORAGE="mistore123"      # Storage Account para Functions (3-24 chars, minúsculas)
export FRONTEND_SA="mifrontend456"    # Storage Account para frontend (3-24 chars, minúsculas)
export FUNC_APP_NAME="mi-func-app"    # Nombre de la Function App
./deploy.sh
```

---

## Limpieza de recursos

```bash
./04_cleanup.sh

# Sin confirmación interactiva (CI/CD)
FORCE_CLEANUP=true ./04_cleanup.sh
```

⚠️ **Destructivo e irreversible.** Elimina el resource group completo y todos sus recursos.

---

## Arquitectura desplegada

```
ESP32-C3
  │  publica via MQTT sobre TLS
  ▼
Azure IoT Hub (cnc-iot-hub)
  │  Event Hub-compatible endpoint
  ▼
Azure Function: procesar_datos  ──► evalúa alertas
  │                               └► guarda en Cosmos DB
  ▼
Azure Cosmos DB (cnc-iot-cosmos / cnc_iot / lecturas)
  │
  ▼
Azure Function: get_datos         GET /api/datos
Azure Function: descargar_csv     GET /api/datos/csv
Azure Function: control_actuador  POST /api/actuador  ──► C2D al ESP32
  │
  ▼
Frontend (Azure Static Website)
  Dashboard HTML/JS — consume las Azure Functions
```

---

## Endpoints de la API

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/api/datos?limit=100&dispositivo=cnc1` | Últimas N lecturas |
| `GET` | `/api/datos/csv?dispositivo=cnc1` | Descarga CSV completo |
| `POST` | `/api/actuador` | Envía comando C2D al ESP32 |

---

## Notas de seguridad

- `infra_outputs.env` contiene secretos — está en `.gitignore` y **no debe subirse al repo**.
- Los connection strings se inyectan como App Settings en Azure Functions, nunca en el código fuente.
- El IoT Hub usa autenticación por certificado/SAS en el ESP32.
