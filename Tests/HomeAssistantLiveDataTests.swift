import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantLiveDataTests: XCTestCase {
  func testSharedStateFeedDrivesChargingAndEveryEnergyValue() async throws {
    let source = ControlledStateSource()
    let states = HomeAssistantStateHub(source: source)
    let charging = HomeAssistantEVChargingStream(
      states: states,
      controller: UnusedEVChargingController()
    )
    let energy = HomeAssistantHomeEnergyStream(
      states: states,
      loader: UnusedHomeEnergyLoader()
    )
    let chargingProbe = AsyncThrowingStreamTestProbe(charging.evChargingUpdates())
    let energyProbe = AsyncThrowingStreamTestProbe(energy.homeEnergyUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try liveStates(power: 0, solar: 8.4)))
    await fulfillment(
      of: [chargingProbe.received(at: 0), energyProbe.received(at: 0)],
      timeout: 1
    )
    let initialChargingSnapshot = try liveChargingSnapshot(
      from: chargingProbe.value(at: 0)
    )
    let initialEnergySnapshot = try liveEnergySnapshot(from: energyProbe.value(at: 0))

    assertSnapshots(
      charging: initialChargingSnapshot,
      mode: .smart,
      activity: .connected,
      energy: initialEnergySnapshot,
      expectedEnergy: energySnapshot(
        solar: 8.4, battery: 76, consumption: 3.1, grid: -2.7, prices: (0.341, 0.127)
      )
    )
    source.yield(.live(try updatedLiveStates()))
    await fulfillment(
      of: [chargingProbe.received(at: 1), energyProbe.received(at: 1)],
      timeout: 1
    )
    let updatedChargingSnapshot = try liveChargingSnapshot(
      from: chargingProbe.value(at: 1)
    )
    let updatedEnergySnapshot = try liveEnergySnapshot(from: energyProbe.value(at: 1))

    assertSnapshots(
      charging: updatedChargingSnapshot,
      mode: .charging,
      activity: .charging(powerWatts: 7_024),
      energy: updatedEnergySnapshot,
      expectedEnergy: energySnapshot(
        solar: 9.1, battery: 68, consumption: 4.6, grid: 1.8, prices: (0.292, 0.143)
      )
    )
    XCTAssertEqual(source.subscriptionCount, 1)
  }

  func testSharedStateFeedStopsAfterItsLastSubscriberCancels() async throws {
    let source = ControlledStateSource()
    let states = HomeAssistantStateHub(source: source)
    let firstReceived = expectation(description: "First subscriber received state")
    let secondReceived = expectation(description: "Second subscriber received state")
    let first = Task {
      var hasReceived = false
      let updates = await states.stateUpdates()
      for try await _ in updates where !hasReceived {
        hasReceived = true
        firstReceived.fulfill()
      }
    }
    let second = Task {
      var hasReceived = false
      let updates = await states.stateUpdates()
      for try await _ in updates where !hasReceived {
        hasReceived = true
        secondReceived.fulfill()
      }
    }
    await fulfillment(of: [source.started], timeout: 1)
    let initialStates = try liveStates(power: 1_000, solar: 8.4)
    source.yield(.live(initialStates))
    await fulfillment(of: [firstReceived, secondReceived], timeout: 1)

    first.cancel()
    _ = try? await first.value
    XCTAssertFalse(source.isCancelled)

    second.cancel()
    _ = try? await second.value
    await fulfillment(of: [source.cancelled], timeout: 1)

    XCTAssertTrue(source.isCancelled)
    XCTAssertEqual(source.subscriptionCount, 1)

    let secondSubscription = source.expectSubscriptionCount(2)
    let laterProbe = AsyncThrowingStreamTestProbe(await states.stateUpdates())
    await fulfillment(of: [secondSubscription], timeout: 1)
    let freshStates = try liveStates(power: 2_000, solar: 9.1)
    source.yield(.live(freshStates))
    await fulfillment(of: [laterProbe.received(at: 0)], timeout: 1)
    let laterUpdate = try laterProbe.value(at: 0)

    XCTAssertEqual(laterUpdate.phase, .live)
    XCTAssertEqual(laterUpdate.states, freshStates)
  }

  func testChargingPublishesReconnectBeforeInitialSnapshot() async throws {
    let source = ControlledStateSource()
    let states = HomeAssistantStateHub(source: source)
    let charging = HomeAssistantEVChargingStream(
      states: states,
      controller: UnusedEVChargingController()
    )
    let probe = AsyncThrowingStreamTestProbe(charging.evChargingUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.reconnecting([]))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let reconnecting = try probe.value(at: 0)
    XCTAssertEqual(reconnecting, .reconnecting(nil))
    source.yield(.live(try liveStates(power: 0, solar: 8.4)))
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let snapshot = try liveChargingSnapshot(from: probe.value(at: 1))

    XCTAssertEqual(snapshot.mode, .smart)
    XCTAssertEqual(snapshot.activity, .connected)
  }

  func testChargingRecoversAfterModeEntityIsTemporarilyUnavailable() async throws {
    let source = ControlledStateSource()
    let charging = HomeAssistantEVChargingStream(
      states: HomeAssistantStateHub(source: source),
      controller: UnusedEVChargingController()
    )
    let probe = AsyncThrowingStreamTestProbe(charging.evChargingUpdates())
    await fulfillment(of: [source.started], timeout: 1)

    source.yield(.live(try liveStates(power: 0, solar: 8.4)))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let initial = try liveChargingSnapshot(from: probe.value(at: 0))
    source.yield(.live(try liveStates(power: 0, solar: 8.4, mode: "unavailable")))
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let unavailableUpdate = try probe.value(at: 1)
    let unavailable = try XCTUnwrap(unavailableUpdate)
    source.yield(.live(try liveStates(power: 7_024, solar: 8.4, mode: "On")))
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let recovered = try liveChargingSnapshot(from: probe.value(at: 2))

    XCTAssertEqual(unavailable, .unavailable(initial))
    XCTAssertEqual(recovered.mode, .charging)
    XCTAssertEqual(recovered.activity, .charging(powerWatts: 7_024))
  }

  func testRefreshRestartsAnActiveSharedSourceInsteadOfReplayingCache() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let firstSubscription = source.expectSubscriptionCount(1)
    let probe = AsyncThrowingStreamTestProbe(await states.stateUpdates())
    await fulfillment(of: [firstSubscription], timeout: 1)
    let cachedStates = try liveStates(power: 1_000, solar: 8.4)
    XCTAssertFalse(cachedStates.isEmpty)
    source.yield(.live(cachedStates))
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)
    let initial = try probe.value(at: 0)
    XCTAssertEqual(initial.phase, .live)
    XCTAssertEqual(initial.states, cachedStates)
    let secondSubscription = source.expectSubscriptionCount(2)
    let refreshedActiveFeed = await states.refresh()
    await fulfillment(of: [probe.received(at: 1)], timeout: 1)
    let refreshing = try probe.value(at: 1)
    await fulfillment(of: [secondSubscription], timeout: 1)

    XCTAssertTrue(refreshedActiveFeed)
    XCTAssertEqual(refreshing.phase, .refreshing)
    XCTAssertEqual(refreshing.states, cachedStates)
    XCTAssertEqual(source.subscriptionCount, 2)
    source.finish(throwing: LiveDataTestError.replacementFailed)
    do {
      await fulfillment(of: [probe.received(at: 2)], timeout: 1)
      _ = try probe.value(at: 2)
      XCTFail("Expected the failed replacement source to terminate the feed.")
    } catch LiveDataTestError.replacementFailed {
    } catch {
      XCTFail("Unexpected refresh error: \(error)")
    }
  }

  func testSupersededSourceCannotTerminateReplacementFeed() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let firstSubscription = source.expectSubscriptionCount(1)
    let probe = AsyncThrowingStreamTestProbe(await states.stateUpdates())
    await fulfillment(of: [firstSubscription], timeout: 1)
    let cachedStates = try liveStates(power: 1_000, solar: 8.4)
    source.yield(.live(cachedStates), subscription: 1)
    await fulfillment(of: [probe.received(at: 0)], timeout: 1)

    let secondSubscription = source.expectSubscriptionCount(2)
    _ = await states.refresh()
    await fulfillment(of: [probe.received(at: 1), secondSubscription], timeout: 1)
    source.finish(
      throwing: LiveDataTestError.replacementFailed,
      subscription: 1
    )
    let freshStates = try liveStates(power: 2_000, solar: 9.1)
    source.yield(.live(freshStates), subscription: 2)
    await fulfillment(of: [probe.received(at: 2)], timeout: 1)
    let update = try probe.value(at: 2)

    XCTAssertEqual(update.phase, .live)
    XCTAssertEqual(update.states, freshStates)
  }

  func testResetStartsFreshSourceBeforeDelayedSubscriberTeardown() async throws {
    let source = ControlledStateSource()
    source.started.assertForOverFulfill = false
    source.cancelled.assertForOverFulfill = false
    let states = HomeAssistantStateHub(source: source)
    let firstSubscription = source.expectSubscriptionCount(1)
    let firstProbe = AsyncThrowingStreamTestProbe(await states.stateUpdates())
    await fulfillment(of: [firstSubscription], timeout: 1)
    let oldStates = try liveStates(power: 1_000, solar: 8.4)
    source.yield(.live(oldStates), subscription: 1)
    await fulfillment(of: [firstProbe.received(at: 0)], timeout: 1)

    await states.reset()
    let secondSubscription = source.expectSubscriptionCount(2)
    let secondProbe = AsyncThrowingStreamTestProbe(await states.stateUpdates())
    await fulfillment(of: [secondSubscription], timeout: 1)
    let newStates = try liveStates(power: 2_000, solar: 9.1)
    source.yield(.live(newStates), subscription: 2)
    await fulfillment(of: [secondProbe.received(at: 0)], timeout: 1)

    XCTAssertEqual(try secondProbe.value(at: 0).states, newStates)
    XCTAssertEqual(source.subscriptionCount, 2)
  }

}

