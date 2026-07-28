import CoreGraphics

enum TemperatureRowDensity {
  case spacious
  case condensed

  var spacing: CGFloat {
    self == .spacious ? 12 : 3
  }

  var locationMinimumWidth: CGFloat {
    self == .spacious ? 180 : 144
  }

  func locationMinimumWidth(isCompact: Bool) -> CGFloat {
    #if os(iOS)
      if self == .condensed, isCompact {
        return 132
      }
    #endif
    return locationMinimumWidth
  }

  var locationMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 144
  }

  func locationMaximumWidth(isCompact: Bool) -> CGFloat {
    #if os(iOS)
      if self == .condensed, isCompact {
        return 132
      }
    #endif
    return locationMaximumWidth
  }

  var temperatureMinimumWidth: CGFloat {
    self == .spacious ? 96 : 68
  }

  var temperatureMaximumWidth: CGFloat {
    self == .spacious ? .infinity : 68
  }

  var minimumHeight: CGFloat {
    self == .spacious ? 76 : 68
  }
}
