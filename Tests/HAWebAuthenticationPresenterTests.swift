import AuthenticationServices
import XCTest

@testable import Bruce

@MainActor
final class HAWebAuthenticationPresenterTests: XCTestCase {
  func testAuthenticationFailsCleanlyBeforeTheViewProvidesAnAuthenticationAction() async throws {
    let presenter = HomeAssistantWebAuthenticationPresenter()

    do {
      _ = try await presenter.authenticate(at: authenticationURL)
      XCTFail("Expected presentation to be unavailable.")
    } catch HomeAssistantAuthenticationError.presentationUnavailable {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAuthenticationReturnsTheCallbackFromTheConfiguredAction() async throws {
    let presenter = HomeAssistantWebAuthenticationPresenter { _ in
      self.callbackURL
    }

    let result = try await presenter.authenticate(at: authenticationURL)

    XCTAssertEqual(result, callbackURL)
  }

  func testDismissingTheAuthenticationSessionIsReportedInsteadOfSilentlyCancelled() async throws {
    let presenter = HomeAssistantWebAuthenticationPresenter { _ in
      throw ASWebAuthenticationSessionError(.canceledLogin)
    }

    do {
      _ = try await presenter.authenticate(at: authenticationURL)
      XCTFail("Expected the ended browser session.")
    } catch HomeAssistantWebAuthenticationError.sessionEnded {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testCancelledLoginClassificationDoesNotDependOnLocalizedDiagnostic() async throws {
    let diagnostic =
      "Die Anwendung ist nicht mit der Domain bruce.symphonious.net verknüpft."
    let presenter = HomeAssistantWebAuthenticationPresenter { _ in
      throw NSError(
        domain: ASWebAuthenticationSessionError.errorDomain,
        code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue,
        userInfo: [NSLocalizedDescriptionKey: diagnostic]
      )
    }

    do {
      _ = try await presenter.authenticate(at: authenticationURL)
      XCTFail("Expected the ambiguous cancelled-login failure.")
    } catch HomeAssistantWebAuthenticationError.sessionEnded(let receivedDiagnostic) {
      XCTAssertEqual(receivedDiagnostic, diagnostic)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testProgrammaticCancellationCancelsTheAuthenticationAction() async throws {
    let action = ControlledAuthenticationAction()
    let presenter = HomeAssistantWebAuthenticationPresenter {
      try await action.authenticate(at: $0)
    }
    let authentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [action.started], timeout: 1)

    presenter.cancel()

    do {
      _ = try await authentication.value
      XCTFail("Expected authentication cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await fulfillment(of: [action.cancelled], timeout: 1)
  }

  func testStartingAnotherAuthenticationCancelsThePreviousAction() async throws {
    let firstAction = ControlledAuthenticationAction()
    let secondAction = ControlledAuthenticationAction()
    var actions = [firstAction, secondAction]
    let presenter = HomeAssistantWebAuthenticationPresenter { url in
      let action = actions.removeFirst()
      return try await action.authenticate(at: url)
    }
    let firstAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [firstAction.started], timeout: 1)

    let secondAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [secondAction.started], timeout: 1)
    secondAction.complete(with: callbackURL)

    do {
      _ = try await firstAuthentication.value
      XCTFail("Expected the replaced authentication to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let result = try await secondAuthentication.value
    XCTAssertEqual(result, callbackURL)
    await fulfillment(of: [firstAction.cancelled], timeout: 1)
  }

  func testUnregisteringTheCurrentOwnerCancelsAuthentication() async throws {
    let action = ControlledAuthenticationAction()
    let presenter = HomeAssistantWebAuthenticationPresenter()
    let ownerID = UUID()
    presenter.register(ownerID: ownerID) {
      try await action.authenticate(at: $0)
    }
    let authentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [action.started], timeout: 1)

    presenter.unregister(ownerID: ownerID)

    do {
      _ = try await authentication.value
      XCTFail("Expected authentication cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await fulfillment(of: [action.cancelled], timeout: 1)
  }

  func testAnOlderOwnerCannotUnregisterANewerOwner() async throws {
    let presenter = HomeAssistantWebAuthenticationPresenter()
    let olderOwnerID = UUID()
    let newerOwnerID = UUID()
    presenter.register(ownerID: olderOwnerID) { _ in
      XCTFail("Expected the newer owner's action.")
      return self.callbackURL
    }
    presenter.register(ownerID: newerOwnerID) { _ in
      self.callbackURL
    }

    presenter.unregister(ownerID: olderOwnerID)

    let result = try await presenter.authenticate(at: authenticationURL)
    XCTAssertEqual(result, callbackURL)
  }

  func testReplacingAnActiveOwnerCancelsItsAuthenticationAndKeepsTheNewOwner() async throws {
    let olderAction = ControlledAuthenticationAction()
    let presenter = HomeAssistantWebAuthenticationPresenter()
    let olderOwnerID = UUID()
    let newerOwnerID = UUID()
    presenter.register(ownerID: olderOwnerID) {
      try await olderAction.authenticate(at: $0)
    }
    let olderAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [olderAction.started], timeout: 1)

    presenter.register(ownerID: newerOwnerID) { _ in
      self.callbackURL
    }
    presenter.unregister(ownerID: olderOwnerID)

    do {
      _ = try await olderAuthentication.value
      XCTFail("Expected the older owner's authentication to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await fulfillment(of: [olderAction.cancelled], timeout: 1)
    let result = try await presenter.authenticate(at: authenticationURL)
    XCTAssertEqual(result, callbackURL)
  }

  private var authenticationURL: URL {
    URL(string: "https://home.example/auth/authorize") ?? URL(fileURLWithPath: "/")
  }

  private var callbackURL: URL {
    URL(string: "https://bruce.symphonious.net/auth/?code=value")
      ?? URL(fileURLWithPath: "/")
  }
}

@MainActor
private final class ControlledAuthenticationAction {
  let started = XCTestExpectation(description: "Web authentication started")
  let cancelled = XCTestExpectation(description: "Web authentication cancelled")
  private var continuation: CheckedContinuation<URL, any Error>?

  func authenticate(at url: URL) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        started.fulfill()
      }
    } onCancel: {
      Task { @MainActor in
        self.cancel()
      }
    }
  }

  func complete(with url: URL) {
    continuation?.resume(returning: url)
    continuation = nil
  }

  private func cancel() {
    continuation?.resume(throwing: CancellationError())
    continuation = nil
    cancelled.fulfill()
  }
}
