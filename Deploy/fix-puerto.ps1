# Script para corregir el puerto del Frontend a 3000

# 1. Cargar tus credenciales de Docker del .env
Get-Content ".\.env" | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2) { Set-Item -Path "env:$($parts[0].Trim())" -Value $parts[1].Trim() }
}

$rg = "cnc-iot-rg"
$appgw = "cnciot-appgw"

Write-Host "Obteniendo datos de la red actual..."
$privSubnetId = az network vnet subnet show --resource-group $rg --vnet-name cnciot-vnet --name private-subnet --query id -o tsv
$backendPrivateIp = (az container show --resource-group $rg --name cnciot-backend -o json | ConvertFrom-Json).ipAddress.ip

Write-Host "1. Eliminando el contenedor frontend mal configurado..."
az container delete --resource-group $rg --name cnciot-frontend --yes

Write-Host "2. Recreando contenedor frontend abriendo el puerto 3000..."
az container create --resource-group $rg --name cnciot-frontend --image $env:FRONTEND_IMAGE --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports 3000 --environment-variables BACKEND_URL="http://${backendPrivateIp}:8000" --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null

Start-Sleep -Seconds 10
$newFrontendIp = (az container show --resource-group $rg --name cnciot-frontend -o json | ConvertFrom-Json).ipAddress.ip

Write-Host "Contenedor listo. Nueva IP de frontend: $newFrontendIp"
Write-Host "3. Actualizando la ruta del Application Gateway hacia el puerto 3000..."

# Actualizamos la IP en el pool (por si Azure le asignó una diferente al recrearlo)
az network application-gateway address-pool update --gateway-name $appgw --resource-group $rg --name FrontendPoolExplicit --servers $newFrontendIp | Out-Null

# Actualizamos el puerto al 3000
az network application-gateway http-settings update --gateway-name $appgw --resource-group $rg --name FrontendHttpSettings --port 3000 | Out-Null

Write-Host "`n¡Cirugía completada! Entra a http://20.29.102.93 y deberías ver el dashboard."