// CNC IoT — ESP32-C3 | Práctica 3 — Azure IoT Hub (MQTTS, puerto 8883)
// Sensores : DHT22 (temperatura y humedad) — GPIO0
// Actuador : LED/relé                      — GPIO2
// Implementa: generación on-device de SAS token (HMAC-SHA256 + base64) y renovación NTP

#include "credentials.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <time.h>

// mbedTLS (ESP32 core incluye mbedtls)
#include "mbedtls/md.h"
#include "mbedtls/base64.h"

#define DHTPIN       0
#define DHTTYPE      DHT22
#define ACTUATOR_PIN 10
#define MQTT_PORT    8883

// Los topics se generan en runtime porque DEVICE_ID es const char*
String TOPIC_TELEMETRY;
String TOPIC_COMMANDS;

DHT dht(DHTPIN, DHTTYPE);
WiFiClientSecure tlsClient;
PubSubClient mqtt(tlsClient);

const unsigned long INTERVALO_MS = 5000;
unsigned long ultimoEnvio = 0;

// SAS token parameters
const unsigned long SAS_TTL = 60UL * 60UL;         // 1 hora
const unsigned long SAS_RENEW_BEFORE = 5UL * 60UL; // renovar 5 minutos antes
unsigned long sasExpiry = 0;

// Forward declarations
void conectarWiFi();
void setupTime();
String urlEncode(const String &str);
String createSasToken(const char* host, const char* deviceId, const char* primaryKey, unsigned long ttlSeconds);
void conectarAzureIoT();
void ensureSasAndConnection();
void publishTelemetry(float temperatura, float humedad);

// Callback: comandos cloud-to-device desde el dashboard
void onCommand(char* topic, byte* payload, unsigned int length) {
  String cmd = "";
  for (unsigned int i = 0; i < length; i++) cmd += (char)payload[i];
  cmd.trim();
  Serial.printf("[CMD] Recibido en topic %s: %s\n", topic, cmd.c_str());

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
  int tries = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (++tries > 120) { // 60s timeout
      Serial.println("\n[WiFi] Timeout conectando a WiFi, reintentando...");
      tries = 0;
    }
  }
  Serial.printf("\n[WiFi] Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
}

// NTP / hora
void setupTime() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("[TIME] Esperando sincronizacion NTP");
  int tries = 0;
  while (time(NULL) < 1600000000UL && tries < 60) { // espera hasta ~30s
    Serial.print(".");
    delay(500);
    tries++;
  }
  Serial.println();
  if (time(NULL) < 1600000000UL) {
    Serial.println("[TIME] No se pudo sincronizar la hora (NTP). Algunos tokens podrían fallar.");
  } else {
    Serial.printf("[TIME] Hora sincronizada: %lu\n", time(NULL));
  }
}

// URL-encode helper
String urlEncode(const String &str) {
  String encoded = "";
  char c;
  for (size_t i = 0; i < str.length(); i++) {
    c = str.charAt(i);
    if (('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') ||
        ('0' <= c && c <= '9') || c == '-' || c == '_' || c == '.' ||
        c == '~') {
      encoded += c;
    } else {
      char buf[5];
      sprintf(buf, "%%%02X", (unsigned char)c);
      encoded += buf;
    }
  }
  return encoded;
}

// Create SAS token on-device using mbedtls (primaryKey must be base64)
String createSasToken(const char* host, const char* deviceId, const char* primaryKey, unsigned long ttlSeconds) {
  String resource = String(host) + "/devices/" + String(deviceId);
  String resourceEncoded = urlEncode(resource);

  unsigned long expiry = (unsigned long)time(NULL) + ttlSeconds;
  String expiryStr = String(expiry);

  // toSign = urlEncodedResource + "\n" + expiry
  String toSign = resourceEncoded + "\n" + expiryStr;

  // Decode primaryKey (base64) -> keyBin
  size_t primaryLen = strlen(primaryKey);
  unsigned char keyBin[128];
  size_t keyBinLen = 0;
  int ret = mbedtls_base64_decode(keyBin, sizeof(keyBin), &keyBinLen, (const unsigned char*)primaryKey, primaryLen);
  if (ret != 0) {
    Serial.printf("[SAS] base64 decode key error: %d\n", ret);
    return "";
  }

  // HMAC SHA256 of toSign
  unsigned char hmac[32];
  const mbedtls_md_info_t *md_info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (md_info == NULL) {
    Serial.println("[SAS] md_info NULL");
    return "";
  }
  ret = mbedtls_md_hmac(md_info, keyBin, keyBinLen, (const unsigned char*)toSign.c_str(), toSign.length(), hmac);
  if (ret != 0) {
    Serial.printf("[SAS] HMAC error: %d\n", ret);
    return "";
  }

  // Base64 encode HMAC
  unsigned char sigBase64[128];
  size_t sigBase64Len = 0;
  ret = mbedtls_base64_encode(sigBase64, sizeof(sigBase64), &sigBase64Len, hmac, sizeof(hmac));
  if (ret != 0) {
    Serial.printf("[SAS] base64 encode sig error: %d\n", ret);
    return "";
  }

  // Build token
  String sig = String((char*)sigBase64).substring(0, sigBase64Len);
  String sigEncoded = urlEncode(sig);
  String token = "SharedAccessSignature sr=" + resourceEncoded + "&sig=" + sigEncoded + "&se=" + expiryStr;
  return token;
}

