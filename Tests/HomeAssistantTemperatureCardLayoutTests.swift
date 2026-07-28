#if os(iOS)
  import SwiftUI
  import UIKit
  import XCTest

  @testable import Bruce

  @MainActor
  final class HomeAssistantTemperatureCardLayoutTests: XCTestCase {
    func testRoomCardUsesOneRowAtEveryNonAccessibilityTextSize() {
      for showsTargetControl in [false, true] {
        for dynamicTypeSize in nonAccessibilityTextSizes {
          let height = renderedCardHeight(
            dynamicTypeSize: dynamicTypeSize,
            showsTargetControl: showsTargetControl
          )

          XCTAssertLessThanOrEqual(
            height,
            singleRowMaximumHeight,
            """
            Room card wrapped at \(dynamicTypeSize) with target controls \
            \(showsTargetControl) and a height of \(height) points.
            """
          )
        }
      }
    }

    func testRoomCardMayStackAtAccessibilityTextSizes() {
      for showsTargetControl in [false, true] {
        let height = renderedCardHeight(
          dynamicTypeSize: .accessibility1,
          showsTargetControl: showsTargetControl
        )

        XCTAssertGreaterThan(
          height,
          singleRowMaximumHeight,
          """
          Room card with target controls \(showsTargetControl) did not use its \
          accessibility layout.
          """
        )
      }
    }

    private func renderedCardHeight(
      dynamicTypeSize: DynamicTypeSize,
      showsTargetControl: Bool
    ) -> CGFloat {
      let card = HomeAssistantTemperatureCard(
        reading: room,
        mode: .standard,
        showsControl: true,
        isControlEnabled: true,
        showsTargetControl: showsTargetControl
      )
      .environment(\.dynamicTypeSize, dynamicTypeSize)
      .environment(\.horizontalSizeClass, .compact)

      let host = UIHostingController(rootView: card)
      return host.sizeThatFits(
        in: CGSize(width: iPhoneRoomCardWidth, height: 1_000)
      ).height
    }

    private var room: HomeAssistantTemperatureReading {
      HomeAssistantTemperatureReading(
        id: "climate.master_bedroom",
        name: "Master Bedroom",
        value: 21.8,
        targetValue: 22,
        unit: "°C",
        powerState: .poweredOn,
        kind: .zone,
        operatingMode: .fanOnly,
        icon: "mdi:bed",
        minimumTargetValue: 16,
        maximumTargetValue: 30,
        targetValueStep: 0.5
      )
    }

    private var nonAccessibilityTextSizes: [DynamicTypeSize] {
      [
        .xSmall,
        .small,
        .medium,
        .large,
        .xLarge,
        .xxLarge,
        .xxxLarge,
      ]
    }

    private var iPhoneRoomCardWidth: CGFloat {
      343
    }

    private var singleRowMaximumHeight: CGFloat {
      120
    }
  }
#endif
