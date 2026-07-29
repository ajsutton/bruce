struct HomeAssistantConnectionBanner: Equatable {
  enum Problem: Equatable {
    case presentation(HomeAssistantPresentation.ConnectionProblem)
    case signInRequired
    case needsAttention
    case unavailable
    case reconnecting
  }

  enum Action: Equatable {
    case manageConnection
    case refresh
    case none
  }

  let problem: Problem

  init(problem: Problem) {
    self.problem = problem
  }

  var action: Action {
    switch problem {
    case .presentation, .signInRequired, .needsAttention:
      .manageConnection
    case .unavailable:
      .refresh
    case .reconnecting:
      .none
    }
  }

  init?(
    presentationProblem: HomeAssistantPresentation.ConnectionProblem?,
    serverStatus: HomeAssistantServerStatus
  ) {
    if let presentationProblem {
      problem = .presentation(presentationProblem)
      return
    }

    switch serverStatus.phase {
    case .signInRequired:
      problem = .signInRequired
    case .needsAttention:
      problem = .needsAttention
    case .unavailable:
      problem = .unavailable
    case .reconnecting:
      problem = .reconnecting
    case .idle, .updating, .live:
      return nil
    }
  }
}

extension HomeAssistantTemperatureStore.Problem {
  var isFeatureSpecific: Bool {
    switch self {
    case .connectionUnavailable, .reconnecting, .signInRequired, .invalidResponse, .other:
      false
    }
  }
}

extension HomeAssistantEVChargingStore.Problem {
  var isFeatureSpecific: Bool {
    switch self {
    case .updateFailed, .updateTimedOut:
      true
    case .connectionNeedsManagement, .connectionUnavailable, .reconnecting, .signInRequired,
      .invalidResponse:
      false
    }
  }
}

extension HomeAssistantGarageDoorStore.Problem {
  var isFeatureSpecific: Bool {
    switch self {
    case .updateFailed:
      true
    case .connectionNeedsManagement, .connectionUnavailable, .reconnecting, .signInRequired,
      .invalidResponse:
      false
    }
  }
}

extension HomeAssistantHomeEnergyStore.Problem {
  var isFeatureSpecific: Bool {
    switch self {
    case .connectionNeedsManagement, .connectionUnavailable, .reconnecting, .signInRequired,
      .invalidResponse:
      false
    }
  }
}