// Connect to Azure IoT Hub using SAS token as password
void conectarAzureIoT() {
  // DEBUG: probar TLS connect con CA configurada
  {
    WiFiClientSecure testClient;
    testClient.setCACert(AZURE_ROOT_CA);
    Serial.println("[DEBUG] Probando TLS connect (con CA)...");
    if (!testClient.connect(IOT_HUB_HOST, MQTT_PORT)) {
      Serial.println("[DEBUG] TLS connect FAILED (con CA)");
    } else {
      Serial.println("[DEBUG] TLS connect OK (con CA)");
      testClient.stop();
    }
  }

  // DEBUG: probar TLS connect sin validar (solo para aislar CA vs red). BORRAR/COMENTAR en producción.
  {
    WiFiClientSecure testClient2;
    testClient2.setInsecure();
    Serial.println("[DEBUG] Probando TLS connect (insecure)...");
    if (!testClient2.connect(IOT_HUB_HOST, MQTT_PORT)) {
      Serial.println("[DEBUG] TLS connect FAILED (insecure) — problema de red/DNS/puerto");
    } else {
      Serial.println("[DEBUG] TLS connect OK (insecure)");
      testClient2.stop();
    }
  }

  // DEBUG: imprime time() para confirmar NTP
  Serial.printf("[DEBUG] time() = %lu\n", (unsigned long)time(NULL));

  // Generar SAS y username (imprimir solo longitud/prefijo)
  String sas = createSasToken(IOT_HUB_HOST, DEVICE_ID, DEVICE_PRIMARY_KEY, SAS_TTL);
  Serial.printf("[DEBUG] SAS length: %u, startsWith: %.20s\n", (unsigned)sas.length(), sas.c_str());
  String username = String(IOT_HUB_HOST) + "/" + DEVICE_ID + "/?api-version=2021-04-12";
  Serial.println("[DEBUG] username: " + username);

  // Configurar cliente MQTT real
  tlsClient.setCACert(AZURE_ROOT_CA);
  mqtt.setServer(IOT_HUB_HOST, MQTT_PORT);
  mqtt.setCallback(onCommand);
  mqtt.setBufferSize(512);

  if (sas == "") {
    Serial.println("[MQTT] No se pudo generar SAS token");
    delay(5000);
    return;
  }
  sasExpiry = (unsigned long)time(NULL) + SAS_TTL;

  Serial.printf("[MQTT] Conectando a %s con SAS (expira en %lus)...\n", IOT_HUB_HOST, SAS_TTL);
  if (mqtt.connect(DEVICE_ID, username.c_str(), sas.c_str())) {
    Serial.println("[MQTT] Conectado OK");
    if (mqtt.subscribe(TOPIC_COMMANDS.c_str())) {
      Serial.println("[MQTT] Suscrito a comandos C2D");
    } else {
      Serial.println("[MQTT] Suscripcion a comandos fallida");
    }
  } else {
    Serial.printf("[MQTT] Error conectando, rc=%d\n", mqtt.state());
  }
}

// Ensure SAS token not expired (renew if near expiration) and connection alive
void ensureSasAndConnection() {
  unsigned long now = (unsigned long)time(NULL);
  if (sasExpiry > 0 && now >= (sasExpiry - SAS_RENEW_BEFORE)) {
    Serial.println("[SAS] SAS Token cercano a expirar, forzando reconexion para regenerarlo.");
    if (mqtt.connected()) {
      mqtt.disconnect();
      delay(200);
    }
  }
  if (!mqtt.connected()) {
    Serial.println("[MQTT] No conectado — intentado conectar...");
    conectarAzureIoT();
  }
}

// Publish telemetry helper
void publishTelemetry(float temperatura, float humedad) {
  char payload[128];
  snprintf(payload, sizeof(payload),
           "{\"temperatura\":%.2f,\"humedad\":%.2f}",
           temperatura, humedad);
  bool ok = mqtt.publish(TOPIC_TELEMETRY.c_str(), payload);
  Serial.printf("[MQTT] → %s  %s\n", payload, ok ? "OK" : "ERROR");
}

// Setup
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== CNC IoT ESP32 — Práctica 3 Azure IoT Hub (SAS) ===");

  pinMode(ACTUATOR_PIN, OUTPUT);
  digitalWrite(ACTUATOR_PIN, LOW);

  dht.begin();
  Serial.println("[DHT22] Iniciado en GPIO0");

  // Construir topics en runtime usando DEVICE_ID (const char*)
  TOPIC_TELEMETRY = String("devices/") + String(DEVICE_ID) + "/messages/events/";
  TOPIC_COMMANDS  = String("devices/") + String(DEVICE_ID) + "/messages/devicebound/#";

  conectarWiFi();
  setupTime();            // sincronizar hora para generar SAS válido
  conectarAzureIoT();
}

// Loop
void loop() {
  ensureSasAndConnection();
  if (mqtt.connected()) {
    mqtt.loop();
  }

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

  publishTelemetry(temperatura, humedad);
}