<#
Deploy script para Azure - Segunda Entrega (Migracion IoT desde AWS):
- Arquitectura de dos niveles: Subred Publica y Subred Privada.
- VM Publica (vm-iot-front): acceso SSH/MQTT/Grafana con IP publica y DNS.
- VM Privada (vm-iot-back): InfluxDB aislado, sin IP publica.
- Ambas VMs aprovisionadas con Docker via cloud-init.
- Seguridad por NSGs diferenciados por nivel.
#>

# =====================================================================
# --- FASE 1: Variables Globales y Grupo de Recursos ---
# =====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 1: Variables Globales y Grupo de Recursos" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- Variables Globales ---
$RG_NAME       = "rg-cnc-iot"
$LOCATION      = "centralus"

# Redes
$VNET_NAME            = "vnet-iot"
$VNET_PREFIX          = "10.0.0.0/16"
$PUBLIC_SUBNET_NAME   = "snet-public"
$PUBLIC_SUBNET_PREFIX = "10.0.1.0/24"
$PRIVATE_SUBNET_NAME  = "snet-private"
$PRIVATE_SUBNET_PREFIX= "10.0.2.0/24"

# Seguridad
$NSG_PUBLIC_NAME  = "nsg-public"
$NSG_PRIVATE_NAME = "nsg-private"

# Maquinas Virtuales
$VM_PUBLIC_NAME   = "vm-iot-front"
$VM_PRIVATE_NAME  = "vm-iot-back"
$VM_IMAGE         = "Ubuntu2204"
$VM_SIZE          = "Standard_B1s"
$ADMIN_USER       = "ubuntu"
$DNS_LABEL        = "cnc-iot-david"
$CLOUD_INIT_FILE  = "$PWD/cloud-init.txt"

