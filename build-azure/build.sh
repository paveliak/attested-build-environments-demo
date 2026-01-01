#!/bin/bash

set -e

SCRIPTPATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P )"
VM_USER="${AZURE_VM_USER:-azureuser}"

echo "Creating resource group..."
az account set --subscription $AZURE_SUBSCRIPTION_ID
az group create --resource-group $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION

echo "Creating image VM..."
IMAGE_VM_NAME="${AZURE_VM_NAME}"
$SCRIPTPATH/create-vm $IMAGE_VM_NAME Standard
IMAGE_VM_ID=$(az vm show --resource-group $AZURE_RESOURCE_GROUP --name $IMAGE_VM_NAME | jq -r ".id")
IP_ADDR=$($SCRIPTPATH/get-ip $IMAGE_VM_ID)
$SCRIPTPATH/test-connectivity $IP_ADDR

echo "Copying files to VM..."
scp -r -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$SCRIPTPATH/../initramfs" "${VM_USER}@${IP_ADDR}":
scp -r -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$SCRIPTPATH/../scripts"  "${VM_USER}@${IP_ADDR}":
scp    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$SCRIPTPATH/image-attestation"  "${VM_USER}@${IP_ADDR}":
scp    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$SCRIPTPATH/AttestationClient"  "${VM_USER}@${IP_ADDR}":

echo "Building VM image..."
ssh    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}" "sudo SSH_KEYS_URL=$SSH_KEYS_URL scripts/build-linux-vm.sh"

echo "Deallocating image VM..."
az vm deallocate --id $IMAGE_VM_ID

echo "Detaching OS disk..."
DISK_ID=$(az vm show --id $IMAGE_VM_ID | jq -r ".storageProfile.osDisk.managedDisk.id")
IMAGE_ID=$(az disk show --id $DISK_ID | jq -r ".creationData.imageReference.id")
SWAP_DISK_NAME="${AZURE_VM_NAME}-$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16 ; echo)"
az disk create --image-reference $IMAGE_ID --resource-group $AZURE_RESOURCE_GROUP --name $SWAP_DISK_NAME --security-type Standard --hyper-v-generation V2
SWAP_DISK_ID=$(az disk show --resource-group $AZURE_RESOURCE_GROUP --name $SWAP_DISK_NAME | jq -r ".id")
az vm update --name $IMAGE_VM_NAME --resource-group $AZURE_RESOURCE_GROUP --os-disk $SWAP_DISK_ID

echo "Creating hasher VM..."
HASHER_VM_NAME="${AZURE_VM_NAME}hash"
$SCRIPTPATH/create-vm $HASHER_VM_NAME Standard
HASHER_VM_ID=$(az vm show --resource-group $AZURE_RESOURCE_GROUP --name $HASHER_VM_NAME | jq -r ".id")
IP_ADDR=$($SCRIPTPATH/get-ip $HASHER_VM_ID)
$SCRIPTPATH/test-connectivity $IP_ADDR

echo "Attaching image disk (with 10% added space for verity hashes)..."
DISK_SIZE=$(az disk show --id $DISK_ID --query "diskSizeGB")
NEW_DISK_SIZE=$(echo "$DISK_SIZE * 1.1" | bc)
NEW_DISK_SIZE=$(printf "%.0f" "$NEW_DISK_SIZE")
az disk update --id $DISK_ID --disk-size-gb $NEW_DISK_SIZE
az vm disk attach --resource-group $AZURE_RESOURCE_GROUP --vm-name $HASHER_VM_NAME --disk-id $DISK_ID --lun 0

echo "Setting up Verity..."
scp -r -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "$SCRIPTPATH/../scripts"  "${VM_USER}@${IP_ADDR}":
ssh    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}" "sudo scripts/rootfs-prepare-verity.sh"
ssh    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}" "sudo scripts/rootfs-measure-verity.sh"

echo "Fetching enlightened kernel"
scp    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}":~/uki.efi .
scp    -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}":~/MOK.pem .
MOK_BASE64=$(sed '/-----BEGIN/d;/-----END/d' MOK.pem | tr -d '\n')

echo "Deleting hasher VM..."
az vm delete --id $HASHER_VM_ID --yes

echo "Attaching OS disk back..."
az vm update --name $IMAGE_VM_NAME --resource-group $AZURE_RESOURCE_GROUP --os-disk $DISK_ID
az disk delete --id $SWAP_DISK_ID --yes

echo "Creating VHD blob..."
STORAGE_ACCOUNT_NAME="${AZURE_VM_NAME}storage"
CONTAINER_NAME="vhd"
BLOB_NAME="disk.vhd"
DISK_URL="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$BLOB_NAME"

az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION --sku Standard_LRS --kind StorageV2
az storage container create --name vhd --account-name $STORAGE_ACCOUNT_NAME
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $AZURE_RESOURCE_GROUP | jq -r ".id")

DISK_SAS=$(az disk grant-access --id $DISK_ID --duration-in-seconds 86400 --access-level Read | jq -r ".accessSAS")

az storage blob copy start --source-uri "$DISK_SAS" --account-name $STORAGE_ACCOUNT_NAME --destination-container $CONTAINER_NAME --destination-blob $BLOB_NAME
while true; do
  STATUS=$(az storage blob show --account-name $STORAGE_ACCOUNT_NAME --container-name $CONTAINER_NAME --name $BLOB_NAME | jq -r ".properties.copy.status")
  echo "Copy status: $STATUS"
  if [ "$STATUS" == "success" ]; then
    echo "Copy completed!"
    break
  elif [ "$STATUS" == "failed" ]; then
    echo "Copy failed."
    exit 1
  fi
  sleep 10
done

echo "Creating image version..."
az deployment group create \
  --resource-group $AZURE_RESOURCE_GROUP \
  --template-file "$SCRIPTPATH/image.bicep" \
  --parameters location="$AZURE_LOCATION" galleryName="$AZURE_GALLERY_NAME" imageDefinitionName="$AZURE_IMAGE_DEFINITION" imageVersion="$AZURE_IMAGE_VERSION" storageAccountId="$STORAGE_ACCOUNT_ID" blobUrl="$DISK_URL" mokCertBase64="$MOK_BASE64"

echo "Deleting image VM..."
az vm delete --id $IMAGE_VM_ID --yes
