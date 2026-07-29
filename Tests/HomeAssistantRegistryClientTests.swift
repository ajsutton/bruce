import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantRegistryClientTests: XCTestCase {
  func testRegistryResolvesClimateMetadataThroughEntityAndDeviceAreas() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: [
        HomeAssistantRegistryEntity(
          id: "climate.dining",
          deviceID: "dining-device",
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "climate.retreat",
          deviceID: "retreat-device",
          areaID: "retreat",
          icon: "mdi:air-conditioner",
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "light.dining",
          deviceID: "dining-device",
          areaID: nil,
          icon: "mdi:lightbulb",
          originalIcon: nil
        ),
      ],
      devices: [
        HomeAssistantRegistryDevice(id: "dining-device", areaID: "dining-room"),
        HomeAssistantRegistryDevice(id: "retreat-device", areaID: "wrong-area"),
      ],
      areas: [
        HomeAssistantRegistryArea(id: "dining-room", icon: "mdi:table-furniture"),
        HomeAssistantRegistryArea(id: "retreat", icon: "mdi:sofa-outline"),
      ]
    )

    XCTAssertEqual(
      metadata,
      [
        "climate.dining": HomeAssistantClimateMetadata(
          icon: "mdi:table-furniture",
          kind: .other
        ),
        "climate.retreat": HomeAssistantClimateMetadata(
          icon: "mdi:air-conditioner",
          kind: .other
        ),
      ]
    )
  }

  func testRegistryUsesOriginalIconOnlyWhenNoExplicitOrAreaIconExists() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: [
        HomeAssistantRegistryEntity(
          id: "climate.lounge",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: "mdi:thermostat"
        )
      ],
      devices: [],
      areas: []
    )

    XCTAssertEqual(
      metadata,
      [
        "climate.lounge": HomeAssistantClimateMetadata(
          icon: "mdi:thermostat",
          kind: .other
        )
      ]
    )
  }

  func testRegistryNormalizesAirTouchEntityKinds() {
    let metadata = HomeAssistantRegistryClient.climateMetadata(
      entities: [
        HomeAssistantRegistryEntity(
          id: "climate.ac_0",
          platform: "airtouch5",
          uniqueID: "ac_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "climate.dining",
          platform: "airtouch5",
          uniqueID: "zone_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "climate.other",
          platform: "another_platform",
          uniqueID: "ac_0",
          deviceID: nil,
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
      ],
      devices: [],
      areas: []
    )

    XCTAssertEqual(metadata["climate.ac_0"]?.kind, .airConditioner)
    XCTAssertEqual(metadata["climate.dining"]?.kind, .zone)
    XCTAssertEqual(metadata["climate.other"]?.kind, .other)
  }

  func testRegistryAssociatesGarageCompanionsByDeviceIdentity() {
    let registry = HomeAssistantRegistryClient.garageDoorRegistry(
      entities: [
        HomeAssistantRegistryEntity(
          id: "cover.side_entry",
          deviceID: "garage-device",
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
        HomeAssistantRegistryEntity(
          id: "light.side_entry_opener",
          deviceID: "garage-device",
          areaID: nil,
          icon: nil,
          originalIcon: nil
        ),
      ],
      devices: [
        HomeAssistantRegistryDevice(
          id: "garage-device",
          areaID: nil,
          name: "Opener 123",
          nameByUser: "Side Garage"
        )
      ]
    )

    XCTAssertEqual(registry.deviceIDByEntityID["cover.side_entry"], "garage-device")
    XCTAssertEqual(
      registry.deviceIDByEntityID["light.side_entry_opener"],
      "garage-device"
    )
    XCTAssertEqual(registry.deviceNameByID["garage-device"], "Side Garage")
  }

  func testWebSocketLoadsRegistriesAfterAuthenticating() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = StubHomeAssistantWebSocketConnection(
      receivedMessages: [
        #"{"type":"auth_required"}"#,
        #"{"type":"auth_ok"}"#,
        """
        {"id":1,"type":"result","success":true,"result":[
          {"entity_id":"climate.dining","platform":"airtouch5","unique_id":"zone_0",
           "device_id":"dining-device","area_id":null,"icon":null,"original_icon":null}
        ]}
        """,
        """
        {"id":2,"type":"result","success":true,"result":[
          {"id":"dining-device","area_id":"dining-room"}
        ]}
        """,
        """
        {"id":3,"type":"result","success":true,"result":[
          {"area_id":"dining-room","icon":"mdi:table-furniture"}
        ]}
        """,
      ]
    )
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: StubHomeAssistantWebSocketConnector(connection: connection)
    )

    let metadata = try await client.loadClimateMetadata()

    XCTAssertEqual(
      metadata,
      [
        "climate.dining": HomeAssistantClimateMetadata(
          icon: "mdi:table-furniture",
          kind: .zone
        )
      ]
    )
    XCTAssertEqual(connection.connectedURL?.absoluteString, "ws://home.local:8123/api/websocket")
    XCTAssertEqual(
      connection.sentMessageTypes,
      [
        "auth",
        "config/entity_registry/list",
        "config/device_registry/list",
        "config/area_registry/list",
      ]
    )
    XCTAssertTrue(connection.isCancelled)
  }

  func testRejectedWebSocketAuthenticationFailsAndClosesConnection() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = StubHomeAssistantWebSocketConnection(
      receivedMessages: [
        #"{"type":"auth_required"}"#,
        #"{"type":"auth_invalid"}"#,
      ]
    )
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: StubHomeAssistantWebSocketConnector(connection: connection)
    )

    do {
      _ = try await client.loadClimateMetadata()
      XCTFail("Expected WebSocket authentication to be rejected.")
    } catch HomeAssistantAPIError.unauthorized {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }

  func testCancellingRegistryLoadClosesBlockedWebSocket() async throws {
    let fixture = SessionFixture()
    let session = fixture.makeSession(apiResponses: [])
    try await session.install(fixture.credentials())
    let connection = BlockingHomeAssistantWebSocketConnection()
    let client = HomeAssistantRegistryClient(
      session: session,
      connector: BlockingHomeAssistantWebSocketConnector(connection: connection)
    )
    let load = Task {
      try await client.loadClimateMetadata()
    }
    await fulfillment(of: [connection.blockedReceiveStarted], timeout: 1)

    load.cancel()

    do {
      _ = try await load.value
      XCTFail("Expected the registry load to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertTrue(connection.isCancelled)
  }
}

private struct StubHomeAssistantWebSocketConnector: HomeAssistantWebSocketConnecting {
  let connection: StubHomeAssistantWebSocketConnection

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    connection.recordConnection(to: url)
    return connection
  }
}

private final class StubHomeAssistantWebSocketConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  private let lock = NSLock()
  private var receivedMessages: [Data]
  private var sentMessages: [Data] = []
  private var storedConnectedURL: URL?
  private var cancellationRequested = false

  init(receivedMessages: [String]) {
    self.receivedMessages = receivedMessages.map { Data($0.utf8) }
  }

  var connectedURL: URL? {
    lock.withLock { storedConnectedURL }
  }

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  var sentMessageTypes: [String] {
    lock.withLock {
      sentMessages.compactMap { data in
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"]
          as? String
      }
    }
  }

  func recordConnection(to url: URL) {
    lock.withLock {
      storedConnectedURL = url
    }
  }

  func send(_ data: Data) async throws {
    lock.withLock {
      sentMessages.append(data)
    }
  }

  func receive() async throws -> Data {
    try lock.withLock {
      guard !receivedMessages.isEmpty else {
        throw HomeAssistantAPIError.invalidResponse
      }
      return receivedMessages.removeFirst()
    }
  }

  func cancel() {
    lock.withLock {
      cancellationRequested = true
    }
  }
}

private struct BlockingHomeAssistantWebSocketConnector: HomeAssistantWebSocketConnecting {
  let connection: BlockingHomeAssistantWebSocketConnection

  func connect(to url: URL) -> any HomeAssistantWebSocketConnection {
    connection
  }
}

private final class BlockingHomeAssistantWebSocketConnection:
  HomeAssistantWebSocketConnection, @unchecked Sendable
{
  let blockedReceiveStarted = XCTestExpectation(description: "WebSocket receive blocked")

  private let lock = NSLock()
  private var initialMessage: Data? = Data(#"{"type":"auth_required"}"#.utf8)
  private var continuation: CheckedContinuation<Data, any Error>?
  private var cancellationRequested = false

  var isCancelled: Bool {
    lock.withLock { cancellationRequested }
  }

  func send(_ data: Data) async throws {}

  func receive() async throws -> Data {
    if let initialMessage = lock.withLock({
      defer {
        self.initialMessage = nil
      }
      return self.initialMessage
    }) {
      return initialMessage
    }

    return try await withCheckedThrowingContinuation { continuation in
      let shouldCancel = lock.withLock {
        guard !cancellationRequested else {
          return true
        }
        self.continuation = continuation
        return false
      }
      if shouldCancel {
        continuation.resume(throwing: CancellationError())
      } else {
        blockedReceiveStarted.fulfill()
      }
    }
  }

  func cancel() {
    let continuation = lock.withLock {
      cancellationRequested = true
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}
