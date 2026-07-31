import XCTest

@testable import Bruce

final class DailyEnergyStreamSchedulingTests: XCTestCase {
  func testDayRolloverRefreshesWithoutAnotherStateUpdate() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingDailyEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let loader = SequencedSchedulingDailyTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: 0.91,
            start: timestamp.addingTimeInterval(-60),
            end: timestamp.addingTimeInterval(10)
          )
        ),
        .success(
          totals(
            importCost: 0.01,
            earnings: 0.02,
            start: timestamp.addingTimeInterval(10),
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
    XCTAssertEqual(refreshed.importCostTodayDollars, 0.01)
    XCTAssertEqual(refreshed.feedInEarningsTodayDollars, 0.02)
    await probe.cancel()
  }

  func testFailedRequestRetriesWithoutAnotherStateUpdate() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingDailyEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let loader = SequencedSchedulingDailyTotalsLoader(
      results: [
        .failure(URLError(.timedOut)),
        .success(
          totals(
            importCost: 0.20,
            earnings: 0.91,
            start: timestamp,
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
    XCTAssertEqual(failed.importCostTodayStatus, .failed)

    clock.advanceToRetry()
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    let recovered = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(loader.requestCount, 2)
    XCTAssertEqual(recovered.importCostTodayStatus, .current)
    XCTAssertEqual(recovered.importCostTodayDollars, 0.20)
    await probe.cancel()
  }

  func testComplementaryPartialResultsConvergeWithoutAnotherRetry()
    async throws
  {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingDailyEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let intervalEnd = timestamp.addingTimeInterval(24 * 60 * 60)
    let loader = SequencedSchedulingDailyTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: nil,
            start: timestamp,
            end: intervalEnd
          )
        ),
        .success(
          totals(
            importCost: nil,
            earnings: 0.91,
            start: timestamp,
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
    XCTAssertEqual(partial.importCostTodayDollars, 0.20)
    XCTAssertEqual(partial.importCostTodayStatus, .current)
    XCTAssertEqual(partial.feedInEarningsTodayStatus, .failed)

    clock.advanceToRetry()
    delay.finish(0)
    await fulfillment(
      of: [probe.received(at: 3), delay.started(at: 1)],
      timeout: 1
    )
    let complete = try liveSnapshot(probe.value(at: 3))

    XCTAssertEqual(loader.requestCount, 2)
    assertComplementaryTotalsAreCurrent(complete)
    XCTAssertEqual(clock.deadline(at: 1), intervalEnd)
    await probe.cancel()
  }

  private func makeStream(
    loader: SequencedSchedulingDailyTotalsLoader,
    clock: SchedulingDailyEnergyClock,
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
      dailyTotalsLoader: loader,
      now: { clock.now },
      dailyRefreshSleep: { deadline in
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
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.importCostEntityID)",
            "state":"2",
            "attributes":{"last_reset":"initial"}
          },
          {
            "entity_id":"\(HomeAssistantHomeEnergySnapshot.feedInEarningsEntityID)",
            "state":"4",
            "attributes":{"last_reset":"initial"}
          }
        ]
        """.utf8
      )
    )
  }

  private func totals(
    importCost: Double?,
    earnings: Double?,
    start: Date,
    end: Date
  ) -> HomeAssistantDailyEnergyTotals {
    HomeAssistantDailyEnergyTotals(
      importCostDollars: importCost,
      feedInEarningsDollars: earnings,
      interval: DateInterval(start: start, end: end)
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

private func assertComplementaryTotalsAreCurrent(
  _ snapshot: HomeAssistantHomeEnergySnapshot
) {
  XCTAssertEqual(snapshot.importCostTodayDollars, 0.20)
  XCTAssertEqual(snapshot.feedInEarningsTodayDollars, 0.91)
  XCTAssertEqual(snapshot.importCostTodayStatus, .current)
  XCTAssertEqual(snapshot.feedInEarningsTodayStatus, .current)
}

extension DailyEnergyStreamSchedulingTests {
  func testDayBoundaryPreemptsPartialResultRetry() async throws {
    let timestamp = Date(timeIntervalSince1970: 10_000)
    let clock = SchedulingDailyEnergyClock(timestamp)
    let delay = ControlledHomeEnergyDelay(delayCount: 2)
    let intervalEnd = timestamp.addingTimeInterval(10)
    let loader = SequencedSchedulingDailyTotalsLoader(
      results: [
        .success(
          totals(
            importCost: 0.20,
            earnings: nil,
            start: timestamp.addingTimeInterval(-60),
            end: intervalEnd
          )
        ),
        .success(
          totals(
            importCost: 0.01,
            earnings: 0.02,
            start: intervalEnd,
            end: intervalEnd.addingTimeInterval(24 * 60 * 60)
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
    XCTAssertEqual(refreshed.importCostTodayDollars, 0.01)
    XCTAssertEqual(refreshed.feedInEarningsTodayDollars, 0.02)
    await probe.cancel()
  }
}

private final class SchedulingDailyEnergyClock: @unchecked Sendable {
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
    advance(by: HomeAssistantDailyEnergyRefreshState.failureRetryInterval)
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

private final class SequencedSchedulingDailyTotalsLoader:
  HomeAssistantDailyEnergyTotalsLoading, @unchecked Sendable
{
  private let lock = NSLock()
  private var results: [Result<HomeAssistantDailyEnergyTotals, any Error>]
  private var storedRequestCount = 0

  init(results: [Result<HomeAssistantDailyEnergyTotals, any Error>]) {
    self.results = results
  }

  var requestCount: Int {
    lock.withLock { storedRequestCount }
  }

  func loadDailyEnergyTotals() async throws -> HomeAssistantDailyEnergyTotals {
    try lock.withLock {
      storedRequestCount += 1
      return try results.removeFirst().get()
    }
  }
}

private struct SchedulingUnusedHomeEnergyLoader:
  HomeAssistantHomeEnergyLoading
{
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}
