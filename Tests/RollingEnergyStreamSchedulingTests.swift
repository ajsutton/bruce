import XCTest

@testable import Bruce

final class RollingEnergyStreamSchedulingTests: XCTestCase {
  func testRollingDeadlineRefreshesWithoutAnotherStateUpdate() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingRollingEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let loader = SequencedSchedulingRollingTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: 0.91,
            end: timestamp.addingTimeInterval(10)
          )
        ),
        .success(
          totals(
            importCost: 0.01,
            earnings: 0.02,
            end: timestamp.addingTimeInterval(24 * 60 * 60)
          )
        ),
      ]
    )
    let (source, probe) = makeStream(
      loader: loader,
      clock: clock,
      delay: delay
    )
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(try states()))
    await fulfillment(
      of: [probe.received(at: 1), delay.started(at: 0)],
      timeout: 1
    )

    clock.advance(by: 10)
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    let refreshed = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(refreshed.importCostLast24HoursDollars, 0.01)
    XCTAssertEqual(refreshed.feedInEarningsLast24HoursDollars, 0.02)
    await probe.cancel()
  }

  func testFailedRequestRetriesWithoutAnotherStateUpdate() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingRollingEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let loader = SequencedSchedulingRollingTotalsLoader(
      results: [
        .failure(URLError(.timedOut)),
        .success(
          totals(
            importCost: 0.20,
            earnings: 0.91,
            end: timestamp.addingTimeInterval(24 * 60 * 60)
          )
        ),
      ]
    )
    let (source, probe) = makeStream(
      loader: loader,
      clock: clock,
      delay: delay
    )
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(try states()))
    await fulfillment(
      of: [probe.received(at: 1), delay.started(at: 0)],
      timeout: 1
    )
    let failed = try liveSnapshot(probe.value(at: 1))
    XCTAssertEqual(failed.importCostLast24HoursStatus, .failed)

    clock.advanceToRetry()
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    let recovered = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(recovered.importCostLast24HoursStatus, .current)
    XCTAssertEqual(recovered.importCostLast24HoursDollars, 0.20)
    await probe.cancel()
  }

  func testComplementaryPartialResultsKeepOmittedMetricStaleAndRetrying()
    async throws
  {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingRollingEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let intervalEnd = timestamp.addingTimeInterval(24 * 60 * 60)
    let loader = SequencedSchedulingRollingTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: nil,
            end: intervalEnd
          )
        ),
        .success(
          totals(
            importCost: nil,
            earnings: 0.91,
            end: intervalEnd
          )
        ),
      ]
    )
    let (source, probe) = makeStream(
      loader: loader,
      clock: clock,
      delay: delay
    )
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(try states()))
    await fulfillment(
      of: [probe.received(at: 1), delay.started(at: 0)],
      timeout: 1
    )
    let partial = try liveSnapshot(probe.value(at: 1))
    assertInitialPartialTotals(partial)

    clock.advanceToRetry()
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    let complete = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(loader.requestCount, 2)
    assertComplementaryPartialTotals(complete)
    assertSecondPartialRetryDeadline(clock.deadline(at: 1), startingAt: timestamp)
    await probe.cancel()
  }

  private func makeStream(
    loader: SequencedSchedulingRollingTotalsLoader,
    clock: SchedulingRollingEnergyClock,
    delay: ControlledHomeEnergyDelay
  ) -> (
    ControlledStateSource,
    AsyncThrowingStreamTestProbe<
      HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>
    >
  ) {
    let source = ControlledStateSource()
    let stream = HomeAssistantHomeEnergyStream(
      states: HomeAssistantStateHub(source: source),
      loader: SchedulingUnusedHomeEnergyLoader(),
      rollingTotalsLoader: loader,
      now: { clock.now },
      rollingRefreshSleep: { deadline in
        clock.record(deadline: deadline)
        try await delay.sleep(.zero)
      }
    )
    return (source, AsyncThrowingStreamTestProbe(stream.homeEnergyUpdates()))
  }

  private func states() throws -> [HomeAssistantState] {
    try JSONDecoder().decode(
      [HomeAssistantState].self,
      from: Data(
        """
        [
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.pvPowerEntityID)",
            "state":"8.4",
            "attributes":{}
          }
        ]
        """.utf8
      )
    )
  }

  private func totals(
    importCost: Double?,
    earnings: Double?,
    end: Date
  ) -> HomeAssistantRollingEnergyTotals {
    HomeAssistantRollingEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      refreshAfter: end
    )
  }

  private func liveSnapshot(
    _ update: HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>?
  ) throws -> HomeAssistantHomeEnergySnapshot {
    guard case .live(let snapshot) = try XCTUnwrap(update) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    return snapshot
  }
}

