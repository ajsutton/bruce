protocol HomeAssistantGarageDoorLoading: Sendable {
  var providesContinuousUpdates: Bool { get }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream
  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot]
}

enum HomeAssistantGarageDoorCommand: Equatable, Hashable, Sendable {
  case open
  case close
  case stop
}

protocol HomeAssistantGarageDoorControlling: Sendable {
  func setGarageLight(entityID: String, isOn: Bool) async throws
  func setGarageLock(entityID: String, isLocked: Bool) async throws
  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand,
    entityID: String
  ) async throws
}

extension HomeAssistantGarageDoorLoading {
  var providesContinuousUpdates: Bool { false }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream {
    HomeAssistantGarageDoorUpdateStream { continuation in
      let task = Task {
        do {
          continuation.yield(.live(try await loadGarageDoors()))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
typealias HomeAssistantGarageDoorUpdate = HomeAssistantLiveUpdate<
  [HomeAssistantGarageDoorSnapshot]
>
typealias HomeAssistantGarageDoorUpdateStream = HomeAssistantBufferedUpdateStream<
  HomeAssistantGarageDoorUpdate
>
