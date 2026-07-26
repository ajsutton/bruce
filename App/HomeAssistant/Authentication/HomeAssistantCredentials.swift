import Foundation

struct HomeAssistantCredentials: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let instanceID: String?
  let instanceName: String
  let internalURL: URL?
  let externalURL: URL?
  var lastSuccessfulURL: URL
  var accessToken: String
  var refreshToken: String
  let tokenType: String
  var accessTokenExpiresAt: Date
  let clientID: URL

  init(
    instanceID: String?,
    instanceName: String,
    internalURL: URL?,
    externalURL: URL?,
    lastSuccessfulURL: URL,
    accessToken: String,
    refreshToken: String,
    tokenType: String,
    accessTokenExpiresAt: Date,
    clientID: URL
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.instanceID = instanceID
    self.instanceName = instanceName
    self.internalURL = internalURL
    self.externalURL = externalURL
    self.lastSuccessfulURL = lastSuccessfulURL
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.tokenType = tokenType
    self.accessTokenExpiresAt = accessTokenExpiresAt
    self.clientID = clientID
  }
}
