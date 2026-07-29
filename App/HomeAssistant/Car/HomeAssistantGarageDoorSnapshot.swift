import Foundation

struct HomeAssistantGarageDoorSnapshot: Equatable, Identifiable, Sendable {
  enum DoorState: Equatable, Sendable {
    case open
    case opening
    case closing
    case closed
    case partlyOpen
    case unavailable

    var isMoving: Bool {
      self == .opening || self == .closing
    }
  }

  enum LightState: Equatable, Sendable {
    case illuminated
    case off
    case unavailable
  }

  enum LockState: Equatable, Sendable {
    case locked
    case locking
    case unlocking
    case unlocked
    case unavailable
  }

  let id: String
  let name: String
  let doorState: DoorState
  let lightState: LightState
  let lockState: LockState
  let lightEntityID: String?
  let lockEntityID: String?
  let supportsStop: Bool

  init(
    id: String,
    name: String,
    doorState: DoorState,
    lightState: LightState,
    lockState: LockState,
    lightEntityID: String? = nil,
    lockEntityID: String? = nil,
    supportsStop: Bool = false
  ) {
    self.id = id
    self.name = name
    self.doorState = doorState
    self.lightState = lightState
    self.lockState = lockState
    self.lightEntityID = lightEntityID
    self.lockEntityID = lockEntityID
    self.supportsStop = supportsStop
  }

  static func snapshots(
    states: [HomeAssistantState],
    registry: HomeAssistantGarageDoorRegistry
  ) -> [Self] {
    let statesByID = Dictionary(uniqueKeysWithValues: states.map { ($0.entityID, $0) })
    let entityIDsByDeviceID = Dictionary(
      grouping: registry.deviceIDByEntityID.keys,
      by: { registry.deviceIDByEntityID[$0] ?? "" }
    )

    return states.compactMap { state in
      guard
        state.entityID.hasPrefix("cover."),
        state.deviceClass == "garage"
      else {
        return nil
      }
      let deviceID = registry.deviceIDByEntityID[state.entityID]
      let companionIDs = deviceID.flatMap { entityIDsByDeviceID[$0] } ?? []
      let light = uniqueCompanion(
        prefix: "light.",
        entityIDs: companionIDs,
        statesByID: statesByID
      )
      let lock = uniqueCompanion(
        prefix: "lock.",
        entityIDs: companionIDs,
        statesByID: statesByID
      )
      return Self(
        id: state.entityID,
        name: deviceID.flatMap { registry.deviceNameByID[$0] }
          ?? state.friendlyName
          ?? fallbackName(for: state.entityID),
        doorState: doorState(
          from: state.state,
          currentPosition: state.currentPosition
        ),
        lightState: lightState(from: light?.state),
        lockState: lockState(from: lock?.state),
        lightEntityID: light?.entityID,
        lockEntityID: lock?.entityID,
        supportsStop: state.supportedFeatures & 8 != 0
      )
    }.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  private static func uniqueCompanion(
    prefix: String,
    entityIDs: [String],
    statesByID: [String: HomeAssistantState]
  ) -> HomeAssistantState? {
    let candidates = entityIDs.compactMap { entityID in
      entityID.hasPrefix(prefix) ? statesByID[entityID] : nil
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func doorState(
    from state: String,
    currentPosition: Double?
  ) -> DoorState {
    switch state {
    case "open":
      if let currentPosition, currentPosition > 0, currentPosition < 100 {
        .partlyOpen
      } else {
        .open
      }
    case "opening": .opening
    case "closing": .closing
    case "closed": .closed
    default: .unavailable
    }
  }

  func replacing(lightState: LightState) -> Self {
    Self(
      id: id,
      name: name,
      doorState: doorState,
      lightState: lightState,
      lockState: lockState,
      lightEntityID: lightEntityID,
      lockEntityID: lockEntityID,
      supportsStop: supportsStop
    )
  }

  func replacing(lockState: LockState) -> Self {
    Self(
      id: id,
      name: name,
      doorState: doorState,
      lightState: lightState,
      lockState: lockState,
      lightEntityID: lightEntityID,
      lockEntityID: lockEntityID,
      supportsStop: supportsStop
    )
  }

  private static func lightState(from state: String?) -> LightState {
    switch state {
    case "on": .illuminated
    case "off": .off
    default: .unavailable
    }
  }

  private static func lockState(from state: String?) -> LockState {
    switch state {
    case "locked": .locked
    case "locking": .locking
    case "unlocking": .unlocking
    case "unlocked": .unlocked
    default: .unavailable
    }
  }

  private static func fallbackName(for entityID: String) -> String {
    let objectID = entityID.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityID
    return objectID.replacingOccurrences(of: "_", with: " ").localizedCapitalized
  }
}
