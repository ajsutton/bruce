import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantGarageDoorSnapshotTests: XCTestCase {
  func testGarageDoorDiscoveryGroupsDoorLightAndLockFromTheSameDevice() throws {
    let snapshots = HomeAssistantGarageDoorSnapshot.snapshots(
      states: try states(
        doorState: "closed",
        lightState: "off",
        lockState: "unlocked"
      ),
      registry: registry
    )

    XCTAssertEqual(
      snapshots,
      [
        HomeAssistantGarageDoorSnapshot(
          id: "cover.side_entry",
          name: "Side Garage",
          doorState: .closed,
          lightState: .off,
          lockState: .unlocked,
          lightEntityID: "light.side_entry_opener",
          lockEntityID: "lock.side_entry_remote",
          supportsStop: true
        )
      ]
    )
  }

  func testGarageDoorDiscoveryPreservesOpeningAndClosingStates() throws {
    let opening = HomeAssistantGarageDoorSnapshot.snapshots(
      states: try states(
        doorState: "opening",
        lightState: "on",
        lockState: "locked"
      ),
      registry: registry
    )
    let closing = HomeAssistantGarageDoorSnapshot.snapshots(
      states: try states(
        doorState: "closing",
        lightState: "on",
        lockState: "locked"
      ),
      registry: registry
    )

    XCTAssertEqual(opening.first?.doorState, .opening)
    XCTAssertTrue(opening.first?.doorState.isMoving == true)
    XCTAssertEqual(closing.first?.doorState, .closing)
    XCTAssertTrue(closing.first?.doorState.isMoving == true)
  }

  func testStoppedDoorBetweenEndpointsIsPartlyOpen() throws {
    let snapshots = HomeAssistantGarageDoorSnapshot.snapshots(
      states: try states(
        doorState: "open",
        lightState: "off",
        lockState: "unlocked",
        currentPosition: 42
      ),
      registry: registry
    )

    XCTAssertEqual(snapshots.first?.doorState, .partlyOpen)
  }

  func testNonGarageCoversAreNotDiscovered() throws {
    let data = Data(
      """
      [
        {
          "entity_id": "cover.lounge_blind",
          "state": "open",
          "attributes": {"device_class": "blind"}
        }
      ]
      """.utf8
    )
    let states = try JSONDecoder().decode([HomeAssistantState].self, from: data)

    XCTAssertTrue(
      HomeAssistantGarageDoorSnapshot.snapshots(
        states: states,
        registry: registry
      ).isEmpty
    )
  }

  func testAmbiguousCompanionsAreNotExposedAsControls() throws {
    var deviceIDs = registry.deviceIDByEntityID
    deviceIDs["light.other_opener"] = "garage-device"
    let ambiguousRegistry = HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: deviceIDs,
      deviceNameByID: registry.deviceNameByID
    )
    let extraLight = try JSONDecoder().decode(
      HomeAssistantState.self,
      from: Data(
        """
        {
          "entity_id": "light.other_opener",
          "state": "on",
          "attributes": {}
        }
        """.utf8
      )
    )
    let snapshots = HomeAssistantGarageDoorSnapshot.snapshots(
      states: try states(
        doorState: "closed",
        lightState: "off",
        lockState: "unlocked"
      ) + [extraLight],
      registry: ambiguousRegistry
    )

    XCTAssertEqual(snapshots.first?.lightState, .unavailable)
    XCTAssertNil(snapshots.first?.lightEntityID)
    XCTAssertEqual(snapshots.first?.lockEntityID, "lock.side_entry_remote")
  }

  private var registry: HomeAssistantGarageDoorRegistry {
    HomeAssistantGarageDoorRegistry(
      deviceIDByEntityID: [
        "cover.side_entry": "garage-device",
        "light.side_entry_opener": "garage-device",
        "lock.side_entry_remote": "garage-device",
      ],
      deviceNameByID: ["garage-device": "Side Garage"]
    )
  }

  private func states(
    doorState: String,
    lightState: String,
    lockState: String,
    currentPosition: Int = 0
  ) throws -> [HomeAssistantState] {
    let data = Data(
      """
      [
        {
          "entity_id": "cover.side_entry",
          "state": "\(doorState)",
          "attributes": {
            "device_class": "garage",
            "friendly_name": "Side Entry",
            "current_position": \(currentPosition),
            "supported_features": 15
          }
        },
        {
          "entity_id": "light.side_entry_opener",
          "state": "\(lightState)",
          "attributes": {}
        },
        {
          "entity_id": "lock.side_entry_remote",
          "state": "\(lockState)",
          "attributes": {}
        }
      ]
      """.utf8
    )
    return try JSONDecoder().decode([HomeAssistantState].self, from: data)
  }
}
