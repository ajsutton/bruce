struct GarageDoorCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var navigationTitle: String { text(.navigationTitle) }
  var light: String { text(.light) }
  var lock: String { text(.lock) }
  var lightOn: String { text(.isOn) }
  var lightOff: String { text(.off) }
  var locked: String { text(.locked) }
  var locking: String { text(.locking) }
  var unlocking: String { text(.unlocking) }
  var unlocked: String { text(.unlocked) }
  var unavailable: String { text(.unavailable) }
  var updating: String { text(.updating) }
  var lastKnown: String { text(.lastKnown) }
  var checkingDevices: String { text(.checkingDevices) }
  var noDevicesTitle: String { text(.noDevicesTitle) }
  var noDevicesDescription: String { text(.noDevicesDescription) }
  var manage: String { text(.manage) }
  var refresh: String { text(.refresh) }
  var showDoorControls: String { text(.showDoorControls) }
  var hideDoorControls: String { text(.hideDoorControls) }
  var openDoor: String { text(.openDoor) }
  var openFully: String { text(.openFully) }
  var closeDoor: String { text(.closeDoor) }
  var stopDoor: String { text(.stopDoor) }
  var stopDoorHint: String { text(.stopDoorHint) }

  func doorState(_ state: HomeAssistantGarageDoorSnapshot.DoorState) -> String {
    switch state {
    case .open: text(.open)
    case .opening: text(.opening)
    case .closing: text(.closing)
    case .closed: text(.closed)
    case .partlyOpen: text(.partlyOpen)
    case .unavailable: unavailable
    }
  }

  func pending(command: HomeAssistantGarageDoorCommand) -> String {
    switch command {
    case .open: text(.sendingOpen)
    case .close: text(.sendingClose)
    case .stop: text(.sendingStop)
    }
  }

  func problem(_ problem: HomeAssistantGarageDoorStore.Problem) -> String {
    switch problem {
    case .connectionNeedsManagement: text(.connectionNeedsManagement)
    case .connectionUnavailable: text(.connectionUnavailable)
    case .reconnecting: text(.reconnecting)
    case .signInRequired: text(.signInRequired)
    case .invalidResponse: text(.invalidResponse)
    case .updateFailed: text(.updateFailed)
    }
  }

  private func text(_ key: Key) -> String {
    copy.text(key.entry)
  }
}

extension GarageDoorCopy {
  fileprivate enum Key: String {
    case navigationTitle
    case open
    case opening
    case closing
    case closed
    case partlyOpen
    case light
    case lock
    case isOn = "on"
    case off
    case locked
    case locking
    case unlocking
    case unlocked
    case unavailable
    case updating
    case lastKnown
    case checkingDevices
    case noDevicesTitle
    case noDevicesDescription
    case connectionNeedsManagement
    case connectionUnavailable
    case reconnecting
    case signInRequired
    case invalidResponse
    case manage
    case refresh
    case showDoorControls
    case hideDoorControls
    case openDoor
    case openFully
    case closeDoor
    case stopDoor
    case stopDoorHint
    case sendingOpen
    case sendingClose
    case sendingStop
    case updateFailed

    var entry: BruceCopy.Entry {
      switch self {
      case .navigationTitle: .localized("garageDoor.navigationTitle")
      case .open: .localized("garageDoor.open")
      case .opening: .localized("garageDoor.opening")
      case .closing: .localized("garageDoor.closing")
      case .closed: .localized("garageDoor.closed")
      case .partlyOpen: .localized("garageDoor.partlyOpen")
      case .light: .localized("garageDoor.light")
      case .lock: .localized("garageDoor.lock")
      case .isOn: .localized("garageDoor.on")
      case .off: .localized("garageDoor.off")
      case .locked: .localized("garageDoor.locked")
      case .locking: .localized("garageDoor.locking")
      case .unlocking: .localized("garageDoor.unlocking")
      case .unlocked: .localized("garageDoor.unlocked")
      case .unavailable: .localized("garageDoor.unavailable")
      case .updating: .localized("garageDoor.updating")
      case .lastKnown: .localized("garageDoor.lastKnown")
      case .checkingDevices: .localized("car.checkingDevices")
      case .noDevicesTitle: .localized("car.noDevicesTitle")
      case .noDevicesDescription: .localized("car.noDevicesDescription")
      case .connectionNeedsManagement:
        .localized("garageDoor.connectionNeedsManagement")
      case .connectionUnavailable:
        .localized("garageDoor.connectionUnavailable")
      case .reconnecting: .localized("garageDoor.reconnecting")
      case .signInRequired: .localized("garageDoor.signInRequired")
      case .invalidResponse: .localized("garageDoor.invalidResponse")
      case .manage: .localized("garageDoor.manage")
      case .refresh: .localized("garageDoor.refresh")
      case .showDoorControls: .localized("garageDoor.showDoorControls")
      case .hideDoorControls: .localized("garageDoor.hideDoorControls")
      case .openDoor: .localized("garageDoor.openDoor")
      case .openFully: .localized("garageDoor.openFully")
      case .closeDoor: .localized("garageDoor.closeDoor")
      case .stopDoor: .localized("garageDoor.stopDoor")
      case .stopDoorHint: .localized("garageDoor.stopDoorHint")
      case .sendingOpen: .localized("garageDoor.sendingOpen")
      case .sendingClose: .localized("garageDoor.sendingClose")
      case .sendingStop: .localized("garageDoor.sendingStop")
      case .updateFailed: .localized("garageDoor.updateFailed")
      }
    }
  }
}
