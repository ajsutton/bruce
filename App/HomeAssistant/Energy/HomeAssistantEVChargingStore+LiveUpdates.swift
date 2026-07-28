extension HomeAssistantEVChargingLiveSubscription.CurrentPresentation {
  @MainActor
  init(store: HomeAssistantEVChargingStore) {
    self.init(
      mode: store.mode,
      activity: store.activity,
      isLive: store.isLive,
      isActivityLive: store.isActivityLive
    )
  }
}

extension HomeAssistantEVChargingStore {
  var canSelectMode: Bool {
    isLive && !isLoading && !isChanging
  }
}
