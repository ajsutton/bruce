import SwiftUI

struct BrucePanelSwipeExclusionModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(iOS)
      content.background {
        GeometryReader { geometry in
          Color.clear.preference(
            key: BrucePanelSwipeExclusionPreferenceKey.self,
            value: [geometry.frame(in: .global)]
          )
        }
      }
    #else
      content
    #endif
  }
}
