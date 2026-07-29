extension HomeAssistantEVChargingSnapshot {
  enum ModeEntityDiscovery {
    case absent
    case found(HomeAssistantState)
    case ambiguous
  }

  init(states: [HomeAssistantState]) throws {
    guard
      let modeEntity = Self.modeEntity(in: states),
      let mode = HomeAssistantEVChargingMode(rawValue: modeEntity.state),
      let modeLastUpdated = modeEntity.lastUpdated
    else {
      throw HomeAssistantAPIError.invalidResponse
    }

    self.init(
      mode: mode,
      activity: Self.activity(
        mode: mode,
        sourceState: Self.sourceState(in: states)
      ),
      modeLastUpdated: modeLastUpdated
    )
  }

  static func modeEntity(in states: [HomeAssistantState]) -> HomeAssistantState? {
    guard case .found(let entity) = modeEntityDiscovery(in: states) else {
      return nil
    }
    return entity
  }

  static func modeEntityDiscovery(
    in states: [HomeAssistantState]
  ) -> ModeEntityDiscovery {
    let expectedOptions = Set(HomeAssistantEVChargingMode.allCases.map(\.rawValue))
    let candidates = states.filter {
      $0.entityID.hasPrefix("input_select.")
        && Set($0.options) == expectedOptions
        && matches($0, terms: ["charging"])
        && matchesAny($0, terms: ["ev", "car"])
    }
    switch candidates.count {
    case 0: return .absent
    case 1: return .found(candidates[0])
    default: return .ambiguous
    }
  }

  private static func sourceState(
    in states: [HomeAssistantState]
  ) -> EVChargingSourceState {
    let plugStates = [
      "Charging",
      "EV Connected",
      "EV Disconnected",
      "Waiting for EV",
    ]
    let plugCandidates = states.filter {
      $0.entityID.hasPrefix("sensor.") && plugStates.contains($0.state)
        && matches($0, terms: ["plug", "status"])
    }
    let plugEntity = plugCandidates.count == 1 ? plugCandidates[0] : nil
    let chargerState = plugEntity.flatMap {
      pairedChargerStatus(in: states, plugEntity: $0)
    }?.state

    return EVChargingSourceState(
      powerWatts: chargingPower(in: states, plugEntity: plugEntity),
      plugState: plugEntity?.state,
      chargerState: chargerState,
      batteryAllowsCharging: uniqueState(in: states) {
        $0.entityID.hasPrefix("input_boolean.")
          && matches($0, terms: ["battery", "allows", "charging"])
      }?.state,
      priceAllowsCharging: uniqueState(in: states) {
        $0.entityID.hasPrefix("input_boolean.")
          && matches($0, terms: ["price", "allows", "charging"])
      }?.state
    )
  }

  private static func pairedChargerStatus(
    in states: [HomeAssistantState],
    plugEntity: HomeAssistantState
  ) -> HomeAssistantState? {
    let suffix = "_plug_status"
    guard plugEntity.entityID.hasSuffix(suffix) else { return nil }
    let stem = plugEntity.entityID.dropLast(suffix.count)
    let expectedEntityID = "\(stem)_status"
    return states.first {
      $0.entityID == expectedEntityID && ["Completed", "Paused"].contains($0.state)
    }
  }

  private static func chargingPower(
    in states: [HomeAssistantState],
    plugEntity: HomeAssistantState?
  ) -> Double? {
    guard let plugEntity else { return nil }
    let powerState = uniqueState(in: states) {
      $0.entityID.hasPrefix("sensor.")
        && $0.deviceClass == "power"
        && matches($0, terms: ["power", "charging"])
        && isRelatedPowerEntity($0, to: plugEntity)
    }
    guard let powerState, let power = Double(powerState.state), power.isFinite else {
      return nil
    }
    return powerState.unitOfMeasurement == "kW" ? power * 1_000 : power
  }

  private static func isRelatedPowerEntity(
    _ powerEntity: HomeAssistantState,
    to plugEntity: HomeAssistantState
  ) -> Bool {
    if plugEntity.entityID.contains("_myenergi_") {
      return powerEntity.entityID == "sensor.home_myenergi_home_power_charging"
    }
    let plugStem = plugEntity.entityID
      .replacingOccurrences(of: "_plug_status", with: "")
    return powerEntity.entityID.hasPrefix("\(plugStem)_")
  }

  private static func uniqueState(
    in states: [HomeAssistantState],
    matching predicate: (HomeAssistantState) -> Bool
  ) -> HomeAssistantState? {
    let candidates = states.filter(predicate)
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func matches(
    _ state: HomeAssistantState,
    terms: [String]
  ) -> Bool {
    let searchable = "\(state.entityID) \(state.friendlyName ?? "")".lowercased()
    return terms.allSatisfy(searchable.contains)
  }

  private static func matchesAny(
    _ state: HomeAssistantState,
    terms: [String]
  ) -> Bool {
    let searchable = "\(state.entityID) \(state.friendlyName ?? "")".lowercased()
    return terms.contains(where: searchable.contains)
  }

  private static func activity(
    mode: HomeAssistantEVChargingMode,
    sourceState: EVChargingSourceState
  ) -> HomeAssistantEVChargingActivity {
    if let powerWatts = sourceState.powerWatts, powerWatts.isFinite, powerWatts > 50 {
      return .charging(powerWatts: powerWatts)
    }
    if sourceState.plugState == "EV Disconnected" {
      return .notPluggedIn
    }
    if sourceState.plugState == "Charging" {
      return .charging(powerWatts: nil)
    }
    if mode == .off {
      return .switchedOff
    }
    if sourceState.chargerState == "Completed" {
      return .complete
    }
    if sourceState.priceAllowsCharging == "off" {
      return .paused(reason: .electricityPrice)
    }
    if mode == .smart, sourceState.batteryAllowsCharging == "off" {
      return .paused(reason: .homeBattery)
    }
    if sourceState.plugState == "Waiting for EV" {
      return .waitingForVehicle
    }
    if sourceState.chargerState == "Paused" {
      return .paused(reason: nil)
    }
    if sourceState.plugState == "EV Connected" {
      return .connected
    }
    return .unavailable
  }
}

private struct EVChargingSourceState {
  let powerWatts: Double?
  let plugState: String?
  let chargerState: String?
  let batteryAllowsCharging: String?
  let priceAllowsCharging: String?
}
