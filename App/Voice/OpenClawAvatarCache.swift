import CryptoKit
import Foundation
import ImageIO

/// Decode away from the UI executor and reuse the same small image in picker and call views.
actor OpenClawAvatarCache {
  static let shared = OpenClawAvatarCache()
  private var images: [String: CGImage] = [:]
  private var insertionOrder: [String] = []

  func image(for value: String?) -> CGImage? {
    guard let value, value.hasPrefix("data:image/"), value.utf8.count <= 8_000_000 else {
      return nil
    }
    let key = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    if let image = images[key] { return image }
    guard let separator = value.range(of: ";base64,"),
      let data = Data(base64Encoded: String(value[separator.upperBound...])),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 384,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    else { return nil }
    if insertionOrder.count == 16 {
      images.removeValue(forKey: insertionOrder.removeFirst())
    }
    insertionOrder.append(key)
    images[key] = image
    return image
  }
}
