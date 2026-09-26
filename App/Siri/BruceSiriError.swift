import Foundation

enum BruceSiriError: LocalizedError {
  case unavailable
  case connectionUnavailable
  case signInRequired
  case modeNotConfirmed

  var errorDescription: String? {
    SiriCopy.current.error(self)
  }
}
