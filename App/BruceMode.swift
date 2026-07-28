import SwiftUI

enum BruceMode: String, CaseIterable {
  case standard
  case full

  static let storageKey = "bruceMode"

  var isFullBruce: Bool {
    self == .full
  }

  var title: String {
    switch self {
    case .standard:
      "Bruce"
    case .full:
      "Bruce!"
    }
  }

  var introduction: String {
    switch self {
    case .standard:
      "A calmer way to run the house."
    case .full:
      "Same house. More Bruce."
    }
  }

  var accentColor: Color {
    switch self {
    case .standard:
      Color(red: 0.84, green: 0.40, blue: 0.28)
    case .full:
      Color(red: 1.00, green: 0.80, blue: 0.09)
    }
  }

  var backgroundColor: Color {
    switch self {
    case .standard:
      Color(red: 0.93, green: 0.89, blue: 0.82)
    case .full:
      Color(red: 0.00, green: 0.34, blue: 0.25)
    }
  }

  func panelBackgroundColor(for colorScheme: ColorScheme) -> Color {
    if isFullBruce || colorScheme == .light {
      return backgroundColor
    }
    return Color(red: 0.13, green: 0.14, blue: 0.13)
  }

  var foregroundColor: Color {
    switch self {
    case .standard:
      Color(red: 0.09, green: 0.24, blue: 0.23)
    case .full:
      Color(red: 1.00, green: 0.80, blue: 0.09)
    }
  }
}
