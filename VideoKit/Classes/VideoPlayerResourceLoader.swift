//
//  VideoPlayerResourceLoader.swift
//  VideoKit
//
//  Created by Louis Bur on 3/11/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import AVFoundation

// MARK: - VideoPlayerResourceLoader

final class VideoPlayerResourceLoader: NSObject {
  
  // MARK: - Enums
  
  enum Error: Swift.Error {
    case invalidURL
    case invalidRequest
    case invalidResponse
  }
  
  // MARK: - Properties
  
  /// The session used to download media fragments
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpShouldUsePipelining = true
    configuration.timeoutIntervalForRequest = 5
    return URLSession(configuration: configuration)
  }()
  
  /// The key used for the cache
  private let cacheKey: String
  
  /// Instance access to the static session
  private var session: URLSession {
    return type(of: self).session
  }
  
  /// The map of dataTasks associated with loadingRequests
  private var loadingRequestsMap = [AVAssetResourceLoadingRequest: URLSessionDataTask]()
  
  // MARK: - Initializing
  
  init(cacheKey: String) {
    // Properties
    self.cacheKey = cacheKey
    
    // Super
    super.init()
  }
  
  deinit {
    // Cancel all requests
    self.loadingRequestsMap.values.forEach { $0.cancel() }
  }
  
  // MARK: - Private Methods
  
  private func processLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
    // Unwrap the url and replace it in the request
    var request = loadingRequest.request
    guard let unwrappedUrl = request.url?.unwrap() else {
      self.finishLoading(loadingRequest, error: Error.invalidURL)
      return
    }
    request.url = unwrappedUrl
    
    // Verify requests consistency
    guard let dataRequest = loadingRequest.dataRequest else {
      loadingRequest.contentInformationRequest != nil
        ? self.finishLoading(loadingRequest, error: Error.invalidRequest)
        : self.finishLoading(loadingRequest)
      return
    }
    
    // Set range header
    // The `requestsAllDataToEndOfResource` is often true, even for simple mp4 files.
    // In that case, we limit the max requested length to 1Mib (== 1 << 20 bytes)
    let range = dataRequest.requestsAllDataToEndOfResource
      ? "bytes=\(dataRequest.requestedOffset)-\(dataRequest.requestedOffset + Int64(min(dataRequest.requestedLength - 1, 1 << 20)))"
      : "bytes=\(dataRequest.requestedOffset)-\(dataRequest.requestedOffset + Int64(dataRequest.requestedLength) - 1)"
    request.addValue(range, forHTTPHeaderField: "Range")
    
    // Create dataTask
    let dataTask = self.session.dataTask(with: request) { [weak self] data, response, error in
      defer {
        // Reset loadingRequest in map
        self?.loadingRequestsMap.removeValue(forKey: loadingRequest)
      }
      
      // Handle errors
      guard let data = data, let response = response as? HTTPURLResponse else {
        if let error = error, (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorCancelled {
          self?.finishLoading(loadingRequest)
          return
        }
        self?.finishLoading(loadingRequest, error: error ?? Error.invalidResponse)
        return
      }
      
      // Provide data to the dataRequest
      dataRequest.respond(with: data)
      
      // Provide content information if needed
      if let contentInformationRequest = loadingRequest.contentInformationRequest {
        contentInformationRequest.contentType = response.mimeType
        contentInformationRequest.contentLength = response.fullContentLength
        contentInformationRequest.isByteRangeAccessSupported = response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
      }
      
      // Finish loading
      self?.finishLoading(loadingRequest)
    }
    
    // Add dataTask to map
    self.loadingRequestsMap[loadingRequest] = dataTask
    
    // Perform dataTask
    dataTask.resume()
  }
  
  private func finishLoading(
    _ loadingRequest: AVAssetResourceLoadingRequest,
    error: Swift.Error? = nil
  ) {
    guard !loadingRequest.isFinished, !loadingRequest.isCancelled else { return }
    
    if let error = error {
      loadingRequest.finishLoading(with: error)
    } else {
      loadingRequest.finishLoading()
    }
  }
  
}

// MARK: - AVAssetResourceLoaderDelegate

extension VideoPlayerResourceLoader: AVAssetResourceLoaderDelegate {
  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    self.processLoadingRequest(loadingRequest)
    return true
  }
  
  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    // Cancel the dataTask associated with the loading request
    self.loadingRequestsMap[loadingRequest]?.cancel()
  }
}
