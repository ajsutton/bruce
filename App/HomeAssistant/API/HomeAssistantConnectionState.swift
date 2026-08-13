import Foundation

enum HomeAssistantConnectionState: Equatable, Sendable {
  case stopped
  case waitingForCredentials
  case suspended
  case connecting
  case authenticating
  case synchronizing
  case live
  case backingOff
  case waitingForConnectivity
  case requiresUserAction
}

enum HomeAssistantConnectionTrigger: String, Sendable {
  case consumerIntent
  case credentials
  case appActivity
  case transportClose
  case heartbeat
  case wakeHint
  case pathHint
  case manualRequest
  case authentication
}
