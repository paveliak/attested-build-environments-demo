param location string
param galleryName string
param imageDefinitionName string
param imageVersion string
param storageAccountId string
param blobUrl string
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
        value: 'TrustedLaunchAndConfidentialVmSupported'
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
      osDiskImage: {
        source: {
          storageAccountId: storageAccountId
          uri: blobUrl
        }
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
