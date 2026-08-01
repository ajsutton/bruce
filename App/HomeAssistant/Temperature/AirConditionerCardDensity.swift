import Foundation

enum AirConditionerCardDensity {
  case spacious
  case condensed

  var spacing: CGFloat {
    self == .spacious ? 12 : 3
  }

  var statusMinimumWidth: CGFloat {
    self == .spacious ? 180 : 132
  }

  var statusMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 132
  }

  var temperatureMinimumWidth: CGFloat {
    self == .spacious ? 96 : 68
  }

  var temperatureMaximumWidth: CGFloat {
    self == .spacious ? 180 : 68
  }

  var minimumHeight: CGFloat {
    self == .spacious ? 76 : 68
  }
}