# IP local del operador (para restriccion SSH)
Write-Host "Obteniendo IP publica local..." -ForegroundColor Yellow
$MY_PUBLIC_IP = (Invoke-RestMethod http://ipinfo.io/ip).Trim()
Write-Host "  -> IP local detectada: $MY_PUBLIC_IP" -ForegroundColor White

# Crear Grupo de Recursos
Write-Host "Creando Resource Group '$RG_NAME' en '$LOCATION'..." -ForegroundColor Yellow
az group create `
    --name     $RG_NAME `
    --location $LOCATION `
    --output   none
Write-Host "  -> Resource Group creado." -ForegroundColor Green

# =====================================================================
# --- FASE 2: Red Virtual (VNet) y Subredes ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 2: Red Virtual (VNet) y Subredes" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Creando VNet '$VNET_NAME' ($VNET_PREFIX)..." -ForegroundColor Yellow
az network vnet create `
    --resource-group $RG_NAME `
    --name           $VNET_NAME `
    --address-prefix $VNET_PREFIX `
    --location       $LOCATION `
    --output         none
Write-Host "  -> VNet creada." -ForegroundColor Green

Write-Host "Creando subred publica '$PUBLIC_SUBNET_NAME' ($PUBLIC_SUBNET_PREFIX)..." -ForegroundColor Yellow
az network vnet subnet create `
    --resource-group  $RG_NAME `
    --vnet-name       $VNET_NAME `
    --name            $PUBLIC_SUBNET_NAME `
    --address-prefix  $PUBLIC_SUBNET_PREFIX `
    --output          none
Write-Host "  -> Subred publica creada." -ForegroundColor Green

Write-Host "Creando subred privada '$PRIVATE_SUBNET_NAME' ($PRIVATE_SUBNET_PREFIX)..." -ForegroundColor Yellow
az network vnet subnet create `
    --resource-group  $RG_NAME `
    --vnet-name       $VNET_NAME `
    --name            $PRIVATE_SUBNET_NAME `
    --address-prefix  $PRIVATE_SUBNET_PREFIX `
    --output          none
Write-Host "  -> Subred privada creada." -ForegroundColor Green

# =====================================================================
# --- FASE 3: Seguridad (NSG) ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 3: Seguridad (NSG)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- NSG Publico ---
Write-Host "Creando NSG publico '$NSG_PUBLIC_NAME'..." -ForegroundColor Yellow
az network nsg create `
    --resource-group $RG_NAME `
    --name           $NSG_PUBLIC_NAME `
    --location       $LOCATION `
    --output         none
Write-Host "  -> NSG publico creado." -ForegroundColor Green

Write-Host "  Agregando regla SSH (puerto 22, solo desde IP del operador: $MY_PUBLIC_IP)..." -ForegroundColor Yellow
az network nsg rule create `
    --resource-group     $RG_NAME `
    --nsg-name           $NSG_PUBLIC_NAME `
    --name               "Allow-SSH" `
    --priority           100 `
    --protocol           Tcp `
    --direction          Inbound `
    --source-address-prefixes "$MY_PUBLIC_IP/32" `
    --source-port-ranges "*" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 22 `
    --access             Allow `
    --output             none

Write-Host "  Agregando regla MQTT (puerto 1883)..." -ForegroundColor Yellow
az network nsg rule create `
    --resource-group     $RG_NAME `
    --nsg-name           $NSG_PUBLIC_NAME `
    --name               "Allow-MQTT" `
    --priority           110 `
    --protocol           Tcp `
    --direction          Inbound `
    --source-address-prefixes "*" `
    --source-port-ranges "*" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 1883 `
    --access             Allow `
    --output             none

Write-Host "  Agregando regla Grafana (puerto 3000)..." -ForegroundColor Yellow
az network nsg rule create `
    --resource-group     $RG_NAME `
    --nsg-name           $NSG_PUBLIC_NAME `
    --name               "Allow-Grafana" `
    --priority           120 `
    --protocol           Tcp `
    --direction          Inbound `
    --source-address-prefixes "*" `
    --source-port-ranges "*" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 3000 `
    --access             Allow `
    --output             none
Write-Host "  -> Reglas del NSG publico configuradas." -ForegroundColor Green

# Asociar NSG publico a la subred publica
Write-Host "  Asociando NSG publico a la subred '$PUBLIC_SUBNET_NAME'..." -ForegroundColor Yellow
az network vnet subnet update `
    --resource-group  $RG_NAME `
    --vnet-name       $VNET_NAME `
    --name            $PUBLIC_SUBNET_NAME `
    --network-security-group $NSG_PUBLIC_NAME `
    --output          none
Write-Host "  -> NSG publico asociado." -ForegroundColor Green

# --- NSG Privado ---
Write-Host "Creando NSG privado '$NSG_PRIVATE_NAME' (aislamiento total de internet)..." -ForegroundColor Yellow
az network nsg create `
    --resource-group $RG_NAME `
    --name           $NSG_PRIVATE_NAME `
    --location       $LOCATION `
    --output         none
Write-Host "  -> NSG privado creado." -ForegroundColor Green

Write-Host "  Agregando regla InfluxDB (puerto 8086) solo desde subred publica..." -ForegroundColor Yellow
az network nsg rule create `
    --resource-group     $RG_NAME `
    --nsg-name           $NSG_PRIVATE_NAME `
    --name               "Allow-InfluxDB-FromPublicSubnet" `
    --priority           100 `
    --protocol           Tcp `
    --direction          Inbound `
    --source-address-prefixes $PUBLIC_SUBNET_PREFIX `
    --source-port-ranges "*" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 8086 `
    --access             Allow `
    --output             none
Write-Host "  -> Regla InfluxDB configurada (solo desde $PUBLIC_SUBNET_PREFIX)." -ForegroundColor Green

# Asociar NSG privado a la subred privada
Write-Host "  Asociando NSG privado a la subred '$PRIVATE_SUBNET_NAME'..." -ForegroundColor Yellow
az network vnet subnet update `
    --resource-group  $RG_NAME `
    --vnet-name       $VNET_NAME `
    --name            $PRIVATE_SUBNET_NAME `
    --network-security-group $NSG_PRIVATE_NAME `
    --output          none
Write-Host "  -> NSG privado asociado." -ForegroundColor Green

# =====================================================================
# --- FASE 4: Creacion de VMs (limpias, sin cloud-init) ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 4: Creacion de VMs (sin cloud-init)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- VM Publica ---
Write-Host "Desplegando VM publica '$VM_PUBLIC_NAME' en subred '$PUBLIC_SUBNET_NAME'..." -ForegroundColor Yellow
az vm create `
    --resource-group             $RG_NAME `
    --name                       $VM_PUBLIC_NAME `
    --image                      $VM_IMAGE `
    --size                       $VM_SIZE `
    --admin-username             $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name                  $VNET_NAME `
    --subnet                     $PUBLIC_SUBNET_NAME `
    --nsg                        $NSG_PUBLIC_NAME `
    --public-ip-sku              Standard `
    --public-ip-address-dns-name $DNS_LABEL `
    --output                     none
Write-Host "  -> VM publica '$VM_PUBLIC_NAME' creada (limpia, sin cloud-init)." -ForegroundColor Green

# --- VM Privada (sin IP publica) ---
Write-Host "Desplegando VM privada '$VM_PRIVATE_NAME' en subred '$PRIVATE_SUBNET_NAME' (sin IP publica)..." -ForegroundColor Yellow
az vm create `
    --resource-group    $RG_NAME `
    --name              $VM_PRIVATE_NAME `
    --image             $VM_IMAGE `
    --size              $VM_SIZE `
    --admin-username    $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name         $VNET_NAME `
    --subnet            $PRIVATE_SUBNET_NAME `
    --nsg               $NSG_PRIVATE_NAME `
    --public-ip-address '""' `
    --output            none
Write-Host "  -> VM privada '$VM_PRIVATE_NAME' creada (sin IP publica)." -ForegroundColor Green

# =====================================================================
# --- Obtener IPs para el provisioning cruzado ---
# =====================================================================

Write-Host ""
Write-Host "Obteniendo IPs de las VMs para provisioning cruzado..." -ForegroundColor Yellow

$VM_PUBLIC_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --show-details `
    --query          "publicIps" `
    --output         tsv).Trim()

$VM_FRONT_PRIVATE_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --show-details `
    --query          "privateIps" `
    --output         tsv).Trim()

$VM_BACK_PRIVATE_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PRIVATE_NAME `
    --show-details `
    --query          "privateIps" `
    --output         tsv).Trim()

