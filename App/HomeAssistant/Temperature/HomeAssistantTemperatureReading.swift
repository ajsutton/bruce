import Foundation

struct HomeAssistantTemperatureReading: Equatable, Identifiable, Sendable {
  enum ClimateMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case automatic = "auto"
    case cooling = "cool"
    case drying = "dry"
    case fanOnly = "fan_only"
    case heating = "heat"
  }

  enum Kind: Equatable, Sendable {
    case airConditioner
    case zone
    case other
  }

  enum OperatingMode: Equatable, Sendable {
    case automatic
    case cooling
    case drying
    case fanOnly
    case heating
    case off
    case active
    case unavailable
  }

  enum PowerState: Equatable, Sendable {
    case poweredOn
    case off
    case unavailable
  }

  let id: String
  let name: String
  let value: Double
  let targetValue: Double?
  let unit: String?
  let powerState: PowerState
  let kind: Kind
  let operatingMode: OperatingMode
  let availableModes: [ClimateMode]
  let icon: String?
  let minimumTargetValue: Double?
  let maximumTargetValue: Double?
  let targetValueStep: Double?

  init(
    id: String,
    name: String,
    value: Double,
    targetValue: Double?,
    unit: String?,
    powerState: PowerState,
    kind: Kind = .other,
    operatingMode: OperatingMode = .active,
    availableModes: [ClimateMode] = [],
    icon: String? = nil,
    minimumTargetValue: Double? = nil,
    maximumTargetValue: Double? = nil,
    targetValueStep: Double? = nil
  ) {
    self.id = id
    self.name = name
    self.value = value
    self.targetValue = targetValue
    self.unit = unit
    self.powerState = powerState
    self.kind = kind
    self.operatingMode = operatingMode
    self.availableModes = availableModes
    self.icon = icon
    self.minimumTargetValue = minimumTargetValue
    self.maximumTargetValue = maximumTargetValue
    self.targetValueStep = targetValueStep
  }

  func replacingClimateState(
    powerState: PowerState,
    operatingMode: OperatingMode
  ) -> Self {
    Self(
      id: id,
      name: name,
      value: value,
      targetValue: targetValue,
      unit: unit,
      powerState: powerState,
      kind: kind,
      operatingMode: operatingMode,
      availableModes: availableModes,
      icon: icon,
      minimumTargetValue: minimumTargetValue,
      maximumTargetValue: maximumTargetValue,
      targetValueStep: targetValueStep
    )
  }

  func replacingTargetValue(_ targetValue: Double) -> Self {
    Self(
      id: id,
      name: name,
      value: value,
      targetValue: targetValue,
      unit: unit,
      powerState: powerState,
      kind: kind,
      operatingMode: operatingMode,
      availableModes: availableModes,
      icon: icon,
      minimumTargetValue: minimumTargetValue,
      maximumTargetValue: maximumTargetValue,
      targetValueStep: targetValueStep
    )
  }

  var effectiveTargetValueStep: Double {
    guard let targetValueStep, targetValueStep.isFinite, targetValueStep > 0 else {
      return unit == "°F" ? 1 : 0.5
    }
    return targetValueStep
  }

  var targetValueFractionLength: Int {
    for fractionLength in 0...6 {
      let scale = pow(10, Double(fractionLength))
      let scaledStep = effectiveTargetValueStep * scale
      if abs(scaledStep - scaledStep.rounded()) < 0.000_001 {
        return fractionLength
      }
    }
    return 6
  }
}
