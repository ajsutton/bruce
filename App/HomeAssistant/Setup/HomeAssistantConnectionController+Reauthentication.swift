extension HomeAssistantConnectionController {
  func requireReauthentication() {
    guard let credentials = connectedCredentials else {
      return
    }
    invalidateConnectionOperation()
    connectionCheckState = .reauthenticationRequired
    step = .configured(credentials)
  }

  func reauthenticate() {
    guard let credentials = connectedCredentials else {
      return
    }
    let candidate = HomeAssistantConnectionCandidate(
      instanceID: credentials.instanceID,
      name: credentials.instanceName,
      internalURL: credentials.internalURL,
      externalURL: credentials.externalURL,
      activeURL: credentials.lastSuccessfulURL,
      source: .manual
    )
    invalidateConnectionOperation()
    step = .confirmation(candidate)
    requestAuthentication()
  }
}