extension RollingEnergyStreamSchedulingTests {
  func testRepeatedFailuresDoNotIncreaseNormalRefreshCadence() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingRollingEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 3)
    let loader = SequencedSchedulingRollingTotalsLoader(
      results: [
        .failure(URLError(.timedOut)),
        .failure(URLError(.timedOut)),
        .failure(URLError(.timedOut)),
      ]
    )
    let (source, probe) = makeStream(loader: loader, clock: clock, delay: delay)
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(try states()))
    await fulfillment(
      of: [probe.received(at: 1), delay.started(at: 0)],
      timeout: 1
    )

    clock.advanceToRetry()
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    clock.advanceToRetry()
    delay.finish(1)
    await fulfillment(
      of: [probe.received(at: 5), delay.started(at: 2)],
      timeout: 1
    )

    XCTAssertEqual(loader.requestCount, 3)
    XCTAssertEqual(
      clock.deadline(at: 0),
      timestamp.addingTimeInterval(HomeAssistantRollingEnergyRefreshState.failureRetryInterval)
    )
    XCTAssertEqual(
      clock.deadline(at: 1),
      timestamp.addingTimeInterval(2 * HomeAssistantRollingEnergyRefreshState.failureRetryInterval)
    )
    XCTAssertEqual(
      clock.deadline(at: 2),
      timestamp.addingTimeInterval(3 * HomeAssistantRollingEnergyRefreshState.failureRetryInterval)
    )
    await probe.cancel()
  }

  func testFailedDeadlineRefreshSchedulesOnlyTheFutureRetry() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingRollingEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let loader = SequencedSchedulingRollingTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: 0.91,
            end: timestamp.addingTimeInterval(10)
          )
        ),
        .failure(URLError(.timedOut)),
      ]
    )
    let (source, probe) = makeStream(loader: loader, clock: clock, delay: delay)
    await fulfillment(of: [source.started], timeout: 1)
    source.yield(.live(try states()))
    await fulfillment(
      of: [probe.received(at: 1), delay.started(at: 0)],
      timeout: 1
    )

    clock.advance(by: 10)
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )

    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(
      clock.deadline(at: 1),
      timestamp.addingTimeInterval(
        10 + HomeAssistantRollingEnergyRefreshState.failureRetryInterval
      )
    )
    await probe.cancel()
  }

}

private final class SchedulingRollingEnergyClock: @unchecked Sendable {
  private let lock = NSLock()
  private var storedNow: Date
  private var deadlines: [Date] = []

  init(_ now: Date) {
    storedNow = now
  }

  var now: Date {
    lock.withLock { storedNow }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock {
      storedNow = storedNow.addingTimeInterval(interval)
    }
  }

  func advanceToRetry() {
    advance(by: HomeAssistantRollingEnergyRefreshState.failureRetryInterval)
  }

  func record(deadline: Date) {
    lock.withLock {
      deadlines.append(deadline)
    }
  }

  func deadline(at index: Int) -> Date? {
    lock.withLock {
      deadlines.indices.contains(index) ? deadlines[index] : nil
    }
  }
}

private final class SequencedSchedulingRollingTotalsLoader:
  HomeAssistantRollingEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var results: [Result<HomeAssistantRollingEnergyTotals, any Error>]
  private var storedRequestCount = 0

  init(results: [Result<HomeAssistantRollingEnergyTotals, any Error>]) {
    self.results = results
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadRollingEnergyTotals() async throws -> HomeAssistantRollingEnergyTotals {
    try lock.withLock {
      storedRequestCount += 1
      return try results.removeFirst().get()
    }
  }
}
