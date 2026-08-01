import Foundation

enum HomeAssistantTemperaturePresentation {
  static func matches(
    _ current: [HomeAssistantTemperatureReading],
    _ candidate: [HomeAssistantTemperatureReading]
  ) -> Bool {
    guard current.count == candidate.count else { return false }
    let currentSummary = HomeAssistantTemperatureSummary(readings: current)
    let candidateSummary = HomeAssistantTemperatureSummary(readings: candidate)
    guard
      temperaturesAreEquivalent(
        currentSummary.averageRoomTemperature,
        candidateSummary.averageRoomTemperature
      ),
      currentSummary.targetValueFractionLength
        == candidateSummary.targetValueFractionLength
    else {
      return false
    }
    return zip(current, candidate).allSatisfy {
      if $0.kind == .airConditioner {
        return airConditionerReadingIsEquivalent($0, $1)
      }
      return readingIsEquivalent($0, $1)
    }
  }

  static func readingIsEquivalent(
    _ current: HomeAssistantTemperatureReading,
    _ candidate: HomeAssistantTemperatureReading
  ) -> Bool {
    sharedReadingPresentationIsEquivalent(current, candidate)
      && temperaturesAreEquivalent(current.value, candidate.value)
  }

  static func airConditionerReadingIsEquivalent(
    _ current: HomeAssistantTemperatureReading,
    _ candidate: HomeAssistantTemperatureReading
  ) -> Bool {
    sharedReadingPresentationIsEquivalent(current, candidate)
  }

  static func temperaturesAreEquivalent(
    _ current: Double?,
    _ candidate: Double?
  ) -> Bool {
    formattedTemperature(current) == formattedTemperature(candidate)
  }

  private static func formattedTemperature(_ value: Double?) -> String? {
    value?.formatted(.number.precision(.fractionLength(1)))
  }

  private static func sharedReadingPresentationIsEquivalent(
    _ current: HomeAssistantTemperatureReading,
    _ candidate: HomeAssistantTemperatureReading
  ) -> Bool {
    current.id == candidate.id
      && current.name == candidate.name
      && current.targetValue == candidate.targetValue
      && current.unit == candidate.unit
      && current.powerState == candidate.powerState
      && current.kind == candidate.kind
      && current.operatingMode == candidate.operatingMode
      && current.availableModes == candidate.availableModes
      && current.icon == candidate.icon
      && current.minimumTargetValue == candidate.minimumTargetValue
      && current.maximumTargetValue == candidate.maximumTargetValue
      && current.targetValueStep == candidate.targetValueStep
      && current.floor == candidate.floor
      && current.presetLabels == candidate.presetLabels
  }
}
