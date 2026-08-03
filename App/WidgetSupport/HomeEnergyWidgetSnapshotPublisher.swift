#if os(iOS)
  import Foundation
  import OSLog
  import WidgetKit

  @MainActor
  final class HomeEnergyWidgetSnapshotPublisher {
    private let store: HomeEnergyWidgetSnapshotStore?
    private let reloadTimelines: () -> Void
    private let sourceIdentifier: () -> String?
    private let logger = Logger(
      subsystem: Bundle.main.bundleIdentifier ?? "Bruce",
      category: "EnergyWidget"
    )

    init(
      store: HomeEnergyWidgetSnapshotStore? = HomeEnergyWidgetSnapshotStore(),
      sourceIdentifier: @escaping () -> String? = {
        BruceSharedHomeAssistant.storedSourceIdentifier()
      },
      reloadTimelines: @escaping () -> Void = {
        WidgetCenter.shared.reloadTimelines(ofKind: EnergyWidgetKind.value)
      }
    ) {
      self.store = store
      self.sourceIdentifier = sourceIdentifier
      self.reloadTimelines = reloadTimelines
    }

    func publish(_ snapshot: HomeAssistantHomeEnergySnapshot, capturedAt: Date) {
      guard let store,
        let sourceIdentifier = sourceIdentifier()
      else { return }
      let previousSnapshot: HomeEnergyWidgetSnapshot?
      do {
        previousSnapshot = try store.load(sourceIdentifier: sourceIdentifier)
      } catch {
        logger.error(
          "Could not decode the Energy Now widget snapshot: \(String(describing: error), privacy: .private)"
        )
        previousSnapshot = nil
      }
      let widgetSnapshot = HomeEnergyWidgetSnapshot(
        snapshot: snapshot,
        capturedAt: capturedAt,
        sourceIdentifier: sourceIdentifier,
        previous: previousSnapshot
      )
      do {
        try store.save(widgetSnapshot, writer: .app)
        if previousSnapshot?.hasSameReadings(as: widgetSnapshot) != true {
          reloadTimelines()
        }
      } catch {
        logger.error(
          "Could not save the Energy Now widget snapshot: \(String(describing: error), privacy: .private)"
        )
      }
    }
  }
#endif
