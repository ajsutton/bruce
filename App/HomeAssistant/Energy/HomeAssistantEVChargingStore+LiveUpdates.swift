extension HomeAssistantEVChargingLiveSubscription.CurrentPresentation {
  @MainActor
  init(store: HomeAssistantEVChargingStore) {
    self.init(
      mode: store.mode,
      activity: store.activity,
      decision: store.decision,
      isLive: store.isLive,
      isActivityLive: store.isActivityLive,
      isDecisionLive: store.isDecisionLive
    )
  }
}

extension HomeAssistantEVChargingStore {
  var canSelectMode: Bool {
    isLive && !isLoading && !isChanging
  }
}
