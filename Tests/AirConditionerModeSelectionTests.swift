import Combine
import XCTest

@testable import Bruce

@MainActor
final class AirConditionerModeSelectionTests: XCTestCase {
  func testOffAirConditionerDefaultsToCoolingRatherThanFirstAdvertisedMode() async {
    let fixture = await start(reading: reading())
    XCTAssertEqual(fixture.store.selectedClimateMode(for: fixture.reading), .cooling)
    await finish(fixture)
  }

  func testSelectingModeWhileOffLeavesPowerOffAndSendsNoCommand() async {
    let fixture = await start(reading: reading())
    await fixture.store.setMode(.heating, for: fixture.reading)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: fixture.reading), .heating)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .off)
    XCTAssertFalse(fixture.store.isControlling(entityID: fixture.reading.id))
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [])
    await finish(fixture)
  }

  func testPowerOnUsesSelectedModeAndPublishesThatModeImmediately() async {
    let fixture = await start(reading: reading())
    XCTAssertTrue(fixture.store.selectClimateModeIfOff(.heating, for: fixture.reading))
    XCTAssertEqual(fixture.store.selectedClimateMode(for: fixture.reading), .heating)
    await fixture.store.setPower(for: fixture.reading, isOn: true)
    XCTAssertEqual(fixture.store.readings.first?.operatingMode, .heating)
    XCTAssertEqual(fixture.store.readings.first?.powerState, .poweredOn)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: fixture.reading.id, mode: .heating)])
    await finish(fixture)
  }

  func testPowerOnWithoutRememberedModeExplicitlyRequestsCooling() async {
    let fixture = await start(reading: reading())
    await fixture.store.setPower(for: fixture.reading, isOn: true)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: fixture.reading.id, mode: .cooling)])
    await finish(fixture)
  }

  func testLiveModeIsRememberedAfterAnExternalPowerOff() async {
    let active = reading(mode: .heating)
    let fixture = await start(reading: active)
    let off = active.replacingClimateState(powerState: .off, operatingMode: .off)
    await publish(.live([off]), in: fixture)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: off), .heating)
    await fixture.store.setPower(for: off, isOn: true)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: off.id, mode: .heating)])
    await finish(fixture)
  }

  func testCachedModeCannotReplaceLastConfirmedMode() async {
    let fixture = await start(reading: reading(mode: .heating))
    let cached = reading(mode: .cooling)
    await publish(.reconnecting([cached]), in: fixture)
    XCTAssertEqual(fixture.store.rememberedClimateModes[fixture.reading.id], .heating)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [])
    await finish(fixture)
  }

  func testUnavailableOrRemovedRememberedModeFallsBackToSupportedCooling() async {
    let fixture = await start(reading: reading(mode: .heating))
    let off = reading(modes: [.automatic, .cooling])
    await publish(.live([off]), in: fixture)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: off), .cooling)
    await fixture.store.setPower(for: off, isOn: true)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: off.id, mode: .cooling)])
    await finish(fixture)
  }

  func testMissingCoolingFallsBackToAnAdvertisedMode() async {
    let fixture = await start(reading: reading(modes: [.heating]))
    await fixture.store.setPower(for: fixture.reading, isOn: true)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: fixture.reading.id, mode: .heating)])
    await finish(fixture)
  }

  func testSelectingModeWhileDisconnectedDoesNotChangeSelection() async {
    let fixture = await start(reading: reading())
    await publish(.reconnecting([reading()]), in: fixture)
    await fixture.store.setMode(.heating, for: fixture.reading)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: fixture.reading), .cooling)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [])
    await finish(fixture)
  }

  func testSelectingModeUsesLatestCapabilitiesRatherThanStaleCallback() async {
    let fixture = await start(reading: reading())
    let latest = reading(modes: [.cooling])
    await publish(.live([latest]), in: fixture)
    await fixture.store.setMode(.heating, for: fixture.reading)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: latest), .cooling)
    let commands = await fixture.controller.commands
    XCTAssertEqual(commands, [])
    await finish(fixture)
  }

  func testFailedModeChangeRollsBackWithoutRememberingUnconfirmedMode() async {
    let controller = OrderedClimateController(commandCount: 1)
    let active = reading(mode: .cooling)
    let fixture = await start(reading: active, controller: controller)
    let command = Task { await fixture.store.setMode(.heating, for: active) }
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    XCTAssertEqual(fixture.store.readings.first?.operatingMode, .heating)
    XCTAssertEqual(fixture.store.rememberedClimateModes[active.id], .cooling)
    controller.fail(command: 0)
    await command.value
    XCTAssertEqual(fixture.store.readings.first?.operatingMode, .cooling)
    XCTAssertEqual(fixture.store.rememberedClimateModes[active.id], .cooling)
    XCTAssertNotNil(fixture.store.controlProblem)
    await finish(fixture)
  }

  func testFailedPowerOnKeepsOffStateAndSelectedModeForRetry() async {
    let controller = OrderedClimateController(commandCount: 1)
    let fixture = await start(reading: reading(), controller: controller)
    await fixture.store.setMode(.heating, for: fixture.reading)
    let command = Task { await fixture.store.setPower(for: fixture.reading, isOn: true) }
    await fulfillment(of: [controller.started(at: 0)], timeout: 1)
    controller.fail(command: 0)
    await command.value
    XCTAssertEqual(fixture.store.readings.first?.powerState, .off)
    XCTAssertEqual(fixture.store.selectedClimateMode(for: fixture.reading), .heating)
    XCTAssertNotNil(fixture.store.controlProblem)
    await finish(fixture)
  }

  func testOffSelectionSurvivesStoreRecreationAndSignOutWithoutCrossingServers() async throws {
    let name = "AirConditionerModeSelectionTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let original = await start(reading: reading(), defaults: defaults, serverID: "home")
    await original.store.setMode(.heating, for: original.reading)
    await finish(original)

    let otherHome = await start(reading: reading(), defaults: defaults, serverID: "holiday")
    XCTAssertEqual(otherHome.store.selectedClimateMode(for: otherHome.reading), .cooling)
    await finish(otherHome)

    let restored = await start(reading: reading(), defaults: defaults, serverID: "home")
    XCTAssertEqual(restored.store.selectedClimateMode(for: restored.reading), .heating)
    await restored.store.setPower(for: restored.reading, isOn: true)
    let commands = await restored.controller.commands
    XCTAssertEqual(commands, [.mode(entityID: restored.reading.id, mode: .heating)])
    await finish(restored)
  }

  func testConfirmedModeSurvivesStoreRecreationWhileTheAirConditionerIsOff() async throws {
    let name = "AirConditionerModeSelectionTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let original = await start(
      reading: reading(mode: .heating), defaults: defaults, serverID: "home")
    await finish(original)
    let restored = await start(reading: reading(), defaults: defaults, serverID: "home")
    XCTAssertEqual(restored.store.selectedClimateMode(for: restored.reading), .heating)
    await finish(restored)
  }

}

