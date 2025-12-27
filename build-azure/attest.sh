#!/bin/bash

set -e

SCRIPTPATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P )"
VM_USER="${AZURE_VM_USER:-azureuser}"

b64url() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

echo "Creating attestation provider..."
ATTEST_PROVIDER_NAME="${AZURE_VM_NAME}maa"
az attestation create --name $ATTEST_PROVIDER_NAME --resource-group $AZURE_RESOURCE_GROUP --location $AZURE_LOCATION
ATTEST_PROVIDER_ID=$(az attestation show --resource-group $AZURE_RESOURCE_GROUP --name $ATTEST_PROVIDER_NAME | jq -r ".id")
ATTEST_PROVIDER_URL=$(az attestation show --resource-group $AZURE_RESOURCE_GROUP --name $ATTEST_PROVIDER_NAME | jq -r ".attestUri")

echo "Setting attestation policy..."
POLICY_B64=$(cat policy.txt | b64url)
JWT_HEADER="{\"alg\":\"none\",\"typ\":\"JWT\"}"
JWT_BODY="{\"AttestationPolicy\":\"$POLICY_B64\"}"
JWT_HEADER_B64=$(echo -n "$JWT_HEADER" | b64url)
JWT_BODY_B64=$(echo -n "$JWT_BODY" | b64url)

curl -X PUT -f "$ATTEST_PROVIDER_URL/policies/AzureGuest?api-version=2022-08-01" \
  -H "Authorization: Bearer $(az account get-access-token --resource https://attest.azure.net | jq -r '.accessToken')" \
  -H "Content-Type: application/json" \
  -d "$JWT_HEADER_B64.$JWT_BODY_B64."

ATTEST_VM_NAME="${AZURE_VM_NAME}attest"
IMAGE_ID=$(az sig image-definition show --resource-group $AZURE_RESOURCE_GROUP --gallery-name $AZURE_GALLERY_NAME --gallery-image-name $AZURE_IMAGE_DEFINITION | jq -r ".id")

echo "Creating attested VM..."
$SCRIPTPATH/create-vm $ATTEST_VM_NAME TrustedLaunch $IMAGE_ID
ATTEST_VM_ID=$(az vm show --resource-group $AZURE_RESOURCE_GROUP --name $ATTEST_VM_NAME | jq -r ".id")
ATTEST_PRINCIPAL_ID=$(az vm show --resource-group $AZURE_RESOURCE_GROUP --name $ATTEST_VM_NAME | jq -r ".identity.principalId")
az role assignment create --assignee $ATTEST_PRINCIPAL_ID --role "Attestation Reader" --scope $ATTEST_PROVIDER_ID

# TODO VM should not have SSH access and attestation should be triggered upon VM start-up (e.g. via systemd service)
echo "Attesting VM..."
IP_ADDR=$($SCRIPTPATH/get-ip $ATTEST_VM_ID)
$SCRIPTPATH/test-connectivity $IP_ADDR
ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${VM_USER}@${IP_ADDR}" "sudo ATTEST_URL=$ATTEST_PROVIDER_URL scripts/attest-linux-vm.sh"

echo "Deallocating attested VM"
az vm deallocate --id $ATTEST_VM_ID
