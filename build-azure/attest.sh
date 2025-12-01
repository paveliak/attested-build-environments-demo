#!/bin/bash

set -e

SCRIPTPATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P )"

ATTEST_VM_NAME="${AZURE_VM_NAME}attest"
IMAGE_ID=$(az sig image-definition show --resource-group $AZURE_RESOURCE_GROUP --gallery-name $AZURE_GALLERY_NAME --gallery-image-name $AZURE_IMAGE_DEFINITION | jq -r ".id")

echo "Creating attested VM..."
$SCRIPTPATH/create-vm $ATTEST_VM_NAME $IMAGE_ID TrustedLaunch
ATTEST_VM_ID=$(az vm show --resource-group $AZURE_RESOURCE_GROUP --name $ATTEST_VM_NAME | jq -r ".id")

echo "Attesting VM..."
#TODO

echo "Deallocating attested VM"
az vm deallocate --id $ATTEST_VM_ID
