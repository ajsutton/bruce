import Foundation

struct HomeAssistantEVChargingSnapshot: Equatable, Sendable {
  let mode: HomeAssistantEVChargingMode
  let activity: HomeAssistantEVChargingActivity
  let modeLastUpdated: Date?

  init(
    mode: HomeAssistantEVChargingMode,
    activity: HomeAssistantEVChargingActivity,
    modeLastUpdated: Date? = nil
  ) {
    self.mode = mode
    self.activity = activity
    self.modeLastUpdated = modeLastUpdated
  }

  func isAtLeastAsNew(as timestamp: Date?) -> Bool {
    guard let timestamp else {
      return true
    }
    guard let modeLastUpdated else {
      return false
    }
    return modeLastUpdated >= timestamp
  }
}
