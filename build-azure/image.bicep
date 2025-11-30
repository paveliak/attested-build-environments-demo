param location string
param galleryName string
param imageDefinitionName string
param imageVersion string
param sourceId string
param mokCertBase64 string

resource gallery 'Microsoft.Compute/galleries@2024-03-03' = {
  name: galleryName
  location: location
}

resource imageDef 'Microsoft.Compute/galleries/images@2024-03-03' = {
  parent: gallery
  name: imageDefinitionName
  location: location
  properties: {
    identifier: {
      publisher: 'DemoPublisher'
      offer: 'DemoOffer'
      sku: 'DemoSku'
    }
    features: [
      {
        name: 'SecurityType'
        value: 'TrustedLaunchSupported'
      }
    ]
    osType: 'Linux'
    osState: 'Specialized'
    hyperVGeneration: 'V2'
  }
}

resource imageVer 'Microsoft.Compute/galleries/images/versions@2024-03-03' = {
  parent: imageDef
  name: imageVersion
  location: location
  properties: {
    storageProfile: {
      source: {
        virtualMachineId: sourceId
      }
    }
    securityProfile: {
      uefiSettings: {
        signatureTemplateNames: [
          'MicrosoftUefiCertificateAuthorityTemplate'
        ]
        additionalSignatures: {
          db: [
            {
              type: 'x509'
              value: [
                mokCertBase64
              ]
            }           
          ] 
        }
      }
    }
  }
}
