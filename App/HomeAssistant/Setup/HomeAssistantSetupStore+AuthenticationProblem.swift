extension HomeAssistantSetupStore {
  enum AuthenticationProblem: Equatable {
    case rejected
    case inactiveUser
    case browserUnavailable
    case browserSessionEnded
    case unavailable
    case invalidCallback
    case verificationFailed
    case couldNotSave
    case other
  }
}
