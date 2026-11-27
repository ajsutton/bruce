import Foundation

final class DemoCharger: HomeAssistantEVCharging {
  private let state = DemoValue(
    HomeAssistantEVChargingSnapshot(
      mode: .smart, activity: .charging(powerWatts: 3600), modeLastUpdated: .now
    ))

  var providesContinuousUpdates: Bool { true }

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { [state] continuation in
      let id = state.observe { continuation.yield(.live($0)) }
      continuation.onTermination = { [weak state] _ in state?.removeObserver(id) }
    }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode { state.value.mode }
  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot { state.value }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    try Task.checkCancellation()
    state.update {
      $0 = HomeAssistantEVChargingSnapshot(
        mode: mode,
        activity: mode == .off ? .switchedOff : .charging(powerWatts: 3600),
        modeLastUpdated: .now
      )
    }
    return mode
  }
}
