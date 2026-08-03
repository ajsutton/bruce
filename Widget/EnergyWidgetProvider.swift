import OSLog
import WidgetKit

enum EnergyWidgetFreshness: Sendable {
  case current
  case lastKnown
  case unavailable
}

struct EnergyWidgetEntry: TimelineEntry, Sendable {
  let date: Date
  let snapshot: HomeEnergyWidgetSnapshot?
  let freshness: EnergyWidgetFreshness
  let isFullBruce: Bool
}

struct EnergyWidgetProvider: TimelineProvider {
  fileprivate static let logger = Logger(
    subsystem: "net.symphonious.bruce.energy-widget",
    category: "Timeline"
  )

  func placeholder(in context: Context) -> EnergyWidgetEntry {
    .preview
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping @Sendable (EnergyWidgetEntry) -> Void
  ) {
    if context.isPreview {
      completion(.preview)
      return
    }
    Task {
      completion(await EnergyWidgetRefreshCoordinator.shared.entry())
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping @Sendable (Timeline<EnergyWidgetEntry>) -> Void
  ) {
    Task {
      let entry = await EnergyWidgetRefreshCoordinator.shared.entry()
      completion(
        Timeline(
          entries: Self.minuteEntries(startingWith: entry),
          policy: .after(entry.date.addingTimeInterval(15 * 60))
        )
      )
    }
  }

  private static func minuteEntries(startingWith entry: EnergyWidgetEntry) -> [EnergyWidgetEntry] {
    guard let snapshot = entry.snapshot else { return [entry] }
    let hasLastKnownValues =
      entry.freshness == .lastKnown
      || !snapshot.readingsAreCurrent
      || !snapshot.importCostIsCurrent
      || !snapshot.feedInEarningsIsCurrent
    let referenceDate =
      hasLastKnownValues
      ? snapshot.oldestLastKnownCapture ?? snapshot.capturedAt
      : snapshot.capturedAt
    return EnergyWidgetFreshnessSchedule.entryDates(
      referenceDate: referenceDate,
      startingAt: entry.date
    ).map { date in
      if date == entry.date {
        entry
      } else {
        EnergyWidgetEntry(
          date: date,
          snapshot: snapshot,
          freshness: entry.freshness,
          isFullBruce: entry.isFullBruce
        )
      }
    }
  }
}

private struct EnergyWidgetRefreshCoordinator: Sendable {
  static let shared = EnergyWidgetRefreshCoordinator()
  private static let refreshTasks = SourceScopedTaskCoalescer<EnergyWidgetEntry>()

  func entry() async -> EnergyWidgetEntry {
    let initialState = Self.loadInitialState(
      store: HomeEnergyWidgetSnapshotStore(),
      credentialStore: WidgetHomeAssistantCredentialStore()
    )
    return await Self.refreshTasks.value(for: initialState.sourceIdentifier) {
      await Self.loadEntry(initialState: initialState)
    }
  }

  private static func loadEntry(initialState: InitialState) async -> EnergyWidgetEntry {
    let now = Date()
    let store = HomeEnergyWidgetSnapshotStore()
    let credentialStore = WidgetHomeAssistantCredentialStore()
    let isFullBruce =
      BruceSharedContainer.defaults()?.bool(forKey: "bruceMode") ?? false
    let sourceIdentifier = initialState.sourceIdentifier
    let cachedSnapshot = initialState.snapshot
    do {
      let snapshot = try await WidgetHomeEnergyClient().loadSnapshot(previous: cachedSnapshot)
      guard try credentialStore.load()?.sourceIdentifier == sourceIdentifier else {
        return latestEntryAfterConnectionChange(
          store: store,
          date: now,
          isFullBruce: isFullBruce
        )
      }
      try store?.save(snapshot, writer: .widget)
      return EnergyWidgetEntry(
        date: now,
        snapshot: snapshot,
        freshness: .current,
        isFullBruce: isFullBruce
      )
    } catch {
      EnergyWidgetProvider.logger.error(
        "Energy widget refresh failed; displaying cached data: \(String(describing: error), privacy: .private)"
      )
      guard (try? credentialStore.load()?.sourceIdentifier) == sourceIdentifier else {
        return latestEntryAfterConnectionChange(
          store: store,
          date: now,
          isFullBruce: isFullBruce
        )
      }
      return lastKnownEntry(cachedSnapshot, date: now, isFullBruce: isFullBruce)
    }
  }

