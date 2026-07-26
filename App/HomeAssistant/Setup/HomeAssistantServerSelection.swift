import Foundation

enum HomeAssistantServerSelection {
  struct State {
    let instanceID: String?
    let wasAutomatic: Bool
  }

  static func updatedState(
    instances: [HomeAssistantInstance],
    previousCount: Int,
    selectedInstanceID: String?,
    selectionWasAutomatic: Bool
  ) -> State {
    var selectedInstanceID = selectedInstanceID
    var selectionWasAutomatic = selectionWasAutomatic
    if let selectedID = selectedInstanceID,
      !instances.contains(where: { $0.id == selectedID })
    {
      selectedInstanceID = nil
      selectionWasAutomatic = false
    }
    if instances.count == 1, selectedInstanceID == nil {
      selectedInstanceID = instances[0].id
      selectionWasAutomatic = true
    } else if instances.count > 1, previousCount <= 1, selectionWasAutomatic {
      selectedInstanceID = nil
      selectionWasAutomatic = false
    }
    return State(
      instanceID: selectedInstanceID,
      wasAutomatic: selectionWasAutomatic
    )
  }

  static func candidate(
    from instance: HomeAssistantInstance
  ) -> HomeAssistantConnectionCandidate? {
    let activeURL = instance.internalURL ?? instance.eligibleExternalURL
    guard let activeURL else {
      return nil
    }
    return HomeAssistantConnectionCandidate(
      instanceID: instance.id,
      name: instance.name,
      internalURL: instance.internalURL,
      externalURL: instance.externalURL,
      activeURL: activeURL,
      source: .discovered
    )
  }
}
