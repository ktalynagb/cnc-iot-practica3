<#
Script de Recuperación (Con Autenticación de Docker Hub):
Supera el Rate Limit autenticándose explícitamente en index.docker.io
#>

param([string]$EnvFile = ".\.env")

# 1. Cargar Variables
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2) { Set-Item -Path "env:$($parts[0].Trim())" -Value $parts[1].Trim() }
}

$rg = $env:RG_NAME
$vnet = $env:VNET_NAME
$privSubnet = $env:PRIVATE_SUBNET_NAME
$appgw = $env:APPGW_NAME
$publicIpName = $env:PUBLIC_IP_NAME

# Validar credenciales de Docker
if (-not $env:DOCKER_USERNAME -or -not $env:DOCKER_PASSWORD) {
    Write-Error "Faltan DOCKER_USERNAME o DOCKER_PASSWORD en tu archivo .env"
    exit 1
}

Write-Host "Recuperando IDs de la infraestructura existente..."
$privSubnetId = az network vnet subnet show --resource-group $rg --vnet-name $vnet --name $privSubnet --query id -o tsv
$publicIp = az network public-ip show --resource-group $rg --name $publicIpName --query "ipAddress" -o tsv

# 2. Reintentar Contenedores CON AUTENTICACIÓN
Write-Host "Iniciando despliegue autenticado en Docker Hub para evadir el límite de tasa..."

az container create --resource-group $rg --name $env:ACI_DB_NAME --image $env:DB_IMAGE --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports 5432 --environment-variables POSTGRES_DB=$env:DB_NAME POSTGRES_USER=$env:DB_USER POSTGRES_PASSWORD=$env:DB_PASSWORD --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 15
$dbPrivateIp = (az container show --resource-group $rg --name $env:ACI_DB_NAME -o json | ConvertFrom-Json).ipAddress.ip

az container create --resource-group $rg --name $env:ACI_BACKEND_NAME --image $env:BACKEND_IMAGE --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports 8000 --environment-variables DB_HOST=$dbPrivateIp DB_PORT=5432 DB_NAME=$env:DB_NAME DB_USER=$env:DB_USER DB_PASSWORD=$env:DB_PASSWORD --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 10
$backendPrivateIp = (az container show --resource-group $rg --name $env:ACI_BACKEND_NAME -o json | ConvertFrom-Json).ipAddress.ip

az container create --resource-group $rg --name $env:ACI_FRONTEND_NAME --image $env:FRONTEND_IMAGE --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports 80 --environment-variables BACKEND_URL="http://${backendPrivateIp}:8000" --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 10
$frontendPrivateIp = (az container show --resource-group $rg --name $env:ACI_FRONTEND_NAME -o json | ConvertFrom-Json).ipAddress.ip

# 3. Aplicar Reglas del AppGW
if (-not $frontendPrivateIp -or -not $backendPrivateIp) {
    Write-Error "Fallo crítico: No se pudieron obtener las IPs. Verifica tus credenciales de Docker Hub."
    exit 1
}

Write-Host "Contenedores listos. IPs recuperadas: Frontend ($frontendPrivateIp), Backend ($backendPrivateIp)"
Write-Host "Finalizando configuración del Application Gateway..."

az network application-gateway frontend-port create --gateway-name $appgw --resource-group $rg --name Port80 --port 80 | Out-Null
az network application-gateway address-pool create --gateway-name $appgw --resource-group $rg --name FrontendPoolExplicit --servers $frontendPrivateIp | Out-Null
az network application-gateway address-pool create --gateway-name $appgw --resource-group $rg --name BackendPool --servers $backendPrivateIp | Out-Null
az network application-gateway http-settings create --gateway-name $appgw --resource-group $rg --name FrontendHttpSettings --port 80 --protocol Http --cookie-based-affinity Disabled | Out-Null
az network application-gateway http-settings create --gateway-name $appgw --resource-group $rg --name BackendHttpSettings --port 8000 --protocol Http --cookie-based-affinity Disabled | Out-Null
az network application-gateway http-listener create --gateway-name $appgw --resource-group $rg --name AppGwFrontListener --frontend-port Port80 --frontend-ip appGatewayFrontendIP | Out-Null
az network application-gateway url-path-map create --gateway-name $appgw --resource-group $rg --name UrlPathMap --rule-name DatosRule --paths "/datos/*" --address-pool BackendPool --http-settings BackendHttpSettings --default-address-pool FrontendPoolExplicit --default-http-settings FrontendHttpSettings | Out-Null
az network application-gateway rule create --gateway-name $appgw --resource-group $rg --name RequestRule-PathBased --rule-type PathBasedRouting --http-listener AppGwFrontListener --url-path-map UrlPathMap --priority 100 | Out-Null

Write-Host "Limpiando regla temporal..."
az network application-gateway rule delete --gateway-name $appgw --resource-group $rg --name rule1 | Out-Null
az network application-gateway http-listener delete --gateway-name $appgw --resource-group $rg --name appGatewayHttpListener | Out-Null
az network application-gateway frontend-port delete --gateway-name $appgw --resource-group $rg --name appGatewayFrontendPort | Out-Null

Write-Host "`n¡Recuperación exitosa! Frontend público en: http://${publicIp}:80"