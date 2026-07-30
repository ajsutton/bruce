import SwiftUI

struct BruceAccessibilityIdentifierModifier: ViewModifier {
  let identifier: String?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let identifier {
      content.accessibilityIdentifier(identifier)
    } else {
      content
    }
  }
}
