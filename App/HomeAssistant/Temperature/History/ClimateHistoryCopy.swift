struct ClimateHistoryCopy {
  let mode: BruceMode
  private var copy: BruceCopy { BruceCopy(mode: mode) }
  var title: String { copy.text(.localized("climateHistory.title")) }
  var actual: String { copy.text(.localized("climateHistory.actual")) }
  var target: String { copy.text(.localized("climateHistory.target")) }
  var opening: String { copy.text(.localized("climateHistory.opening")) }
  var period: String { copy.text(.localized("climateHistory.period")) }
  var expand: String { copy.text(.localized("climateHistory.expand")) }
  var done: String { copy.text(.localized("climateHistory.done")) }
  var loading: String { copy.text(.localized("climateHistory.loading")) }
  var unavailable: String { copy.text(.localized("climateHistory.unavailable")) }
  var failed: String { copy.text(.localized("climateHistory.failed")) }
  var retry: String { copy.text(.localized("climateHistory.retry")) }
  var time: String { copy.text(.localized("climateHistory.time")) }
  var temperature: String { copy.text(.localized("climateHistory.temperature")) }
  var lastKnown: String { TemperatureCopy(mode: mode).lastKnown }

  func activity(_ value: ClimateHistoryValue.Activity) -> String {
    switch value {
    case .active: copy.text(.localized("climateHistory.on"))
    case .off: copy.text(.localized("climateHistory.off"))
    case .unknown: TemperatureCopy(mode: mode).unavailable
    }
  }
}
