import Foundation

struct HomeEnergyPriceHistory: Equatable, Sendable {
  enum Tariff: String, CaseIterable, Equatable, Hashable, Sendable {
    case general
    case feedIn
  }

  struct ReadingIdentifier: Hashable, Sendable {
    let tariff: Tariff
    let timestamp: Date
  }

  struct Reading: Equatable, Identifiable, Sendable {
    let tariff: Tariff
    let timestamp: Date
    let dollarsPerKilowattHour: Double

    var id: ReadingIdentifier {
      ReadingIdentifier(tariff: tariff, timestamp: timestamp)
    }

    var centsPerKilowattHour: Double {
      dollarsPerKilowattHour * 100
    }
  }

  static let empty = HomeEnergyPriceHistory(
    interval: DateInterval(start: .distantPast, duration: 0),
    readings: []
  )

  let interval: DateInterval
  let readings: [Reading]

  var hasReadings: Bool {
    !readings.isEmpty
  }

  var hasCompleteTariffs: Bool {
    Set(readings.map(\.tariff)) == Set(Tariff.allCases)
  }

  var readingsExtendingToIntervalEnd: [Reading] {
    var extendedReadings = readings
    for tariff in Tariff.allCases {
      guard
        let latest = readings.last(where: { $0.tariff == tariff }),
        latest.timestamp < interval.end
      else {
        continue
      }
      extendedReadings.append(
        Reading(
          tariff: tariff,
          timestamp: interval.end,
          dollarsPerKilowattHour: latest.dollarsPerKilowattHour
        )
      )
    }
    return sorted(extendedReadings)
  }

  func recording(
    snapshot: HomeAssistantHomeEnergySnapshot,
    at timestamp: Date
  ) -> HomeEnergyPriceHistory {
    let start = timestamp.addingTimeInterval(-24 * 60 * 60)
    var updatedReadings = readingsPreservingValues(at: start)
    append(
      snapshot.generalPriceDollarsPerKilowattHour,
      tariff: .general,
      at: timestamp,
      to: &updatedReadings
    )
    append(
      snapshot.feedInPriceDollarsPerKilowattHour,
      tariff: .feedIn,
      at: timestamp,
      to: &updatedReadings
    )
    return HomeEnergyPriceHistory(
      interval: DateInterval(start: start, end: timestamp),
      readings: sorted(updatedReadings)
    )
  }

  func mergingLiveReadings(
    from liveHistory: HomeEnergyPriceHistory
  ) -> HomeEnergyPriceHistory {
    let mergedEnd = max(
      interval.end,
      liveHistory.readings.map(\.timestamp).max() ?? interval.end
    )
    let mergedStart = mergedEnd.addingTimeInterval(-24 * 60 * 60)
    let liveReadings = liveHistory.readings.filter {
      $0.timestamp >= mergedStart && $0.timestamp <= mergedEnd
    }
    let merged = HomeEnergyPriceHistory(
      interval: DateInterval(start: interval.start, end: mergedEnd),
      readings: sorted(readings + liveReadings)
    )
    return HomeEnergyPriceHistory(
      interval: DateInterval(start: mergedStart, end: mergedEnd),
      readings: merged.readingsPreservingValues(at: mergedStart)
    )
  }

  private func readingsPreservingValues(at start: Date) -> [Reading] {
    var retained = readings.filter { $0.timestamp >= start }
    for tariff in Tariff.allCases {
      guard
        !retained.contains(where: {
          $0.tariff == tariff && $0.timestamp == start
        })
      else {
        continue
      }
      guard
        let active = readings.last(where: {
          $0.tariff == tariff && $0.timestamp < start
        })
      else {
        continue
      }
      retained.append(
        Reading(
          tariff: tariff,
          timestamp: start,
          dollarsPerKilowattHour: active.dollarsPerKilowattHour
        )
      )
    }
    return sorted(retained)
  }

  private func sorted(_ readings: [Reading]) -> [Reading] {
    Dictionary(readings.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
      .values
      .sorted { lhs, rhs in
        if lhs.timestamp == rhs.timestamp {
          return lhs.tariff.rawValue < rhs.tariff.rawValue
        }
        return lhs.timestamp < rhs.timestamp
      }
  }

  private func append(
    _ value: Double?,
    tariff: Tariff,
    at timestamp: Date,
    to readings: inout [Reading]
  ) {
    guard let value, value.isFinite else { return }
    guard
      readings.last(where: { $0.tariff == tariff })?.dollarsPerKilowattHour
        != value
    else {
      return
    }
    readings.append(
      Reading(
        tariff: tariff,
        timestamp: timestamp,
        dollarsPerKilowattHour: value
      )
    )
  }
}
