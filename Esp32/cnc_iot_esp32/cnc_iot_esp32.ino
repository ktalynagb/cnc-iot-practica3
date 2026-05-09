// CNC IoT — ESP32 Entrega 3 | Azure IoT Hub (MQTTS, puerto 8883)
// Soporta: C2D (devicebound) + Direct Methods ($iothub/methods)
// Sensores : DHT22 (temperatura y humedad) — GPIO0
// Actuador : LED/relé                      — GPIO2 (ajusta si usas otro pin)

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
// Cambia este pin si tu placa usa otro (GPIO2 es típico). En tu código anterior estaba 10; ajústalo aquí si lo necesitas.
#define ACTUATOR_PIN 10
#define MQTT_PORT    8883

// Topics generados en runtime (DEVICE_ID viene de credentials.h como const char*)
String TOPIC_TELEMETRY;
String TOPIC_COMMANDS;
const char* TOPIC_METHODS_SUB = "$iothub/methods/POST/#";

// Helpers
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
void mqttCallback(char* topic, byte* payload, unsigned int length);
String parseCommandFromPayload(const String &payload);
void handleDirectMethod(const char* topic, const String &payload);
void sendMethodResponse(const String &rid, int status, const String &body);

// --- Implementación ---

// Extrae valor "comando" desde JSON sencillo o usa texto plano
String parseCommandFromPayload(const String &payload) {
  String s = payload;
  s.trim();
  if (s.length() == 0) return "";

  // Si parece JSON, buscar "comando": "VALUE"
  if (s.charAt(0) == '{') {
    int idx = s.indexOf("\"comando\"");
    if (idx >= 0) {
      int colon = s.indexOf(':', idx);
      if (colon >= 0) {
        // buscar primera comilla después del colon
        int q1 = s.indexOf('"', colon);
        if (q1 >= 0) {
          int q2 = s.indexOf('"', q1 + 1);
          if (q2 > q1) {
            return s.substring(q1 + 1, q2);
          }
        }
        // si valor no entre comillas, extraer token sin espacios/comas
        int start = colon + 1;
        while (start < s.length() && isSpace(s.charAt(start))) start++;
        int end = start;
        while (end < s.length() && s.charAt(end) != ',' && s.charAt(end) != '}' && !isSpace(s.charAt(end))) end++;
        return s.substring(start, end);
      }
    }
    // no se encontró, devolver cadena completa
    return s;
  }
  // no es JSON: devolver tal cual
  return s;
}

// Maneja métodos directos: topic = $iothub/methods/POST/{method_name}/?$rid={rid}
void handleDirectMethod(const char* topic, const String &payload) {
  String t = String(topic);
  // extraer method_name y rid
  // formato: $iothub/methods/POST/actuador/?$rid=1
  // o $iothub/methods/POST/actuador/?$rid=1234
  int p1 = t.indexOf("/POST/");
  if (p1 < 0) {
    Serial.printf("[METHOD] Topic inesperado: %s\n", topic);
    return;
  }
  int startMethod = p1 + 6;
  int qmark = t.indexOf("/?", startMethod);
  if (qmark < 0) qmark = t.indexOf('?', startMethod);
  String methodName;
  String rid;
  if (qmark > startMethod) {
    methodName = t.substring(startMethod, qmark);
    int ridIdx = t.indexOf("$rid=", qmark);
    if (ridIdx >= 0) {
      rid = t.substring(ridIdx + 5);
      // si hay otros params, tomar hasta &
      int amp = rid.indexOf('&');
      if (amp >= 0) rid = rid.substring(0, amp);
    }
  } else {
    methodName = t.substring(startMethod);
  }

  methodName.trim();
  rid.trim();

  Serial.printf("[METHOD] recibido method='%s' rid='%s' payload=%s\n", methodName.c_str(), rid.c_str(), payload.c_str());

  // por ahora soporte solo "actuador"
  if (methodName == "actuador") {
    String cmd = parseCommandFromPayload(payload);
    cmd.trim();
    cmd.toUpperCase();

    if (cmd == "ON") {
      digitalWrite(ACTUATOR_PIN, HIGH);
      Serial.println("[ACT] Actuador ENCENDIDO (method)");
      // responder status 200 con body opcional
      sendMethodResponse(rid, 200, "{\"result\":\"OK\",\"comando\":\"ON\"}");
      return;
    } else if (cmd == "OFF") {
      digitalWrite(ACTUATOR_PIN, LOW);
      Serial.println("[ACT] Actuador APAGADO (method)");
      sendMethodResponse(rid, 200, "{\"result\":\"OK\",\"comando\":\"OFF\"}");
      return;
    } else if (cmd == "RESET") {
      digitalWrite(ACTUATOR_PIN, LOW);
      delay(100);
      digitalWrite(ACTUATOR_PIN, HIGH);
      delay(100);
      digitalWrite(ACTUATOR_PIN, LOW);
      Serial.println("[ACT] Actuador RESET (method)");
      sendMethodResponse(rid, 200, "{\"result\":\"OK\",\"comando\":\"RESET\"}");
      return;
    } else {
      Serial.println("[METHOD] comando no reconocido");
      sendMethodResponse(rid, 404, "{\"error\":\"Comando no reconocido\"}");
      return;
    }
  } else {
    Serial.println("[METHOD] method no soportado");
    sendMethodResponse(rid, 404, "{\"error\":\"Method not supported\"}");
  }
}

