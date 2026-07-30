extension HomeAssistantTemperatureCard: Equatable {
  nonisolated static func == (
    lhs: HomeAssistantTemperatureCard,
    rhs: HomeAssistantTemperatureCard
  ) -> Bool {
    HomeAssistantTemperaturePresentation.readingIsEquivalent(
      lhs.reading,
      rhs.reading
    )
      && lhs.mode == rhs.mode
      && lhs.showsControl == rhs.showsControl
      && lhs.isControlEnabled == rhs.isControlEnabled
      && lhs.isControlling == rhs.isControlling
      && lhs.isTargetControlling == rhs.isTargetControlling
      && lhs.isLastKnown == rhs.isLastKnown
      && lhs.showsTargetControl == rhs.showsTargetControl
      && lhs.targetValueFractionLength == rhs.targetValueFractionLength
  }
}

extension HomeAssistantAirConditionerCard: Equatable {
  nonisolated static func == (
    lhs: HomeAssistantAirConditionerCard,
    rhs: HomeAssistantAirConditionerCard
  ) -> Bool {
    HomeAssistantTemperaturePresentation.airConditionerReadingIsEquivalent(
      lhs.reading,
      rhs.reading
    )
      && HomeAssistantTemperaturePresentation.temperaturesAreEquivalent(
        lhs.averageValue,
        rhs.averageValue
      )
      && lhs.mode == rhs.mode
      && lhs.showsName == rhs.showsName
      && lhs.showsControls == rhs.showsControls
      && lhs.isControlEnabled == rhs.isControlEnabled
      && lhs.isControlling == rhs.isControlling
      && lhs.isLastKnown == rhs.isLastKnown
      && lhs.targetValueFractionLength == rhs.targetValueFractionLength
  }
}
