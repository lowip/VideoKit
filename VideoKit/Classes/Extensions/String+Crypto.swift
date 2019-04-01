//
//  String+Crypto.swift
//  VideoKit
//
//  Created by Louis Bur on 3/13/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import Foundation
import CommonCrypto

/// Defines types of hash string outputs available
enum HashOutputType {
  /// Standard hex string output
  case hex
  /// Base64 encoded string output
  case base64
}

/// Defines types of hash algorithms available
enum HashType {
  case md5
  case sha1
  case sha224
  case sha256
  case sha384
  case sha512
  
  var length: Int32 {
    switch self {
    case .md5: return CC_MD5_DIGEST_LENGTH
    case .sha1: return CC_SHA1_DIGEST_LENGTH
    case .sha224: return CC_SHA224_DIGEST_LENGTH
    case .sha256: return CC_SHA256_DIGEST_LENGTH
    case .sha384: return CC_SHA384_DIGEST_LENGTH
    case .sha512: return CC_SHA512_DIGEST_LENGTH
    }
  }
}

extension String {
  
  /// md5 hash of the string in hex form
  var md5: String? {
    return self.hashed(.md5)
  }
  
  /// Hashing algorithm for hashing a string instance.
  ///
  /// - Parameters:
  ///   - type: The type of hash to use.
  ///   - output: The type of output desired, defaults to .hex.
  ///
  /// - Returns: The requested hash output or nil if failure.
  func hashed(_ type: HashType, output: HashOutputType = .hex) -> String? {
    // convert string to utf8 encoded data
    guard let message = self.data(using: .utf8) else { return nil }
    
    // setup data variable to hold hashed value
    var digest = Data(count: Int(type.length))
    
    // generate hash using specified hash type
    _ = digest.withUnsafeMutableBytes { (digestBytes: UnsafeMutablePointer<UInt8>) in
      message.withUnsafeBytes { (messageBytes: UnsafePointer<UInt8>) in
        let length = CC_LONG(message.count)
        switch type {
        case .md5: CC_MD5(messageBytes, length, digestBytes)
        case .sha1: CC_SHA1(messageBytes, length, digestBytes)
        case .sha224: CC_SHA224(messageBytes, length, digestBytes)
        case .sha256: CC_SHA256(messageBytes, length, digestBytes)
        case .sha384: CC_SHA384(messageBytes, length, digestBytes)
        case .sha512: CC_SHA512(messageBytes, length, digestBytes)
        }
      }
    }
    
    // return the value based on the specified output type.
    switch output {
    case .hex: return digest.map { String(format: "%02hhx", $0) }.joined()
    case .base64: return digest.base64EncodedString()
    }
  }
}
