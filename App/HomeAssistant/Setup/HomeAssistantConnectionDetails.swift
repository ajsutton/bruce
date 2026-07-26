import SwiftUI

struct HomeAssistantConnectionDetails: View {
  let credentials: HomeAssistantCredentials

  var body: some View {
    if let internalURL = credentials.internalURL {
      LabeledContent("Internal", value: internalURL.absoluteString)
    }
    if let externalURL = credentials.externalURL {
      LabeledContent("External", value: externalURL.absoluteString)
    }
    LabeledContent("Last successful route", value: credentials.lastSuccessfulURL.absoluteString)
  }
}
