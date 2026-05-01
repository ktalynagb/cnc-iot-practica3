#!/usr/bin/env bash
set -euo pipefail

RG_NAME="rg-cnc-iot"
LOCATION="centralus"

VNET_NAME="vnet-iot"
VNET_PREFIX="10.0.0.0/16"
PUBLIC_SUBNET_NAME="snet-public"
PUBLIC_SUBNET_PREFIX="10.0.1.0/24"
PRIVATE_SUBNET_NAME="snet-private"
PRIVATE_SUBNET_PREFIX="10.0.2.0/24"

NSG_PUBLIC_NAME="nsg-public"
NSG_PRIVATE_NAME="nsg-private"

VM_PUBLIC_NAME="vm-iot-front"
VM_PRIVATE_NAME="vm-iot-back"
VM_IMAGE="Ubuntu2204"
VM_SIZE="Standard_D2s_v3"
ADMIN_USER="ubuntu"
DNS_LABEL="cnc-iot-david"

INFLUX_TOKEN="flux-cnc-iot-admin-token-2024"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

trap 'echo "ERROR: el despliegue falló. Revisa el mensaje anterior." >&2' ERR

echo "============================================================"
echo " FASE 4: Creacion de VMs (sin cloud-init)"
echo "============================================================"

echo "Desplegando VM publica '${VM_PUBLIC_NAME}'..."
az vm create \
  --resource-group "$RG_NAME" \
  --name "$VM_PUBLIC_NAME" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --subnet "$PUBLIC_SUBNET_NAME" \
  --nsg "$NSG_PUBLIC_NAME" \
  --public-ip-sku Standard \
  --public-ip-address-dns-name "$DNS_LABEL" \
  --output none
echo "  -> VM publica creada."

echo "Desplegando VM privada '${VM_PRIVATE_NAME}'..."
az vm create \
  --resource-group "$RG_NAME" \
  --name "$VM_PRIVATE_NAME" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --subnet "$PRIVATE_SUBNET_NAME" \
  --nsg "$NSG_PRIVATE_NAME" \
  --public-ip-address "" \
  --output none
echo "  -> VM privada creada."

echo "Obteniendo IPs..."
VM_PUBLIC_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PUBLIC_NAME" --show-details --query publicIps --output tsv | tr -d '[:space:]')"
VM_FRONT_PRIVATE_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PUBLIC_NAME" --show-details --query privateIps --output tsv | tr -d '[:space:]')"
VM_BACK_PRIVATE_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PRIVATE_NAME" --show-details --query privateIps --output tsv | tr -d '[:space:]')"

echo "  -> IP publica: ${VM_PUBLIC_IP}"
echo "  -> IP privada front: ${VM_FRONT_PRIVATE_IP}"
echo "  -> IP privada back: ${VM_BACK_PRIVATE_IP}"

echo "Aprovisionando VM publica..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_PUBLIC_NAME" \
  --command-id RunShellScript \
  --scripts "@${SCRIPTS_DIR}/provision-front.sh" \
  --parameters "$VM_BACK_PRIVATE_IP" "$INFLUX_TOKEN" \
  --output json

echo "Aprovisionando VM privada..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_PRIVATE_NAME" \
  --command-id RunShellScript \
  --scripts "@${SCRIPTS_DIR}/provision-back.sh" \
  --parameters "$VM_FRONT_PRIVATE_IP" \
  --output json

echo "============================================================"
echo "Fase 4 finalizada"
echo "============================================================"