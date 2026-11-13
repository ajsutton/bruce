import AVFoundation
import Foundation

/// Cancellation retires our waiter even while the system permission prompt remains open.
@MainActor
final class OpenClawMicrophonePermission {
  private let requestPermission: @MainActor (@escaping @Sendable (Bool) -> Void) -> Void

  init(
    requestPermission: @escaping @MainActor (@escaping @Sendable (Bool) -> Void) -> Void =
      OpenClawMicrophonePermission.systemRequest
  ) {
    self.requestPermission = requestPermission
  }

  private static func systemRequest(_ completion: @escaping @Sendable (Bool) -> Void) {
    #if os(iOS)
      AVAudioApplication.requestRecordPermission(completionHandler: completion)
    #else
      AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    #endif
  }

  private var waiter: CheckedContinuation<Bool, any Error>?

  func request() async throws -> Bool {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiter = continuation
        requestPermission { [weak self] granted in
          Task { @MainActor [weak self] in self?.finish(.success(granted)) }
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
    }
  }

  private func finish(_ result: Result<Bool, any Error>) {
    let waiter = waiter
    self.waiter = nil
    waiter?.resume(with: result)
  }
}
