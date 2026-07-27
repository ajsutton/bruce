import CoreGraphics

enum TemperatureRowDensity {
  case spacious
  case condensed

  var spacing: CGFloat {
    self == .spacious ? 12 : 6
  }

  var locationMinimumWidth: CGFloat {
    self == .spacious ? 180 : 144
  }

  var locationMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 144
  }

  var temperatureMinimumWidth: CGFloat {
    self == .spacious ? 96 : 68
  }

  var minimumHeight: CGFloat {
    self == .spacious ? 76 : 68
  }
}
