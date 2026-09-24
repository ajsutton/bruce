import Foundation

struct ClimateHistoryValue: Equatable, Sendable {
  enum Activity: Equatable, Sendable {
    case active, off, unknown
  }

  let actual: Double?
  let target: Double?
  let opening: Double?
  let activity: Activity

  static let unknown = Self(actual: nil, target: nil, opening: nil, activity: .unknown)

  init(actual: Double?, target: Double?, opening: Double?, activity: Activity) {
    self.actual = actual
    self.target = target
    self.opening = opening
    self.activity = activity
  }

  init(zone: ClimateHistoryZone, states: [String: HomeAssistantState]) {
    let room = states[zone.id]
    let system = states[ClimateHistoryZone.systemID]
    actual =
      room?.isAvailable == true ? room?.currentTemperature.flatMap { $0.isFinite ? $0 : nil } : nil
    target =
      room?.isAvailable == true ? room?.targetTemperature.flatMap { $0.isFinite ? $0 : nil } : nil
    if system?.state == "off" || room?.state == "off" {
      activity = .off
      opening = 0
    } else if system?.isAvailable == true, room?.isAvailable == true {
      activity = .active
      let damper = states[zone.damperID]
      opening =
        damper?.isAvailable == true
        ? damper?.currentPosition.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        : nil
    } else {
      activity = .unknown
      opening = nil
    }
  }

  func hasSemanticChange(from previous: Self) -> Bool {
    activity != previous.activity || (actual == nil) != (previous.actual == nil)
      || (target == nil) != (previous.target == nil)
      || (opening == nil) != (previous.opening == nil)
      || target != previous.target
  }
}
