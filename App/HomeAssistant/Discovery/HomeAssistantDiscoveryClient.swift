import Foundation

struct HomeAssistantDiscoveryAdvertisement: Equatable, Identifiable, Sendable {
  let id: String
  let serviceName: String
  let txt: [String: String]
  let resolvedInternalURL: URL?
}

enum HomeAssistantDiscoveryError: Error, Equatable, Sendable {
  case permissionDenied
  case browserFailed(String)
}

struct HomeAssistantDiscoveryIssue: Equatable, Identifiable, Sendable {
  enum Problem: Equatable, Sendable {
    case missingUUID
    case invalidURLFields([String])
  }

  let advertisementID: String
  let serviceName: String
  let problem: Problem

  var id: String {
    advertisementID
  }
}

struct HomeAssistantDiscoverySnapshot: Equatable, Sendable {
  let instances: [HomeAssistantInstance]
  let issues: [HomeAssistantDiscoveryIssue]
}

protocol HomeAssistantDiscoveryBrowsing: Sendable {
  func advertisements()
    -> AsyncThrowingStream<[HomeAssistantDiscoveryAdvertisement], any Error>
}

protocol HomeAssistantDiscovering: Sendable {
  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error>
}

struct HomeAssistantDiscoveryClient: HomeAssistantDiscovering {
  private let browser: any HomeAssistantDiscoveryBrowsing

  init(browser: any HomeAssistantDiscoveryBrowsing) {
    self.browser = browser
  }

  func snapshots() -> AsyncThrowingStream<HomeAssistantDiscoverySnapshot, any Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          for try await advertisements in browser.advertisements() {
            try Task.checkCancellation()
            continuation.yield(Self.snapshot(from: advertisements))
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  private static func snapshot(
    from advertisements: [HomeAssistantDiscoveryAdvertisement]
  ) -> HomeAssistantDiscoverySnapshot {
    let (parsed, issues) = parse(advertisements)
    let instances = deduplicate(parsed).sorted {
      let nameComparison = $0.name.localizedStandardCompare($1.name)
      return nameComparison == .orderedSame ? $0.id < $1.id : nameComparison == .orderedAscending
    }
    return HomeAssistantDiscoverySnapshot(instances: instances, issues: issues)
  }

  private static func parse(
    _ advertisements: [HomeAssistantDiscoveryAdvertisement]
  ) -> ([HomeAssistantInstance], [HomeAssistantDiscoveryIssue]) {
    var instances: [HomeAssistantInstance] = []
    var issues: [HomeAssistantDiscoveryIssue] = []
    for advertisement in advertisements.sorted(by: { $0.id < $1.id }) {
      do {
        let record = try HomeAssistantDiscoveryRecord(
          serviceName: advertisement.serviceName,
          txt: advertisement.txt,
          resolvedInternalURL: advertisement.resolvedInternalURL
        )
        if !record.invalidURLFields.isEmpty {
          issues.append(
            HomeAssistantDiscoveryIssue(
              advertisementID: advertisement.id,
              serviceName: advertisement.serviceName,
              problem: .invalidURLFields(record.invalidURLFields)
            )
          )
        }
        instances.append(record.instance)
      } catch {
        issues.append(
          HomeAssistantDiscoveryIssue(
            advertisementID: advertisement.id,
            serviceName: advertisement.serviceName,
            problem: .missingUUID
          )
        )
      }
    }
    return (instances, issues)
  }

  private static func deduplicate(
    _ instances: [HomeAssistantInstance]
  ) -> [HomeAssistantInstance] {
    Dictionary(grouping: instances, by: \.id).compactMap { _, instances in
      instances.reduce(nil as HomeAssistantInstance?) { accumulated, instance in
        guard let accumulated else {
          return instance
        }
        return HomeAssistantInstance(
          id: instance.id,
          name: preferredName(accumulated.name, instance.name),
          version: accumulated.version ?? instance.version,
          internalURL: accumulated.internalURL ?? instance.internalURL,
          externalURL: accumulated.externalURL ?? instance.externalURL,
          isOnboarding: accumulated.isOnboarding || instance.isOnboarding
        )
      }
    }
  }

  private static func preferredName(_ first: String, _ second: String) -> String {
    first.localizedStandardCompare(second) == .orderedDescending ? second : first
  }
}
