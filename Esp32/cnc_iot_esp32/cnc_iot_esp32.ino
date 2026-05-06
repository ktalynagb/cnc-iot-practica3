// CNC IoT — ESP32-C3 | Práctica 3 — Azure IoT Hub (MQTTS, puerto 8883)
// Sensores : DHT22 (temperatura y humedad) — GPIO0
// Actuador : LED/relé                      — GPIO2
// Sin MPU-6050 en esta entrega

#include "credentials.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>

#define DHTPIN       0
#define DHTTYPE      DHT22
#define ACTUATOR_PIN 2
#define MQTT_PORT    8883

// Topics Azure IoT Hub
#define TOPIC_TELEMETRY "devices/" DEVICE_ID "/messages/events/"
#define TOPIC_COMMANDS  "devices/" DEVICE_ID "/messages/devicebound/#"

DHT dht(DHTPIN, DHTTYPE);
WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);

const unsigned long INTERVALO_MS = 5000;
unsigned long ultimoEnvio = 0;


// Callback: comandos cloud-to-device desde el dashboard

void onCommand(char* topic, byte* payload, unsigned int length) {
  String cmd = "";
  for (unsigned int i = 0; i < length; i++) cmd += (char)payload[i];
  cmd.trim();
  Serial.printf("[CMD] Recibido: %s\n", cmd.c_str());

  if (cmd == "ON" || cmd == "on") {
    digitalWrite(ACTUATOR_PIN, HIGH);
    Serial.println("[ACT] Actuador ENCENDIDO");
  } else if (cmd == "OFF" || cmd == "off") {
    digitalWrite(ACTUATOR_PIN, LOW);
    Serial.println("[ACT] Actuador APAGADO");
  } else {
    Serial.println("[ACT] Comando no reconocido");
  }
}


// Conexión WiFi

void conectarWiFi() {
  Serial.printf("[WiFi] Conectando a %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n[WiFi] Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
}


// Conexión Azure IoT Hub via MQTTS con certificado X.509

void conectarAzureIoT() {
  tlsClient.setCACert(AZURE_ROOT_CA);
  tlsClient.setCertificate(DEVICE_CERT);
  tlsClient.setPrivateKey(DEVICE_PRIVATE_KEY);

  mqtt.setServer(IOT_HUB_HOST, MQTT_PORT);
  mqtt.setCallback(onCommand);
  mqtt.setBufferSize(512);

  // Username requerido por Azure IoT Hub (contraseña vacía para auth X.509)
  String username = String(IOT_HUB_HOST) + "/" + DEVICE_ID +
                    "/?api-version=2021-04-12";

  while (!mqtt.connected()) {
    Serial.printf("[MQTT] Conectando a %s...", IOT_HUB_HOST);
    if (mqtt.connect(DEVICE_ID, username.c_str(), "")) {
      Serial.println(" OK");
      mqtt.subscribe(TOPIC_COMMANDS);
      Serial.printf("[MQTT] Suscrito a comandos C2D\n");
    } else {
      Serial.printf(" Error rc=%d — reintentando en 5s\n", mqtt.state());
      delay(5000);
    }
  }
}


// Setup

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== CNC IoT ESP32 — Práctica 3 Azure IoT Hub ===");

  pinMode(ACTUATOR_PIN, OUTPUT);
  digitalWrite(ACTUATOR_PIN, LOW);

  dht.begin();
  Serial.println("[DHT22] Iniciado en GPIO0");

  conectarWiFi();
  conectarAzureIoT();
}


// Loop

void loop() {
  if (!mqtt.connected()) {
    Serial.println("[MQTT] Desconectado - reconectando...");
    conectarAzureIoT();
  }
  mqtt.loop();

  unsigned long ahora = millis();
  if (ahora - ultimoEnvio < INTERVALO_MS) return;
  ultimoEnvio = ahora;

  float humedad     = dht.readHumidity();
  float temperatura = dht.readTemperature();

  if (isnan(humedad) || isnan(temperatura)) {
    Serial.println("[DHT22] Error de lectura - se omite este ciclo");
    return;
  }

  Serial.println("------ Nueva lectura ------");
  Serial.printf("  Temperatura : %.2f °C\n", temperatura);
  Serial.printf("  Humedad     : %.2f %%\n", humedad);

  char payload[96];
  snprintf(payload, sizeof(payload),
           "{\"temperatura\":%.2f,\"humedad\":%.2f}",
           temperatura, humedad);

  bool ok = mqtt.publish(TOPIC_TELEMETRY, payload);
  Serial.printf("[MQTT] → %s  %s\n", payload, ok ? "OK" : "ERROR");
}
