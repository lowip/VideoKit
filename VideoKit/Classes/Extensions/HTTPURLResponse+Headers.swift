//
//  HTTPURLResponse+Headers.swift
//  VideoKit
//
//  Created by Louis Bur on 3/13/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import Foundation

extension HTTPURLResponse {
  /**
   The value which corresponds to the given header.
   
   Note that, in keeping with the HTTP RFC, HTTP header field names are case-insensitive.
   
   - Note: We have to declare this method because of a bug in `allHeaderFields` which should be case-insensitive
           but is not. See: https://bit.ly/2Y4klHQ
   
   - Parameter field: The header field name to use for the lookup (case-insensitive)
   */
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
      let contentLength = Int64(contentRangeLast) else {
        // NSURLResponseUnknownLength is not available yet in swift (https://bugs.swift.org/browse/SR-485)
        return -1
    }
    
    return contentLength
  }
}
