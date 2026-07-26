import AuthenticationServices

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
protocol HomeAssistantWebAuthenticating: AnyObject {
  func authenticate(at url: URL) async throws -> URL
  func cancel()
}

@MainActor
protocol HAWebAuthenticationSession: AnyObject {
  var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? {
    get set
  }
  func start() -> Bool
  func cancel()
}

@MainActor
final class HomeAssistantWebAuthenticationPresenter: NSObject, HomeAssistantWebAuthenticating {
  typealias AnchorProvider = @MainActor () -> ASPresentationAnchor?
  typealias SessionFactory =
    @MainActor (
      URL,
      @escaping ASWebAuthenticationSession.CompletionHandler
    ) -> any HAWebAuthenticationSession

  private let anchorProvider: AnchorProvider
  private let sessionFactory: SessionFactory
  private let cancellationDeferral: @Sendable () async -> Void
  private var session: (any HAWebAuthenticationSession)?
  private var presentationContext: HAAuthenticationPresentationContext?
  private var continuation: CheckedContinuation<URL, any Error>?
  private var attemptID = UUID()

  init(
    anchorProvider: @escaping AnchorProvider =
      HomeAssistantWebAuthenticationPresenter.activePresentationAnchor,
    sessionFactory: @escaping SessionFactory =
      HomeAssistantWebAuthenticationPresenter.makeSession,
    cancellationDeferral: @escaping @Sendable () async -> Void = {}
  ) {
    self.anchorProvider = anchorProvider
    self.sessionFactory = sessionFactory
    self.cancellationDeferral = cancellationDeferral
  }

  func authenticate(at url: URL) async throws -> URL {
    cancel()
    guard let anchor = anchorProvider() else {
      throw HomeAssistantAuthenticationError.presentationUnavailable
    }
    let attemptID = UUID()
    self.attemptID = attemptID
    let callbackURL = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let session = sessionFactory(url) { [weak self] callbackURL, error in
          Task { @MainActor [weak self] in
            self?.complete(
              attemptID: attemptID,
              callbackURL: callbackURL,
              error: error
            )
          }
        }
        let presentationContext = HAAuthenticationPresentationContext(anchor: anchor)
        session.presentationContextProvider = presentationContext
        self.presentationContext = presentationContext
        self.session = session
        guard session.start() else {
          complete(
            attemptID: attemptID,
            callbackURL: nil,
            error: HomeAssistantAuthenticationError.unexpectedResponse
          )
          return
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        await cancellationDeferral()
        cancel(attemptID: attemptID)
      }
    }
    try Task.checkCancellation()
    return callbackURL
  }

  func cancel() {
    let activeSession = session
    let continuation = continuation
    session = nil
    presentationContext = nil
    self.continuation = nil
    attemptID = UUID()
    activeSession?.cancel()
    continuation?.resume(throwing: CancellationError())
  }

  private func cancel(attemptID: UUID) {
    guard self.attemptID == attemptID else {
      return
    }
    cancel()
  }

  private static func activePresentationAnchor() -> ASPresentationAnchor? {
    #if os(macOS)
      NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        ?? NSApplication.shared.windows.first(where: \.isVisible)
    #else
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let scene = scenes.first { $0.activationState == .foregroundActive }
      return scene?.keyWindow ?? scene?.windows.first(where: { !$0.isHidden })
    #endif
  }

  private static func makeSession(
    url: URL,
    completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler
  ) -> any HAWebAuthenticationSession {
    HAWebAuthenticationSessionAdapter(
      url: url,
      completionHandler: completionHandler
    )
  }

  private func complete(
    attemptID: UUID,
    callbackURL: URL?,
    error: (any Error)?
  ) {
    guard self.attemptID == attemptID, let continuation else {
      return
    }
    self.continuation = nil
    session = nil
    presentationContext = nil
    self.attemptID = UUID()
    if let authenticationError = error as? ASWebAuthenticationSessionError,
      authenticationError.code == .canceledLogin
    {
      continuation.resume(throwing: CancellationError())
    } else if let error {
      continuation.resume(throwing: error)
    } else if let callbackURL {
      continuation.resume(returning: callbackURL)
    } else {
      continuation.resume(throwing: HomeAssistantAuthenticationError.invalidCallback)
    }
  }
}

@MainActor
private final class HAWebAuthenticationSessionAdapter: HAWebAuthenticationSession {
  private let session: ASWebAuthenticationSession

  var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
  {
    get { session.presentationContextProvider }
    set { session.presentationContextProvider = newValue }
  }

  init(
    url: URL,
    completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler
  ) {
    session = ASWebAuthenticationSession(
      url: url,
      callback: .https(host: "bruce.symphonious.net", path: "/auth/"),
      completionHandler: completionHandler
    )
  }

  func start() -> Bool {
    session.start()
  }

  func cancel() {
    session.cancel()
  }
}

private final class HAAuthenticationPresentationContext: NSObject,
  ASWebAuthenticationPresentationContextProviding
{
  let anchor: ASPresentationAnchor

  init(anchor: ASPresentationAnchor) {
    self.anchor = anchor
  }

  func presentationAnchor(
    for session: ASWebAuthenticationSession
  ) -> ASPresentationAnchor {
    anchor
  }
}

#if os(iOS)
  extension UIWindowScene {
    fileprivate var keyWindow: UIWindow? {
      windows.first(where: \.isKeyWindow)
    }
  }
#endif
