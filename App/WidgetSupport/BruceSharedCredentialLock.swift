import Darwin
import Foundation

enum BruceSharedCredentialLock {
  enum LockError: Error {
    case containerUnavailable
    case openFailed(Int32)
    case lockFailed(Int32)
  }

  static func withLock<Value>(_ operation: () throws -> Value) throws -> Value {
    guard let containerURL = BruceSharedContainer.url() else {
      throw LockError.containerUnavailable
    }
    let lockURL = containerURL.appending(path: "home-assistant-credentials.lock")
    let descriptor = try openLockFile(at: lockURL)
    defer { close(descriptor) }
    try acquire(descriptor)
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
  }

  private static func openLockFile(at url: URL) throws -> Int32 {
    while true {
      let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      if descriptor >= 0 { return descriptor }
      if errno != EINTR { throw LockError.openFailed(errno) }
    }
  }

  private static func acquire(_ descriptor: Int32) throws {
    while flock(descriptor, LOCK_EX) != 0 {
      if errno != EINTR { throw LockError.lockFailed(errno) }
    }
  }
}
