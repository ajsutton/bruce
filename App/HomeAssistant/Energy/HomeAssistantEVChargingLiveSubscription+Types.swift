extension HomeAssistantEVChargingLiveSubscription {
  enum Event {
    case progress
    case update(HomeAssistantEVChargingUpdate)
    case finished
    case failed(any Error)
  }

  struct Presentation {
    let mode: HomeAssistantEVChargingMode?
    let activity: HomeAssistantEVChargingActivity
    let decision: HomeAssistantEVChargingDecision
    let isLive: Bool
    let isActivityLive: Bool
    let isDecisionLive: Bool
    let isRefreshing: Bool
    let problem: HomeAssistantEVChargingStore.Problem?
    let finishesProgress: Bool
  }

  struct ModeConfirmation {
    let mode: HomeAssistantEVChargingMode
    let decision: HomeAssistantEVChargingDecision
    let isLive: Bool
    let isActivityLive: Bool
    let isDecisionLive: Bool
  }

  struct CurrentPresentation {
    let mode: HomeAssistantEVChargingMode?
    let activity: HomeAssistantEVChargingActivity
    let decision: HomeAssistantEVChargingDecision
    let isLive: Bool
    let isActivityLive: Bool
    let isDecisionLive: Bool
  }
}