extension AirConditionerModeSelectionTests {
  private struct Fixture {
    let store: HomeAssistantTemperatureStore
    let reading: HomeAssistantTemperatureReading
    let loader: ControlledTemperatureLoader
    let controller: RecordingClimateController
    let load: Task<Void, Never>
  }

  private func start(
    reading: HomeAssistantTemperatureReading,
    controller: (any HomeAssistantClimateControlling)? = nil,
    defaults: UserDefaults? = nil, serverID: String? = nil
  ) async -> Fixture {
    let loader = ControlledTemperatureLoader(requestCount: 1)
    let recording = RecordingClimateController()
    let store = HomeAssistantTemperatureStore(
      loader: loader, controller: controller ?? recording, modeDefaults: defaults
    )
    let load = Task {
      if let serverID {
        await store.synchronize(with: .ready(credentials(serverID: serverID)))
      } else {
        await store.load()
      }
    }
    await fulfillment(of: [loader.started(at: 0)], timeout: 1)
    let live = expectation(description: "Live climate state")
    let subscription = store.$isLive.filter { $0 }.prefix(1).sink { _ in live.fulfill() }
    loader.yieldRequest(0, update: .live([reading]))
    await fulfillment(of: [live], timeout: 1)
    withExtendedLifetime(subscription) {}
    return Fixture(
      store: store, reading: reading, loader: loader, controller: recording, load: load)
  }

  private func publish(_ update: HomeAssistantTemperatureUpdate, in fixture: Fixture) async {
    let received = expectation(description: "Climate update")
    let updates: AnyPublisher<Void, Never> =
      fixture.store.readings == update.readings
      ? fixture.store.$isLive.dropFirst().map { _ in () }.eraseToAnyPublisher()
      : fixture.store.$readings.dropFirst().map { _ in () }.eraseToAnyPublisher()
    let subscription = updates.prefix(1).sink { received.fulfill() }
    fixture.loader.yieldRequest(0, update: update)
    await fulfillment(of: [received], timeout: 1)
    withExtendedLifetime(subscription) {}
  }

  private func finish(_ fixture: Fixture) async {
    fixture.store.reset()
    fixture.loader.finishRequest(0)
    await fixture.load.value
  }

  private func credentials(serverID: String) -> HomeAssistantCredentials {
    let url = URL(filePath: "/home-assistant")
    return HomeAssistantCredentials(
      instanceID: serverID, instanceName: serverID, internalURL: url,
      externalURL: nil, lastSuccessfulURL: url, accessToken: "test", refreshToken: "test",
      tokenType: "Bearer", accessTokenExpiresAt: .distantFuture, clientID: url
    )
  }

  private func reading(
    mode: HomeAssistantTemperatureReading.OperatingMode = .off,
    modes: [HomeAssistantTemperatureReading.ClimateMode] = [.automatic, .heating, .cooling]
  ) -> HomeAssistantTemperatureReading {
    HomeAssistantTemperatureReading(
      id: "climate.ac_0", name: "Air conditioning", value: 24, targetValue: 22,
      unit: "°C", powerState: mode == .off ? .off : .poweredOn,
      kind: .airConditioner, operatingMode: mode, availableModes: modes
    )
  }
}