void sendMethodResponse(const String &rid, int status, const String &body) {
  if (rid.length() == 0) {
    Serial.println("[METHOD] No rid, no se puede responder");
    return;
  }
  String topicRes = String("$iothub/methods/res/") + String(status) + "/?$rid=" + rid;
  bool ok = mqtt.publish(topicRes.c_str(), body.c_str());
  Serial.printf("[METHOD] Respondido topic=%s status=%d ok=%d body=%s\n", topicRes.c_str(), status, ok, body.c_str());
}

// Callback MQTT: manejar devicebound y methods
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String t = String(topic);
  String pl = "";
  for (unsigned int i = 0; i < length; i++) pl += (char)payload[i];
  pl.trim();

  Serial.printf("[MQTT] Mensaje en topic: %s\n  payload: %s\n", topic, pl.c_str());

  // Direct Methods
  if (t.startsWith("$iothub/methods/POST/")) {
    handleDirectMethod(topic, pl);
    return;
  }

  // Cloud-to-Device (devicebound) — payload puede ser JSON o texto
  // topic example: devices/{deviceId}/messages/devicebound/#
  if (t.indexOf("/messages/devicebound/") >= 0) {
    // parsear
    String cmd = parseCommandFromPayload(pl);
    cmd.trim();
    cmd.toUpperCase();

    if (cmd == "ON") {
      digitalWrite(ACTUATOR_PIN, HIGH);
      Serial.println("[ACT] Actuador ENCENDIDO (C2D)");
    } else if (cmd == "OFF") {
      digitalWrite(ACTUATOR_PIN, LOW);
      Serial.println("[ACT] Actuador APAGADO (C2D)");
    } else if (cmd == "RESET") {
      digitalWrite(ACTUATOR_PIN, LOW);
      delay(100);
      digitalWrite(ACTUATOR_PIN, HIGH);
      delay(100);
      digitalWrite(ACTUATOR_PIN, LOW);
      Serial.println("[ACT] Actuador RESET (C2D)");
    } else {
      Serial.println("[ACT] Comando C2D no reconocido");
    }
    return;
  }

  // Otros topics (telemetry ack u otros) — ignora
  Serial.println("[MQTT] Topic no gestionado");
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

// Conectar a Azure IoT Hub (MQTT sobre TLS)
void conectarAzureIoT() {
  tlsClient.setCACert(AZURE_ROOT_CA);
  mqtt.setServer(IOT_HUB_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(1024); // aumentar buffer para topics largos

  String username = String(IOT_HUB_HOST) + "/" + DEVICE_ID + "/?api-version=2021-04-12";

  String sas = createSasToken(IOT_HUB_HOST, DEVICE_ID, DEVICE_PRIMARY_KEY, SAS_TTL);
  if (sas == "") {
    Serial.println("[MQTT] No se pudo generar SAS token");
    delay(5000);
    return;
  }
  sasExpiry = (unsigned long)time(NULL) + SAS_TTL;

  Serial.printf("[MQTT] Conectando a %s con SAS (expira en %lus)...\n", IOT_HUB_HOST, SAS_TTL);
  if (mqtt.connect(DEVICE_ID, username.c_str(), sas.c_str())) {
    Serial.println("[MQTT] Conectado OK");
    // Suscripciones necesarias:
    if (mqtt.subscribe(TOPIC_COMMANDS.c_str())) {
      Serial.println("[MQTT] Suscrito a comandos C2D");
    } else {
      Serial.println("[MQTT] Suscripcion a comandos C2D fallida");
    }
    if (mqtt.subscribe(TOPIC_METHODS_SUB)) {
      Serial.println("[MQTT] Suscrito a Direct Methods");
    } else {
      Serial.println("[MQTT] Suscripcion a Direct Methods fallida");
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
  char payload[160];
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
  Serial.println("\n=== CNC IoT ESP32 — Azure IoT Hub (SAS) ===");

  pinMode(ACTUATOR_PIN, OUTPUT);
  digitalWrite(ACTUATOR_PIN, LOW);

  dht.begin();
  Serial.println("[DHT22] Iniciado");

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