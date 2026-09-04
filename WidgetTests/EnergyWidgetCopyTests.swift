import XCTest

final class EnergyWidgetCopyTests: XCTestCase {
  func testRollingTotalLabelsDescribeTwentyFourHours() {
    let bundle = Bundle(for: EnergyWidgetCopyTests.self)
    let standard = EnergyWidgetCopy(isFullBruce: false, bundle: bundle)
    let fullBruce = EnergyWidgetCopy(isFullBruce: true, bundle: bundle)

    XCTAssertEqual(standard.costLast24Hours, "24h cost")
    XCTAssertEqual(standard.earningsLast24Hours, "24h earnings")
    XCTAssertEqual(fullBruce.costLast24Hours, "24h wallet")
    XCTAssertEqual(fullBruce.earningsLast24Hours, "24h payday")
  }
}