Write-Host "  -> IP publica  de $VM_PUBLIC_NAME  : $VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "  -> IP privada  de $VM_PUBLIC_NAME  : $VM_FRONT_PRIVATE_IP" -ForegroundColor Green
Write-Host "  -> IP privada  de $VM_PRIVATE_NAME : $VM_BACK_PRIVATE_IP" -ForegroundColor Green

# =====================================================================
# --- FASE 4b: Aprovisionamiento via az vm run-command invoke ---
# Evita cloud-init y SSH; el agente de Azure ejecuta los scripts bash
# directamente dentro de cada VM con privilegios de root.
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 4b: Aprovisionamiento via az vm run-command invoke" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- Aprovisionar VM Publica: Mosquitto (INF-2) + Grafana (INF-5) ---
Write-Host ""
Write-Host "Aprovisionando '$VM_PUBLIC_NAME' (Mosquitto + Grafana)..." -ForegroundColor Yellow
Write-Host "  Script    : provision-front.sh" -ForegroundColor Gray
Write-Host "  Parametros: VM_BACK_IP=$VM_BACK_PRIVATE_IP" -ForegroundColor Gray

$frontResult = az vm run-command invoke `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --command-id     RunShellScript `
    --scripts        "@$SCRIPTS_DIR\provision-front.sh" `
    --parameters     $VM_BACK_PRIVATE_IP $INFLUX_TOKEN `
    --output         json | ConvertFrom-Json