extension HomeAssistantLiveDataTests {
  fileprivate func liveChargingSnapshot(
    from update: HomeAssistantEVChargingUpdate?
  ) throws -> HomeAssistantEVChargingSnapshot {
    switch try XCTUnwrap(update) {
    case .live(let snapshot):
      return snapshot
    case .absent, .refreshing, .reconnecting, .unavailable:
      throw LiveDataTestError.unexpectedUpdate
    }
  }

  fileprivate func liveEnergySnapshot(
    from update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>?
  ) throws -> HomeAssistantHomeEnergySnapshot {
    switch try XCTUnwrap(update) {
    case .live(let snapshot):
      return snapshot
    case .refreshing, .reconnecting:
      throw LiveDataTestError.unexpectedUpdate
    }
  }

  fileprivate func liveStates(
    power: Double,
    solar: Double,
    mode: String = "Smart Charging",
    battery: Double = 76,
    consumption: Double = 3.1,
    grid: Double = -2.7,
    generalPrice: Double = 0.341,
    feedInPrice: Double = 0.127
  ) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {"entity_id":"input_select.ev_charging_mode","state":"\(mode)","attributes":{"options":["Off","Smart Charging","On"]},"last_updated":"2026-07-28T01:02:03Z"},
        {"entity_id":"sensor.home_myenergi_home_power_charging","state":"\(power)","attributes":{"device_class":"power","unit_of_measurement":"W"}},
        {"entity_id":"sensor.zappi_myenergi_zappi_26482259_plug_status","state":"EV Connected","attributes":{}},
        {"entity_id":"sensor.zappi_myenergi_zappi_26482259_status","state":"Ready","attributes":{}},
        {"entity_id":"input_boolean.ev_smart_battery_allows_charging","state":"on","attributes":{}},
        {"entity_id":"input_boolean.ev_price_allows_charging","state":"on","attributes":{}},
        {"entity_id":"sensor.sigen_plant_pv_power","state":"\(solar)","attributes":{}},
        {"entity_id":"sensor.sigen_plant_battery_state_of_charge","state":"\(battery)","attributes":{}},
        {"entity_id":"sensor.sigen_plant_consumed_power","state":"\(consumption)","attributes":{}},
        {"entity_id":"sensor.sigen_plant_grid_active_power","state":"\(grid)","attributes":{}},
        {"entity_id":"sensor.01krmdgkh60wyckeepvgtbbgv3_general_price","state":"\(generalPrice)","attributes":{}},
        {"entity_id":"sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price","state":"\(feedInPrice)","attributes":{}}
      ]
      """.utf8
    )
    return try JSONDecoder().decode([HomeAssistantState].self, from: data)
  }

  fileprivate func updatedLiveStates() throws -> [HomeAssistantState] {
    try liveStates(
      power: 7_024,
      solar: 9.1,
      mode: "On",
      battery: 68,
      consumption: 4.6,
      grid: 1.8,
      generalPrice: 0.292,
      feedInPrice: 0.143
    )
  }

  fileprivate func energySnapshot(
    solar: Double,
    battery: Double,
    consumption: Double,
    grid: Double,
    prices: (general: Double, feedIn: Double)
  ) -> HomeAssistantHomeEnergySnapshot {
    HomeAssistantHomeEnergySnapshot(
      pvPowerKilowatts: solar,
      batteryStateOfCharge: battery,
      homeConsumptionKilowatts: consumption,
      gridPowerKilowatts: grid,
      generalPriceDollarsPerKilowattHour: prices.general,
      feedInPriceDollarsPerKilowattHour: prices.feedIn
    )
  }

  fileprivate func assertSnapshots(
    charging: HomeAssistantEVChargingSnapshot,
    mode: HomeAssistantEVChargingMode,
    activity: HomeAssistantEVChargingActivity,
    energy: HomeAssistantHomeEnergySnapshot,
    expectedEnergy: HomeAssistantHomeEnergySnapshot
  ) {
    XCTAssertEqual(charging.mode, mode)
    XCTAssertEqual(charging.activity, activity)
    XCTAssertEqual(energy, expectedEnergy)
  }
}

private struct UnusedEVChargingController: HomeAssistantEVCharging {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    throw LiveDataTestError.unexpectedRequest
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    throw LiveDataTestError.unexpectedRequest
  }
}

private struct UnusedHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw LiveDataTestError.unexpectedRequest
  }
}

private enum LiveDataTestError: Error {
  case replacementFailed
  case unexpectedRequest
  case unexpectedUpdate
}
