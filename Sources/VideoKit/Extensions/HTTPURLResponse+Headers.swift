import Foundation

extension HTTPURLResponse {

  /// Returns the value that corresponds to the given header field.
  ///
  /// In keeping with the HTTP RFC, HTTP header field names are case-insensitive.
  ///
  /// - Important: We have to declare our own version of `value(forHTTPHeaderField:)` because
  ///              Apple's version is only available starting with os versions supporting Swift 5.1
  ///              (iOS 13.0, tvOS 13.0, macOS 10.15).
  ///              `allHeaderFields` was previously documented as case-insensitive, though this is
  ///              not the case in Swift, see [Github issue](https://archive.ph/zSUtO).
  ///
  /// - Parameter field: The name of the header field you want to retrieve. The name is
  ///                    case-insensitive.
  /// - Returns: The value associated with the given header field, or nil if no value is associated
  ///            with the field.
  func value(forHTTPHeaderField field: String) -> String? {
    return (self.allHeaderFields as NSDictionary).object(forKey: field) as? String
  }

  /// The content length of the remote resource (extracted from the `Content-Range` header)
  var fullContentLength: Int64 {
    guard let contentRange = self.value(forHTTPHeaderField: "Content-Range") else {
      // NSURLResponseUnknownLength is not available yet in swift (https://bugs.swift.org/browse/SR-485)
      return -1
    }

    guard let contentRangeLast = contentRange.split(separator: "/").last,
      let contentLength = Int64(contentRangeLast)
    else {
      // NSURLResponseUnknownLength is not available yet in swift (https://bugs.swift.org/browse/SR-485)
      return -1
    }

    return contentLength
  }

}
