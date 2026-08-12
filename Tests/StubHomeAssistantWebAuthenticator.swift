import Foundation

@testable import Bruce

@MainActor
final class StubHomeAssistantWebAuthenticator: HomeAssistantWebAuthenticating {
  var error: (any Error)?
  private(set) var authenticationCount = 0

  func authenticate(at url: URL) async throws -> URL {
    authenticationCount += 1
    if let error {
      throw error
    }
    guard
      var components = URLComponents(
        url: HomeAssistantOAuthConfiguration.release.redirectURI,
        resolvingAgainstBaseURL: false
      )
    else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    components.queryItems = [
      URLQueryItem(name: "code", value: "authorization-code"),
      URLQueryItem(name: "state", value: "expected-state"),
    ]
    guard let callback = components.url else {
      throw HomeAssistantAuthenticationError.invalidCallback
    }
    return callback
  }

  func cancel() {}
}
