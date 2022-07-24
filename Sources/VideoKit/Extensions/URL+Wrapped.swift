import Foundation

extension URL {

  /// A Boolean that is true if the url is wrapped
  var isWrapped: Bool {
    // Retrieve the url components and scheme
    guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
      let scheme = components.scheme
    else {
      return false
    }

    return scheme.starts(with: "videokit+")
  }

  /// Replaces the scheme of the url and add a file extension if needed.
  ///
  /// For instance `http://domain.ext/media` is replaced by
  /// `videokit+http://domain.ext/media+videokit.mp4`.
  ///
  /// - Returns: The url with its scheme wrapped.
  func wrap() -> URL? {
    // Retrieve the url components and scheme
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
      let scheme = components.scheme
    else {
      return nil
    }

    // Wrap the scheme
    components.scheme = "videokit+\(scheme)"

    // Adds and extension if needed
    components.path =
      self.pathExtension == ""
      ? "\(components.path)+videokit.mp4"
      : components.path

    // Return the url
    return components.url
  }

  /// Replace the scheme of the url and remove the file extension if needed.
  ///
  /// For instance `videokit+http://domain.ext/media+videokit.mp4` is replaced by
  /// `http://domain.ext/media`.
  ///
  /// - Returns: The url with its scheme unwrapped.
  func unwrap() -> URL? {
    // Retrieve the url components and scheme
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
      let wrappedScheme = components.scheme
    else {
      return nil
    }

    // Unwrap the scheme
    guard let schemeRange = wrappedScheme.range(of: "videokit+") else { return nil }
    components.scheme = wrappedScheme.replacingCharacters(in: schemeRange, with: "")

    // Unwrap the extension
    if let extensionRange = components.path.range(of: "+videokit.mp4") {
      components.path = components.path.replacingCharacters(in: extensionRange, with: "")
    }

    // Return the url
    return components.url
  }

}
