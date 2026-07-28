import Foundation

struct BruceCopy {
  struct Entry {
    let key: String.LocalizationValue

    static func localized(_ key: String.LocalizationValue) -> Self {
      Self(key: key)
    }
  }

  let mode: BruceMode

  func text(_ entry: Entry) -> String {
    String(
      localized: entry.key,
      table: "Localizable",
      bundle: mode.copyBundle,
      locale: mode.copyLocale
    )
  }
}

extension BruceMode {
  fileprivate var copyBundle: Bundle {
    guard
      let path = Bundle.main.path(
        forResource: copyLocalization,
        ofType: "lproj"
      ),
      let bundle = Bundle(path: path)
    else {
      return .main
    }
    return bundle
  }

  fileprivate var copyLocale: Locale {
    Locale(identifier: copyLocalization)
  }

  private var copyLocalization: String {
    switch self {
    case .standard:
      "en"
    case .full:
      "en-AU"
    }
  }
}