foreach ($item in $frontResult.value) {
    if ($item.message) { Write-Host $item.message }
}
Write-Host "  -> Aprovisionamiento de '$VM_PUBLIC_NAME' completado." -ForegroundColor Green

# --- Aprovisionar VM Privada: InfluxDB (INF-3/INF-4) + Telegraf (Bridge) ---
Write-Host ""
Write-Host "Aprovisionando '$VM_PRIVATE_NAME' (InfluxDB + Telegraf)..." -ForegroundColor Yellow
Write-Host "  Script    : provision-back.sh" -ForegroundColor Gray
Write-Host "  Parametros: VM_FRONT_IP=$VM_FRONT_PRIVATE_IP" -ForegroundColor Gray

$backResult = az vm run-command invoke `
    --resource-group $RG_NAME `
    --name           $VM_PRIVATE_NAME `
    --command-id     RunShellScript `
    --scripts        "@$SCRIPTS_DIR\provision-back.sh" `
    --parameters     $VM_FRONT_PRIVATE_IP `
    --output         json | ConvertFrom-Json

foreach ($item in $backResult.value) {
    if ($item.message) { Write-Host $item.message }
}
Write-Host "  -> Aprovisionamiento de '$VM_PRIVATE_NAME' completado." -ForegroundColor Green

# =====================================================================
# --- FASE 5: Resumen de Conectividad ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " DESPLIEGUE FINALIZADO EXITOSAMENTE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  VM Publica  ($VM_PUBLIC_NAME):" -ForegroundColor Green
Write-Host "    IP Publica  : $VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    IP Privada  : $VM_FRONT_PRIVATE_IP" -ForegroundColor Green
Write-Host "    DNS         : $DNS_LABEL.$LOCATION.cloudapp.azure.com" -ForegroundColor Green
Write-Host "    SSH         : ssh $ADMIN_USER@$VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    MQTT        : $VM_PUBLIC_IP:1883  (flux_user / flux_pass)" -ForegroundColor Green
Write-Host "    Grafana     : http://$VM_PUBLIC_IP:3000  (admin / admin123)" -ForegroundColor Green
Write-Host ""
Write-Host "  VM Privada  ($VM_PRIVATE_NAME):" -ForegroundColor Green
Write-Host "    IP Privada  : $VM_BACK_PRIVATE_IP" -ForegroundColor Green
Write-Host "    InfluxDB    : http://$VM_BACK_PRIVATE_IP:8086  (accesible solo desde $PUBLIC_SUBNET_PREFIX)" -ForegroundColor Green
Write-Host "    Org/Bucket  : flux / flux_cnc" -ForegroundColor Green
Write-Host ""
Write-Host "  [INF-4] Token InfluxDB — compartir con equipo de Backend:" -ForegroundColor Yellow
Write-Host "    INFLUX_TOKEN  = $INFLUX_TOKEN" -ForegroundColor Yellow
Write-Host "    INFLUX_URL    = http://$VM_BACK_PRIVATE_IP:8086" -ForegroundColor Yellow
Write-Host "    INFLUX_ORG    = flux" -ForegroundColor Yellow
Write-Host "    INFLUX_BUCKET = flux_cnc" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Flujo de red:" -ForegroundColor Cyan
Write-Host "    ESP32       --> Mosquitto  ($VM_PUBLIC_IP:1883)" -ForegroundColor Cyan
Write-Host "    Telegraf    --> Mosquitto  ($VM_FRONT_PRIVATE_IP:1883)  [VNet interna]" -ForegroundColor Cyan
Write-Host "    Telegraf    --> InfluxDB   (influxdb:8086)              [Docker interno]" -ForegroundColor Cyan
Write-Host "    Grafana     --> InfluxDB   ($VM_BACK_PRIVATE_IP:8086)  [VNet interna]" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green

