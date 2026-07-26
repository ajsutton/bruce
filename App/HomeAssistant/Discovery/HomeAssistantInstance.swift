import Foundation

struct HomeAssistantInstance: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let version: String?
  let internalURL: URL?
  let externalURL: URL?
  let isOnboarding: Bool

  var candidateURLs: [URL] {
    [internalURL, externalURL]
      .compactMap(\.self)
      .reduce(into: []) { result, url in
        if !result.contains(url) {
          result.append(url)
        }
      }
  }

  var eligibleExternalURL: URL? {
    guard externalURL?.scheme?.lowercased() == "https" else {
      return nil
    }
    return externalURL
  }
}
