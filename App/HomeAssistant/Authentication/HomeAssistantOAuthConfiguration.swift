import Foundation

struct HomeAssistantOAuthConfiguration: Equatable, Sendable {
  static var release: HomeAssistantOAuthConfiguration {
    guard
      let clientID = URL(string: "https://bruce.symphonious.net/"),
      let redirectURI = URL(string: "https://bruce.symphonious.net/auth/")
    else {
      preconditionFailure("The built-in Home Assistant OAuth URLs must be valid.")
    }
    return HomeAssistantOAuthConfiguration(clientID: clientID, redirectURI: redirectURI)
  }

  let clientID: URL
  let redirectURI: URL
}
