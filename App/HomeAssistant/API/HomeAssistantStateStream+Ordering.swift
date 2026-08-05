import Foundation

extension HomeAssistantStateStream {
  struct Snapshot: Sendable {
    var statesByID: [String: HomeAssistantState]
    var removals: [String: Date]
    var orderedStates: [HomeAssistantState]
  }

  static func mergedSnapshot(
    _ states: [HomeAssistantState],
    previousStates: [HomeAssistantState],
    previousRemovals: [String: Date]
  ) throws -> Snapshot {
    guard states.allSatisfy({ $0.lastUpdated != nil }) else {
      throw HomeAssistantAPIError.invalidResponse
    }
    var statesByID: [String: HomeAssistantState] = [:]
    for state in states {
      guard statesByID.updateValue(state, forKey: state.entityID) == nil else {
        throw HomeAssistantAPIError.invalidResponse
      }
    }
    var removals = previousRemovals
    mergeRemovals(previousRemovals, into: &statesByID, retained: &removals)
    for previousState in previousStates
    where !shouldApply(
      statesByID[previousState.entityID] ?? previousState,
      over: previousState
    ) {
      statesByID[previousState.entityID] = previousState
    }
    return Snapshot(
      statesByID: statesByID,
      removals: removals,
      orderedStates: sorted(statesByID.values)
    )
  }

  private static func mergeRemovals(
    _ previousRemovals: [String: Date],
    into statesByID: inout [String: HomeAssistantState],
    retained removals: inout [String: Date]
  ) {
    for (entityID, removedAt) in previousRemovals {
      guard let state = statesByID[entityID],
        let lastUpdated = state.lastUpdated
      else {
        continue
      }
      if lastUpdated <= removedAt {
        statesByID.removeValue(forKey: entityID)
      } else {
        removals.removeValue(forKey: entityID)
      }
    }
  }

  static func sorted(
    _ states: Dictionary<String, HomeAssistantState>.Values
  ) -> [HomeAssistantState] {
    states.sorted { $0.entityID < $1.entityID }
  }

  static func shouldApply(
    _ state: HomeAssistantState,
    over existingState: HomeAssistantState?
  ) -> Bool {
    guard let existingState,
      let existingDate = existingState.lastUpdated,
      let newDate = state.lastUpdated
    else {
      return true
    }
    return newDate >= existingDate
  }

  static func apply(
    _ change: HomeAssistantStateChangedData,
    to snapshot: inout Snapshot
  ) throws {
    try validate(change.newState, entityID: change.entityID)
    try validate(change.oldState, entityID: change.entityID)
    guard change.newState != nil || change.oldState != nil else {
      throw HomeAssistantAPIError.invalidResponse
    }
    let previousState = snapshot.statesByID[change.entityID]
    if let newState = change.newState {
      apply(
        newState,
        to: &snapshot.statesByID,
        removals: &snapshot.removals
      )
    } else {
      applyRemoval(
        change,
        to: &snapshot.statesByID,
        removals: &snapshot.removals
      )
    }
    let currentState = snapshot.statesByID[change.entityID]
    guard previousState != currentState else { return }
    if let index = snapshot.orderedStates.firstIndex(where: {
      $0.entityID == change.entityID
    }) {
      if let currentState {
        snapshot.orderedStates[index] = currentState
      } else {
        snapshot.orderedStates.remove(at: index)
      }
    } else if let currentState {
      let insertionIndex =
        snapshot.orderedStates.firstIndex(where: {
          $0.entityID > change.entityID
        }) ?? snapshot.orderedStates.endIndex
      snapshot.orderedStates.insert(currentState, at: insertionIndex)
    }
  }

  private static func apply(
    _ newState: HomeAssistantState,
    to statesByID: inout [String: HomeAssistantState],
    removals: inout [String: Date]
  ) {
    let entityID = newState.entityID
    guard
      removals[entityID].map({ removedAt in
        guard let lastUpdated = newState.lastUpdated else { return true }
        return lastUpdated > removedAt
      }) ?? true,
      shouldApply(newState, over: statesByID[entityID])
    else {
      return
    }
    statesByID[entityID] = newState
    removals.removeValue(forKey: entityID)
  }

  private static func applyRemoval(
    _ change: HomeAssistantStateChangedData,
    to statesByID: inout [String: HomeAssistantState],
    removals: inout [String: Date]
  ) {
    guard
      change.oldState.map({
        shouldApply($0, over: statesByID[change.entityID])
      }) ?? true
    else {
      return
    }
    statesByID.removeValue(forKey: change.entityID)
    guard let removedAt = change.oldState?.lastUpdated,
      removals[change.entityID].map({ removedAt >= $0 }) ?? true
    else {
      return
    }
    removals[change.entityID] = removedAt
  }

  private static func validate(
    _ state: HomeAssistantState?,
    entityID: String
  ) throws {
    guard let state else {
      return
    }
    guard state.entityID == entityID, state.lastUpdated != nil else {
      throw HomeAssistantAPIError.invalidResponse
    }
  }

  static func shouldReconnect(
    after error: any Error,
    attempt: HomeAssistantReconnectAttempt
  ) -> Bool {
    guard let apiError = error as? HomeAssistantAPIError else {
      return true
    }
    switch apiError {
    case .server:
      return true
    case .invalidResponse:
      return attempt.hasPublishedSnapshot
    case .staleOperation:
      return attempt.attemptedAccess != nil
    case .noCredentials, .invalidServerURL, .unauthorized, .reauthenticationRequired,
      .incompatibleServer:
      return false
    }
  }
}
