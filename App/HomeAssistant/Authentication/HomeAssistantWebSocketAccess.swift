import Foundation

enum HomeAssistantServerIdentity: Equatable, Sendable {
  case instance(String)
  case endpoints(internalURL: URL?, externalURL: URL?)

  init(_ credentials: HomeAssistantCredentials) {
    if let instanceID = credentials.instanceID {
      self = .instance(instanceID)
    } else {
      self = .endpoints(
        internalURL: credentials.internalURL,
        externalURL: credentials.externalURL
      )
    }
  }
}

struct HomeAssistantObservationIdentity: Equatable, Sendable {
  let server: HomeAssistantServerIdentity
  let authenticationSessionEpoch: Int
}

struct HomeAssistantWebSocketAccess: Sendable {
  let baseURL: URL
  let url: URL
  let accessToken: String
  let credentialGeneration: Int
  let authenticationSessionEpoch: Int
  let serverIdentity: HomeAssistantServerIdentity

  var observationIdentity: HomeAssistantObservationIdentity {
    HomeAssistantObservationIdentity(
      server: serverIdentity,
      authenticationSessionEpoch: authenticationSessionEpoch
    )
  }
}

extension HomeAssistantSession {
  func authenticatedWebSocketAccess() async throws -> HomeAssistantWebSocketAccess {
    guard let access = try await authenticatedWebSocketAccesses().first else {
      throw HomeAssistantAPIError.invalidServerURL
    }
    return access
  }
}
