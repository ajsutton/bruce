import XCTest

@testable import Bruce

@MainActor
final class AirConditionerModePreferencesTests: XCTestCase {
  func testSelectionsSurviveRecreationForTheSameServer() throws {
    let name = "AirConditionerModePreferencesTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var original = AirConditionerModePreferences(defaults: defaults)
    _ = original.selectServer(.instance("home"))
    original.save(["climate.ac_0": .heating, "climate.ac_1": .drying])

    var restored = AirConditionerModePreferences(defaults: defaults)
    XCTAssertEqual(
      restored.selectServer(.instance("home")),
      [
        "climate.ac_0": .heating, "climate.ac_1": .drying,
      ])
  }

  func testDifferentServersCannotShareModeSelectionsForTheSameEntityID() throws {
    let name = "AirConditionerModePreferencesTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var preferences = AirConditionerModePreferences(defaults: defaults)
    _ = preferences.selectServer(.instance("home"))
    preferences.save(["climate.ac_0": .heating])
    XCTAssertEqual(preferences.selectServer(.instance("holiday")), [:])
    preferences.save(["climate.ac_0": .cooling])
    XCTAssertEqual(preferences.selectServer(.instance("home")), ["climate.ac_0": .heating])
    XCTAssertEqual(preferences.selectServer(nil), [:])
    XCTAssertEqual(preferences.selectServer(.instance("home")), ["climate.ac_0": .heating])
  }

  func testEndpointIdentitiesKeepTheirPreferencesSeparateWithoutAnInstanceID() throws {
    let name = "AirConditionerModePreferencesTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let home = try XCTUnwrap(URL(string: "https://home.example"))
    let holiday = try XCTUnwrap(URL(string: "https://holiday.example"))
    var preferences = AirConditionerModePreferences(defaults: defaults)
    _ = preferences.selectServer(.endpoints(internalURL: nil, externalURL: home))
    preferences.save(["climate.ac_0": .fanOnly])
    XCTAssertEqual(
      preferences.selectServer(.endpoints(internalURL: nil, externalURL: holiday)), [:])
    XCTAssertEqual(
      preferences.selectServer(.endpoints(internalURL: nil, externalURL: home)),
      [
        "climate.ac_0": .fanOnly
      ])
  }
}
