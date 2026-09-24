import Foundation

struct ClimateHistoryZone: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let damperID: String

  static let systemID = "climate.ac_0"
  // The AirTouch installation represented by the climate page and diagnostics dashboard.
  static let all: [Self] = [
    Self(id: "climate.lounge", name: "Lounge", damperID: "cover.lounge_damper"),
    Self(id: "climate.dining", name: "Dining", damperID: "cover.dining_damper"),
    Self(id: "climate.retreat", name: "Retreat", damperID: "cover.retreat_damper"),
    Self(id: "climate.ella", name: "Ella", damperID: "cover.ella_damper"),
    Self(id: "climate.office_spare", name: "Office / Spare", damperID: "cover.office_spare_damper"),
    Self(id: "climate.master_bed", name: "Master Bed", damperID: "cover.master_bed_damper"),
  ]

  static var entityIDs: [String] {
    [systemID] + all.flatMap { [$0.id, $0.damperID] }
  }
}
