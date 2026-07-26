import XCTest

@testable import Bruce

final class HomeAssistantHTTPDataLoaderTests: XCTestCase {
  func testProductionSessionWaitsForConnectivity() {
    let configuration = URLSessionHomeAssistantHTTPDataLoader.makeConfiguration()

    XCTAssertTrue(configuration.waitsForConnectivity)
    XCTAssertEqual(configuration.timeoutIntervalForResource, 60)
  }
}
