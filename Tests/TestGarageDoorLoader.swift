@testable import Bruce

struct TestGarageDoorLoader: HomeAssistantGarageDoorLoading {
  let providesContinuousUpdates = true

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] {
    []
  }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream {
    HomeAssistantGarageDoorUpdateStream { continuation in
      continuation.yield(.live([]))
    }
  }
}
