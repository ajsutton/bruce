struct HomeAssistantAccessState: Equatable {
  enum Phase {
    case signedOut
    case loading
    case ready
    case requiresUserAction
  }

  static let signedOut = Self(phase: .signedOut)
  static let loading = Self(phase: .loading)
  static let requiresUserAction = Self(phase: .requiresUserAction)

  let phase: Phase
  private let serverIdentity: HomeAssistantServerIdentity?

  var isReady: Bool {
    phase == .ready
  }

  private init(
    phase: Phase,
    serverIdentity: HomeAssistantServerIdentity? = nil
  ) {
    self.phase = phase
    self.serverIdentity = serverIdentity
  }

  static func ready(_ credentials: HomeAssistantCredentials) -> Self {
    Self(
      phase: .ready,
      serverIdentity: HomeAssistantServerIdentity(credentials)
    )
  }
}
