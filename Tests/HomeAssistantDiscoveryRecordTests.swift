import XCTest

@testable import Bruce

final class HomeAssistantDiscoveryRecordTests: XCTestCase {
  func testCompleteRecordPreservesInternalAndExternalURLs() throws {
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "Fallback",
      txt: [
        "uuid": "home-1",
        "location_name": "Beach House",
        "version": "2026.7.2",
        "internal_url": "http://homeassistant.local:8123",
        "external_url": "https://home.example.com",
      ]
    )

    XCTAssertEqual(record.uuid, "home-1")
    XCTAssertEqual(record.locationName, "Beach House")
    XCTAssertEqual(record.version, "2026.7.2")
    XCTAssertEqual(record.internalURL, URL(string: "http://homeassistant.local:8123"))
    XCTAssertEqual(record.externalURL, URL(string: "https://home.example.com"))
  }

  func testMissingOptionalValuesUsesServiceName() throws {
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: ["uuid": "home-1"]
    )

    XCTAssertEqual(record.locationName, "My Home")
    XCTAssertNil(record.version)
    XCTAssertNil(record.internalURL)
    XCTAssertNil(record.externalURL)
  }

  func testResolvedServiceSuppliesMissingInternalURL() throws {
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "external_url": "https://home.example.com",
      ],
      resolvedInternalURL: URL(string: "http://192.168.1.20:8123")
    )

    XCTAssertEqual(record.internalURL, URL(string: "http://192.168.1.20:8123"))
    XCTAssertEqual(record.externalURL, URL(string: "https://home.example.com"))
  }

  func testBaseURLIsOnlyUsedWhenNoCurrentURLIsAdvertised() throws {
    let compatibilityRecord = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "base_url": "http://legacy.local:8123",
      ]
    )
    let externalRecord = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "external_url": "https://home.example.com",
        "base_url": "http://legacy.local:8123",
      ]
    )

    XCTAssertEqual(compatibilityRecord.internalURL, URL(string: "http://legacy.local:8123"))
    XCTAssertNil(externalRecord.internalURL)
  }

  func testLandingPageIsCaseInsensitiveAndPasswordFlagIsIgnored() throws {
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "landingpage": "TRUE",
        "requires_api_password": "true",
      ]
    )

    XCTAssertTrue(record.isOnboarding)
  }

  func testMissingUUIDIsRejectedAndMalformedURLIsDiagnosed() throws {
    XCTAssertThrowsError(
      try HomeAssistantDiscoveryRecord(serviceName: "My Home", txt: [:])
    ) { error in
      XCTAssertEqual(error as? HomeAssistantDiscoveryRecord.ValidationError, .missingUUID)
    }
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: ["uuid": "home-1", "internal_url": "file:///tmp/home"]
    )

    XCTAssertNil(record.internalURL)
    XCTAssertEqual(record.invalidURLFields, ["internal_url"])
  }

  func testURLCredentialsQueriesAndFragmentsAreDiagnosed() throws {
    for value in [
      "https://user@example.com",
      "https://example.com?token=secret",
      "https://example.com#fragment",
    ] {
      let record = try HomeAssistantDiscoveryRecord(
        serviceName: "My Home",
        txt: ["uuid": "home-1", "external_url": value]
      )
      XCTAssertNil(record.externalURL)
      XCTAssertEqual(record.invalidURLFields, ["external_url"])
    }
  }

  func testMalformedOptionalURLDoesNotDiscardValidCandidates() throws {
    let record = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "internal_url": "http://home.local:8123",
        "external_url": "not a URL",
        "base_url": "also not a URL",
      ]
    )

    XCTAssertEqual(record.internalURL, URL(string: "http://home.local:8123"))
    XCTAssertNil(record.externalURL)
    XCTAssertEqual(record.invalidURLFields, ["base_url", "external_url"])
  }

  func testIdenticalCandidatesArePresentedOnceAndHttpExternalIsIneligible() throws {
    let instance = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "internal_url": "http://home.local:8123",
        "external_url": "http://home.local:8123",
      ]
    ).instance

    XCTAssertEqual(instance.candidateURLs, [URL(string: "http://home.local:8123")!])
    XCTAssertNil(instance.eligibleExternalURL)
  }

  func testExternalHTTPSEligibilityIsCaseInsensitive() throws {
    let instance = try HomeAssistantDiscoveryRecord(
      serviceName: "My Home",
      txt: [
        "uuid": "home-1",
        "external_url": "HTTPS://home.example.com",
      ]
    ).instance

    XCTAssertEqual(instance.eligibleExternalURL, URL(string: "https://home.example.com"))
  }
}
