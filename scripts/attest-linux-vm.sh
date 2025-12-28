#!/bin/bash

set -euo pipefail

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

ATTEST_URL=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/userData?api-version=2025-04-07&format=text" | base64 -d | jq -r ".attest_url")

echo "Attesting VM with $ATTEST_URL"
TOKEN=$(AttestationClient -o token -a $ATTEST_URL)

echo "Verifying using $TOKEN"
