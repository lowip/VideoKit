import Foundation
import CommonCrypto

extension String {

  // MARK: - Methods

  /// Computes the string's SHA256 hash.
  /// - Returns: The hexadecimal representation of the string's SHA256 hash.
  public func sha256() -> String {
    let data = Data(self.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
      _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return
      hash
      .map { String(format: "%02x", UInt8($0)) }
      .joined()
  }

  // - Regex

  func replacing(
    pattern: String,
    with template: String,
    options: NSRegularExpression.Options = []
  ) throws -> String {
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.stringByReplacingMatches(
      in: self,
      options: [],
      range: NSRange(location: 0, length: utf16.count),
      withTemplate: template
    )
  }

}
