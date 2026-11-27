import Foundation
import Synchronization

/// In-memory demo state shared by controls and their existing observation streams.
final class DemoValue<Value: Sendable>: Sendable {
  private struct State: Sendable {
    var value: Value
    var observers: [UUID: @Sendable (Value) -> Void] = [:]
  }
  private let state: Mutex<State>

  init(_ value: Value) {
    state = Mutex(State(value: value))
  }

  var value: Value { state.withLock { $0.value } }

  func update(_ change: (inout Value) throws -> Void) rethrows {
    try state.withLock {
      try change(&$0.value)
      for observer in $0.observers.values { observer($0.value) }
    }
  }

  func observe(_ receive: @escaping @Sendable (Value) -> Void) -> UUID {
    state.withLock {
      let id = UUID()
      $0.observers[id] = receive
      receive($0.value)
      return id
    }
  }

  func removeObserver(_ id: UUID) {
    state.withLock { $0.observers[id] = nil }
  }
}
