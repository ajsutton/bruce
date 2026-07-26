import XCTest

@testable import Bruce

final class HomeAssistantServerAddressTests: XCTestCase {
  func testMissingSchemeDefaultsToHTTPSAndTrailingSlashIsRemoved() throws {
    let address = try HomeAssistantServerAddress(" home.example.com/ ")

    XCTAssertEqual(address.url, URL(string: "https://home.example.com"))
    XCTAssertFalse(address.usesUnencryptedHTTP)
  }

  func testHTTPIsAcceptedAndMarkedUnencrypted() throws {
    let address = try HomeAssistantServerAddress("http://homeassistant.local:8123")

    XCTAssertEqual(address.url, URL(string: "http://homeassistant.local:8123"))
    XCTAssertTrue(address.usesUnencryptedHTTP)
  }

  func testBaseSubpathIsPreserved() throws {
    let address = try HomeAssistantServerAddress("https://example.com/home-assistant/")

    XCTAssertEqual(address.url, URL(string: "https://example.com/home-assistant"))
  }

  func testInvalidAddressesReturnSpecificErrors() {
    let cases: [(String, HomeAssistantServerAddress.ValidationError)] = [
      ("", .empty),
      ("ftp://example.com", .unsupportedScheme),
      ("https:///missing-host", .missingHost),
      ("https://user:password@example.com", .containsCredentials),
      ("https://example.com?token=secret", .containsQuery),
      ("https://example.com#sign-in", .containsFragment),
      ("https://example.com/api/states", .pointsToEndpoint),
      ("https://example.com/auth/authorize", .pointsToEndpoint),
      ("https://example.com/home-assistant/api/states", .pointsToEndpoint),
      ("https://example.com/home-assistant/%61pi/states", .pointsToEndpoint),
      ("https://example.com/home-assistant/auth/authorize", .pointsToEndpoint),
    ]

    for (input, expectedError) in cases {
      XCTAssertThrowsError(try HomeAssistantServerAddress(input)) { error in
        XCTAssertEqual(error as? HomeAssistantServerAddress.ValidationError, expectedError)
      }
    }
  }
}
