import Foundation

enum HomeAssistantWebAuthenticationError: Error, Equatable, LocalizedError {
  case presentationFailed(String)
  case sessionEnded(String)

  var errorDescription: String? {
    switch self {
    case .presentationFailed(let diagnostic), .sessionEnded(let diagnostic):
      diagnostic
    }
  }
}