  private static func loadInitialState(
    store: HomeEnergyWidgetSnapshotStore?,
    credentialStore: WidgetHomeAssistantCredentialStore
  ) -> InitialState {
    do {
      let credentials = try credentialStore.load()
      return InitialState(
        sourceIdentifier: credentials?.sourceIdentifier,
        snapshot: try credentials.flatMap {
          try store?.load(sourceIdentifier: $0.sourceIdentifier)
        }
      )
    } catch {
      EnergyWidgetProvider.logger.error(
        "Could not decode the Energy widget cache: \(String(describing: error), privacy: .private)"
      )
      return InitialState(sourceIdentifier: nil, snapshot: nil)
    }
  }

  private static func latestEntryAfterConnectionChange(
    store: HomeEnergyWidgetSnapshotStore?,
    date: Date,
    isFullBruce: Bool
  ) -> EnergyWidgetEntry {
    let credentials = try? WidgetHomeAssistantCredentialStore().load()
    let snapshot = try? credentials.flatMap {
      try store?.load(sourceIdentifier: $0.sourceIdentifier)
    }
    return lastKnownEntry(snapshot ?? nil, date: date, isFullBruce: isFullBruce)
  }

  private static func lastKnownEntry(
    _ snapshot: HomeEnergyWidgetSnapshot?,
    date: Date,
    isFullBruce: Bool
  ) -> EnergyWidgetEntry {
    EnergyWidgetEntry(
      date: date,
      snapshot: snapshot,
      freshness: snapshot == nil ? .unavailable : .lastKnown,
      isFullBruce: isFullBruce
    )
  }

  private struct InitialState: Sendable {
    let sourceIdentifier: String?
    let snapshot: HomeEnergyWidgetSnapshot?
  }
}

extension EnergyWidgetEntry {
  static let preview = EnergyWidgetEntry(
    date: Date(),
    snapshot: HomeEnergyWidgetSnapshot(
      capturedAt: Date().addingTimeInterval(-4 * 60),
      pvPowerKilowatts: 6.4,
      batteryStateOfCharge: 78,
      homeConsumptionKilowatts: 2.1,
      gridPowerKilowatts: -3.2,
      generalPriceDollarsPerKilowattHour: 0.284,
      feedInPriceDollarsPerKilowattHour: 0.08,
      importCostTodayDollars: 2.43,
      feedInEarningsTodayDollars: 4.18
    ),
    freshness: .current,
    isFullBruce: false
  )

  static let fullBruceEdgePreview = EnergyWidgetEntry(
    date: Date(),
    snapshot: HomeEnergyWidgetSnapshot(
      capturedAt: Date().addingTimeInterval(-12 * 60),
      pvPowerKilowatts: 0,
      batteryStateOfCharge: 14,
      homeConsumptionKilowatts: 4.8,
      gridPowerKilowatts: 4.8,
      generalPriceDollarsPerKilowattHour: 0.612,
      feedInPriceDollarsPerKilowattHour: -0.05,
      importCostTodayDollars: 12.48,
      feedInEarningsTodayDollars: 0.04,
      importCostIsCurrent: false,
      feedInEarningsIsCurrent: false
    ),
    freshness: .current,
    isFullBruce: true
  )

  static let lastKnownPreview = EnergyWidgetEntry(
    date: Date(),
    snapshot: preview.snapshot,
    freshness: .lastKnown,
    isFullBruce: true
  )

  static let unavailablePreview = EnergyWidgetEntry(
    date: Date(),
    snapshot: nil,
    freshness: .unavailable,
    isFullBruce: false
  )

  static let fullBruceUnavailablePreview = EnergyWidgetEntry(
    date: Date(),
    snapshot: nil,
    freshness: .unavailable,
    isFullBruce: true
  )
}
