//
//  VideoPlayerManager.swift
//  VideoKit
//
//  Created by Louis Bur on 3/24/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import Foundation
import UIKit

final class VideoPlayerManager {
  
  // MARK: - Singleton
  
  /// Default manager
  static let `default` = VideoPlayerManager(
    queue: DispatchQueue(label: "com.videkit.VideoPlayerManager")
  )
  
  // MARK: - Properties
  
  /// The weak map of video players by cache keys
  private let videoPlayers = NSMapTable<NSString, VideoPlayer>(
    keyOptions: .copyIn, valueOptions: .weakMemory
  )

  // The queue on which operations are processed
  private let queue: DispatchQueue
  
  // MARK: - Initializing
  
  init(queue: DispatchQueue = .main) {
    // Set properties
    self.queue = queue
  }
  
  // MARK: - Public Methods
  
  /// Gets a player for the `url` and optionally the `cacheKey`.
  ///
  /// Try to find an existing player first. If not existing player is found,
  /// creates a new one.
  ///
  /// - Parameters:
  ///   - url: The url of the media
  ///   - cacheKey: The key to use for the cache, defaults to `url.absoluteString`
  ///
  /// - Returns: The player for the `url` / `cacheKey`
  func player(for url: URL, cacheKey: String? = nil) -> VideoPlayer {
    return self.execute(queue: self.queue) {
      // Retrieve the actual cacheKey
      let cacheKey = VideoPlayerModel.cacheKey(with: url, cacheKey: cacheKey)
      
      // Check in the videoPlayers map
      if let videoPlayer = self.videoPlayers.object(forKey: cacheKey as NSString) {
        return videoPlayer
      }
      
      // Create video player and store it in the videoPlayers map
      let videoPlayer = VideoPlayer(url: url, cacheKey: cacheKey)
      self.videoPlayers.setObject(videoPlayer, forKey: cacheKey as NSString)
      
      return videoPlayer
    }
  }
  
  // MARK: - Private Methods
  
  /// Safely executes a `work` closure synchronously on `queue`
  ///
  /// - Parameters:
  ///   - queue: The dispatch queue
  ///   - work: The closure to execute
  ///
  /// - Returns: The result of the `work` closure execution
  private func execute<T>(queue: DispatchQueue, work: () throws -> T) rethrows -> T {
    // When on main thread and the queue is .main, execute directly
    if Thread.isMainThread, queue == .main {
      return try work()
    }
    
    // Execute on queue synchronously
    return try queue.sync(execute: work)
  }
  
}
