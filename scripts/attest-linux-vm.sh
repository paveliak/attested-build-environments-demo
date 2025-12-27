#!/bin/bash

set -e

SCRIPTPATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P )"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Attesting VM with $ATTEST_URL"
ls -al
#sudo ./AttestationClient -o token -a https://attest.cus.attest.azure.net
