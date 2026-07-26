import AuthenticationServices
import XCTest

@testable import Bruce

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
final class HAWebAuthenticationPresenterTests: XCTestCase {
  func testAuthenticationFailsCleanlyWithoutAPresentationAnchor() async throws {
    let presenter = HomeAssistantWebAuthenticationPresenter(anchorProvider: { nil })
    let url = try XCTUnwrap(URL(string: "https://home.example/auth/authorize"))

    do {
      _ = try await presenter.authenticate(at: url)
      XCTFail("Expected presentation to be unavailable.")
    } catch HomeAssistantAuthenticationError.presentationUnavailable {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testProgrammaticCancellationCompletesOnceAndIgnoresLateCallback() async throws {
    let session = ControlledWebAuthenticationSession()
    let presenter = makePresenter(sessions: [session])
    let authentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [session.started], timeout: 1)

    presenter.cancel()
    session.complete(with: callbackURL)

    do {
      _ = try await authentication.value
      XCTFail("Expected authentication cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(session.cancelCount, 1)
  }

  func testLateCallbackFromReplacedSessionCannotCompleteCurrentAttempt() async throws {
    let firstSession = ControlledWebAuthenticationSession()
    let secondSession = ControlledWebAuthenticationSession()
    let presenter = makePresenter(sessions: [firstSession, secondSession])
    let firstAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [firstSession.started], timeout: 1)

    let secondAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [secondSession.started], timeout: 1)
    firstSession.complete(with: callbackURL)
    secondSession.complete(with: callbackURL)

    do {
      _ = try await firstAuthentication.value
      XCTFail("Expected the replaced authentication to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let secondCallback = try await secondAuthentication.value
    XCTAssertEqual(secondCallback, callbackURL)
    XCTAssertEqual(firstSession.cancelCount, 1)
    XCTAssertEqual(secondSession.cancelCount, 0)
  }

  func testDelayedCancellationCannotCancelReplacementAttempt() async throws {
    let firstSession = ControlledWebAuthenticationSession()
    let secondSession = ControlledWebAuthenticationSession()
    let cancellationDeferral = WebAuthenticationCancellationDeferral()
    let presenter = makePresenter(
      sessions: [firstSession, secondSession],
      cancellationDeferral: {
        await cancellationDeferral.wait()
      }
    )
    let firstAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [firstSession.started], timeout: 1)

    firstAuthentication.cancel()
    await fulfillment(of: [cancellationDeferral.started], timeout: 1)
    let secondAuthentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [secondSession.started], timeout: 1)
    await cancellationDeferral.proceed()
    secondSession.complete(with: callbackURL)

    do {
      _ = try await firstAuthentication.value
      XCTFail("Expected the first authentication to be cancelled.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let secondCallback = try await secondAuthentication.value
    XCTAssertEqual(secondCallback, callbackURL)
    XCTAssertEqual(secondSession.cancelCount, 0)
  }

  func testCallbackCannotSucceedAfterAuthenticationTaskIsCancelled() async throws {
    let session = ControlledWebAuthenticationSession()
    let cancellationDeferral = WebAuthenticationCancellationDeferral()
    let presenter = makePresenter(
      sessions: [session],
      cancellationDeferral: {
        await cancellationDeferral.wait()
      }
    )
    let authentication = Task {
      try await presenter.authenticate(at: authenticationURL)
    }
    await fulfillment(of: [session.started], timeout: 1)

    authentication.cancel()
    await fulfillment(of: [cancellationDeferral.started], timeout: 1)
    session.complete(with: callbackURL)

    do {
      _ = try await authentication.value
      XCTFail("Expected authentication cancellation.")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    await cancellationDeferral.proceed()
  }

  private func makePresenter(
    sessions: [ControlledWebAuthenticationSession],
    cancellationDeferral: @escaping @Sendable () async -> Void = {}
  ) -> HomeAssistantWebAuthenticationPresenter {
    var remainingSessions = sessions
    return HomeAssistantWebAuthenticationPresenter(
      anchorProvider: { self.presentationAnchor },
      sessionFactory: { _, completionHandler in
        let session = remainingSessions.removeFirst()
        session.completionHandler = completionHandler
        return session
      },
      cancellationDeferral: cancellationDeferral
    )
  }

  private var authenticationURL: URL {
    URL(string: "https://home.example/auth/authorize") ?? URL(fileURLWithPath: "/")
  }

  private var callbackURL: URL {
    URL(string: "https://bruce.symphonious.net/auth/?code=value")
      ?? URL(fileURLWithPath: "/")
  }

  private var presentationAnchor: ASPresentationAnchor? {
    #if os(macOS)
      NSWindow()
    #else
      guard
        let windowScene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first
      else {
        return nil
      }
      return UIWindow(windowScene: windowScene)
    #endif
  }
}

private actor WebAuthenticationCancellationDeferral {
  nonisolated let started = XCTestExpectation(description: "Cancellation was deferred")
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started.fulfill()
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func proceed() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class ControlledWebAuthenticationSession: HAWebAuthenticationSession {
  let started = XCTestExpectation(description: "Web authentication started")
  var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
  var completionHandler: ASWebAuthenticationSession.CompletionHandler?
  private(set) var cancelCount = 0

  func start() -> Bool {
    started.fulfill()
    return true
  }

  func cancel() {
    cancelCount += 1
  }

  func complete(with callbackURL: URL) {
    completionHandler?(callbackURL, nil)
  }
}
