import AuthenticationServices
import Foundation

@MainActor
protocol HomeAssistantWebAuthenticating: AnyObject {
  func authenticate(at url: URL) async throws -> URL
  func cancel()
}

@MainActor
final class HomeAssistantWebAuthenticationPresenter: HomeAssistantWebAuthenticating {
  typealias AuthenticationAction = @MainActor (URL) async throws -> URL

  private struct Registration {
    let ownerID: UUID
    let authenticationAction: AuthenticationAction
  }

  private var registration: Registration?
  private var authenticationTask: Task<URL, any Error>?
  private var attemptID = UUID()

  init(authenticationAction: AuthenticationAction? = nil) {
    registration = authenticationAction.map {
      Registration(ownerID: UUID(), authenticationAction: $0)
    }
  }

  func register(
    ownerID: UUID,
    authenticationAction: @escaping AuthenticationAction
  ) {
    if let registration, registration.ownerID != ownerID {
      cancel()
    }
    registration = Registration(
      ownerID: ownerID,
      authenticationAction: authenticationAction
    )
  }

  func unregister(ownerID: UUID) {
    guard registration?.ownerID == ownerID else {
      return
    }
    registration = nil
    cancel()
  }

  func authenticate(at url: URL) async throws -> URL {
    cancel()
    guard let authenticationAction = registration?.authenticationAction else {
      throw HomeAssistantAuthenticationError.presentationUnavailable
    }
    let attemptID = UUID()
    self.attemptID = attemptID
    let task = Task {
      try await authenticationAction(url)
    }
    authenticationTask = task
    return try await withTaskCancellationHandler {
      defer {
        if self.attemptID == attemptID {
          authenticationTask = nil
        }
      }
      let callbackURL: URL
      do {
        callbackURL = try await task.value
      } catch let error as ASWebAuthenticationSessionError
        where error.code == .canceledLogin
      {
        throw CancellationError()
      }
      try Task.checkCancellation()
      guard self.attemptID == attemptID else {
        throw CancellationError()
      }
      return callbackURL
    } onCancel: {
      task.cancel()
    }
  }

  func cancel() {
    authenticationTask?.cancel()
    authenticationTask = nil
    attemptID = UUID()
  }
}
