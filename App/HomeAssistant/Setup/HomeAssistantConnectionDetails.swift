import SwiftUI

struct HomeAssistantConnectionDetails: View {
  let credentials: HomeAssistantCredentials
  let copy: HomeAssistantInterfaceCopy

  var body: some View {
    if let internalURL = credentials.internalURL {
      LabeledContent(copy.internalRoute, value: internalURL.absoluteString)
    }
    if let externalURL = credentials.externalURL {
      LabeledContent(copy.externalRoute, value: externalURL.absoluteString)
    }
    LabeledContent(copy.lastSuccessfulRoute, value: credentials.lastSuccessfulURL.absoluteString)
  }
}
