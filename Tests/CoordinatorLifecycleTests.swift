import Foundation
import XCTest

@testable import Bruce

@MainActor
final class CoordinatorLifecycleTests: XCTestCase {
  func testCancelledServerStatusTaskDoesNotOpenFeed() async {
    let source = ControlledStateSource()
    let coordinator = makeCoordinator(serverUpdates: { await source.stateUpdates() })

    await coordinator.synchronize(with: .connected(credentials))
    await coordinator.synchronize(with: .disconnected)
    await Task.yield()

    XCTAssertEqual(source.subscriptionCount, 0)
  }

  func testCoordinatorTeardownCancelsActiveServerStatusFeed() async {
    let source = ControlledStateSource()
    var coordinator: HomeAssistantObservationCoordinator? = makeCoordinator(
      serverUpdates: { await source.stateUpdates() }
    )
    await coordinator?.synchronize(with: .connected(credentials))
    await fulfillment(of: [source.started], timeout: 1)

    coordinator = nil

    await fulfillment(of: [source.cancelled], timeout: 1)
    XCTAssertTrue(source.isCancelled)
  }

  private func makeCoordinator(
    serverUpdates:
      @escaping @Sendable () async -> AsyncThrowingStream<
        HomeAssistantStateUpdate, any Error
      >
  ) -> HomeAssistantObservationCoordinator {
    HomeAssistantObservationCoordinator(
      temperatureStore: HomeAssistantTemperatureStore(
        loader: LifecycleTemperatureLoader()
      ),
      chargingStore: HomeAssistantEVChargingStore(
        client: StreamingEVChargingClient()
      ),
      garageDoorStore: HomeAssistantGarageDoorStore(
        loader: TestGarageDoorLoader()
      ),
      homeEnergyStore: HomeAssistantHomeEnergyStore(
        loader: LifecycleEnergyLoader()
      ),
      serverUpdates: serverUpdates
    )
  }

  private var credentials: HomeAssistantCredentials {
    HomeAssistantCredentials(
      instanceID: "home",
      instanceName: "Home",
      internalURL: URL(string: "http://home.local:8123"),
      externalURL: URL(string: "https://home.example"),
      lastSuccessfulURL: URL(string: "https://home.example")
        ?? URL(fileURLWithPath: "/"),
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      accessTokenExpiresAt: Date(timeIntervalSince1970: 30_000),
      clientID: HomeAssistantOAuthConfiguration.release.clientID
    )
  }
}

private struct LifecycleTemperatureLoader: HomeAssistantTemperatureLoading {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live([]))
    }
  }
}

private struct LifecycleEnergyLoader: HomeAssistantHomeEnergyLoading {
  let providesContinuousEnergyUpdates = true

  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    .unavailable
  }

  func homeEnergyUpdates() -> AsyncThrowingStream<
    HomeAssistantLiveUpdate<HomeAssistantHomeEnergySnapshot>, any Error
  > {
    AsyncThrowingStream { continuation in
      continuation.yield(.live(.unavailable))
    }
  }
}
