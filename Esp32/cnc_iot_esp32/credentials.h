#ifndef CREDENTIALS_H
#define CREDENTIALS_H

// WiFi
const char* WIFI_SSID     = "COWORKING";
const char* WIFI_PASSWORD = "coworking2026..";

// Azure IoT Hub — completar con los valores que entregue Ktalyna (BE-2)
const char* IOT_HUB_HOST = "TU-HUB.azure-devices.net";   // ← reemplazar
const char* DEVICE_ID    = "esp32-cnc1";                   // ← acordar con BE-2

// CA raíz de Azure IoT Hub (DigiCert Global Root G2)
// Referencia oficial: https://learn.microsoft.com/azure/iot-hub/reference-iot-hub-tls-support
const char* AZURE_ROOT_CA = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDjjCCAnagAwIBAgIQAzrx5qcRqaC7KGSxHQn65TANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0xMzA4MDExMjAwMDBaFw0zODAxMTUxMjAwMDBaMGExCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
b20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IEcyMIIBIjANBgkqhkiG
9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuzfNNNx7a8myaJCtSnX/RrohCgiN9RlUyfuI
2/Ou8jqJkTx65qsGGmvPrC3oXgkkRLpimn7Wo6h+4FR1IAWsULecYxpsMNzaHxmx
1x7e/dfgy5SDN67sH0NO3Xss0r0upS/kqbitOtSZpLYl6ZtrAGCSYP9PIUkY92eQ
q2EGnI/yuum06ZIya7XzV+hdG82MHauVBJVJ8zUtluNJbd134/tJS7SsVQepj5Wz
tCO7TG1F8PapspUwtP1MVYwnSlcUfIKdzXOS0xZKBgyMUNGPHgm+F6HmIcr9g+UQ
vIOlCsRnKPZzFBQ9RnbDhxSJITRNrw9FDKZJobq7nMWxM4MphQIDAQABo2YwZDAO
BgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUTiJUIBiV
5uNu5g/6+rkS7QYXjzkwHwYDVR0jBBgwFoAUTiJUIBiV5uNu5g/6+rkS7QYXjzk
wDQYJKoZIhvcNAQELBQADggEBAGBnKJRvDkhj6zHd6mcY1Yl9PMWLSn/pvtsrF9+
wX3N3KjITOYFnQoQj8kVnNeyIv/iPsGEMNKSuIEyExtv4NeF22d+mQrvHRAiGfzZ
0JFrabA0UWTW98kndth/Jsw1HKj2ZL7tcu7XUIOGZX1NGFdtom/DzMNU+MeKNhJ7
jitralj41E6Vf8PlwUHBHQRFXGU7Aj64GxJUTFy8bJZ918rGOmaFvE7FBcf6IKsh
PECBVDdYSjaNKVkZCIGIxuPQ8YsK+5FaHnLFnI8oF4HFo/PL3mGajKQ/if1pPKr
VtVJbkpXPQPJSNFqcRyvJCBXMKi4WSTH7cpiM=
-----END CERTIFICATE-----
)EOF";

// Certificado del dispositivo (X.509) — generado por Kta (BE-2)
const char* DEVICE_CERT = R"EOF(
-----BEGIN CERTIFICATE-----
PENDIENTE: pegar aquí el .pem del dispositivo que entregue Kta
-----END CERTIFICATE-----
)EOF";

// Llave privada del dispositivo — generada junto al certificado (BE-2)
const char* DEVICE_PRIVATE_KEY = R"EOF(
-----BEGIN RSA PRIVATE KEY-----
PENDIENTE: pegar aquí la llave privada .key que entregue Kta
-----END RSA PRIVATE KEY-----
)EOF";

#endif
