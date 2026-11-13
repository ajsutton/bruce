enum OpenClawVoiceError: Error {
  case signInRequired
  case protocolFailure
  case unavailable
  case microphoneDenied
  case disconnected
  case gateway(String)
}
