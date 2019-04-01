//
//  VideoPlayerModel.swift
//  VideoKit
//
//  Created by Louis Bur on 3/11/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - VideoPlayerModel

class VideoPlayerModel {
  
  // MARK: - Constants
  
  /// The dispatchQueue used for time observation
  static private let timeObserverQueue = DispatchQueue.global(qos: .background)
  
  /// The keys to load before the player item's asset is ready for playback
  static private let keysForPlayback: [String] = ["playable", "duration", "tracks"]
  
  // MARK: - Properties
  
  /// The key used for the cache
  let cacheKey: String

  /// The player item
  let playerItem: AVPlayerItem
  
  /// The resource loader for the player item
  let resourceLoader: VideoPlayerResourceLoader
  
  /// The player responsible for playback
  weak var player: AVPlayer? {
    didSet { self.setupPlayerObservers(player: self.player, previousPlayer: oldValue) }
  }
  
  /// The potential error occuring when loading keys
  private(set) var keyError: Error? {
    didSet {
      if let keyError = self.keyError {
        self.delegate?.videoPlayerModel(self, errorWhenLoadingKeys: keyError)
      }
    }
  }
  
  /// The delegate
  weak var delegate: VideoPlayerModelDelegate?

  /// The flag specifying if the player item's asset is ready for playback
  ///
  /// `isReadyForPlayback` is false until the assets keys aren't loaded
  private(set) var isReadyForPlayback: Bool = false {
    didSet {
      if oldValue != self.isReadyForPlayback {
        self.delegate?.videoPlayerModel(self, isReadyForPlaybackDidChange: self.isReadyForPlayback)
      }
    }
  }
  
  /// The number of seconds elapsed in the video
  private(set) var elapsedSeconds: TimeInterval = .nan
  
  /// The total number of seconds of the video
  private(set) var totalSeconds: TimeInterval = .nan
  
  // MARK: - Observations Properties
  
  private var currentItemObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var itemObservations: [NSKeyValueObservation]?
  private var itemDidEndObserver: NSObjectProtocol?
//  private var itemFailedToPlayToEndObserver: NSObjectProtocol?
  
  // MARK: - Initializing
  
  /// Initializes a VideoPlayerModel
  ///
  /// This initializer will force the use of `VideoPlayerResourceLoader` if the `playerItem` asset is a
  /// `AVURLAsset` and that its url is wrapped
  ///
  /// - Parameters:
  ///   - playerItem: The AVPlayerItem
  ///   - cacheKey: The key to use for the cache
  ///
  /// - Returns: The newly created VideoPlayerModel
  init(playerItem: AVPlayerItem, cacheKey: String) {
    // Set properties
    self.playerItem = playerItem
    self.cacheKey = cacheKey
    self.resourceLoader = VideoPlayerResourceLoader(cacheKey: cacheKey)
    
    // Use the resourceLoader if possible
    if let urlAsset = playerItem.asset as? AVURLAsset, urlAsset.url.isWrapped {
      urlAsset.resourceLoader.setDelegate(self.resourceLoader, queue: .global())
    }
  }
  
  /// Initializes a VideoPlayerModel
  ///
  /// This initializer will force the use of `VideoPlayerResourceLoader` by replacing
  /// url by a url with a fake scheme and possibly a fake path extension (excepted for
  /// hls, see: https://apple.co/2O3KPEB)
  ///
  /// - Parameters:
  ///   - url: The url of the media
  ///   - cacheKey: The key to use for the cache, defaults to `url.absoluteString`
  ///
  /// - Returns: The newly created VideoPlayerModel
  convenience init(url: URL, cacheKey: String? = nil) {
    // Wrap the url
    let wrappedUrl = url.pathExtension != "m3u8" ? url.wrap()! : url
    
    // Create AVURLAsset/AVPlayerItem from wrapped scheme url
    let videoURLAsset = AVURLAsset(url: wrappedUrl)
    let playerItem = AVPlayerItem(asset: videoURLAsset, automaticallyLoadedAssetKeys: nil)
        
    // Initialize player model
    self.init(
      playerItem: playerItem,
      cacheKey: VideoPlayerModel.cacheKey(with: url, cacheKey: cacheKey)
    )
  }
  
  deinit {
    // Remove timeObserver
    if let timeObserver = self.timeObserver {
      self.player?.removeTimeObserver(timeObserver)
    }
    
    // Remove itemDidEndObserver
    if let itemDidEndObserver = self.itemDidEndObserver {
      NotificationCenter.default.removeObserver(itemDidEndObserver)
    }
    
    /*
    // Remove itemFailedToPlayToEndObserver
    if let itemFailedToPlayToEndObserver = self.itemFailedToPlayToEndObserver {
      NotificationCenter.default.removeObserver(itemFailedToPlayToEndObserver)
    }
     */
    
    // Cleanup playerItem
    self.playerItem.cancelPendingSeeks()
    self.playerItem.asset.cancelLoading()
  }
  
  // MARK: - Public Methods
  
  /// Gets the cache key
  ///
  /// If `cacheKey` is `nil`, defaults to `url.absoluteString`
  ///
  /// - Parameters:
  ///   - url: The url
  ///   - cacheKey: The optional cache key to use
  ///
  /// - Returns: The cache key
  class func cacheKey(with url: URL, cacheKey: String?) -> String {
    return cacheKey ?? url.absoluteString
  }
  
  /// Prepares the player model for playback
  ///
  /// Loads the keys specified in `VideoPlayerModel.keysForPlayback` on the player item's
  /// asset.
  func prepareForPlayback() {
    // Nothing to do if already ready
    guard !self.isReadyForPlayback else { return }
    
    // Load keys on the asset
    self.playerItem.asset.loadValuesAsynchronously(forKeys: VideoPlayerModel.keysForPlayback) { [weak self] in
      guard let `self` = self else { return }
      
      // Check keys status
      let asset = self.playerItem.asset
      
      var error: NSError? = nil
      let (success, keyError) = VideoPlayerModel.keysForPlayback.reduce((true, nil)) { tuple, key -> (Bool, Error?) in
        let (success, keyError) = tuple
        let status = asset.statusOfValue(forKey: key, error: &error)
        switch status {
        case .loaded:
          return (success, keyError)
        case .failed:
          return (false, error!)
        default:
          return (false, keyError)
        }
      }
      
      // Update isReadyForPlayback and keyError
      if Thread.isMainThread {
        self.isReadyForPlayback = success
        self.keyError = keyError
      } else {
        DispatchQueue.main.sync {
          self.isReadyForPlayback = success
          self.keyError = keyError
        }
      }
    }
  }
  
  // MARK: - Private Methods
  
  private func setupPlayerObservers(player: AVPlayer?, previousPlayer: AVPlayer?) {
    // Nothing to do if the player didn't change
    guard player !== previousPlayer else { return }
    
    // Setup observers
    // - currentItem
    self.setupCurrentItemObserver(player: player, previousPlayer: previousPlayer)
    // - time
    self.setupTimeObserver(player: player, previousPlayer: previousPlayer)
  }
  
  private func setupCurrentItemObserver(player: AVPlayer?, previousPlayer: AVPlayer?) {
    // Nothing to do if the player didn't change
    guard player !== previousPlayer else { return }
    
    // Reset previous observer
    self.currentItemObservation = nil
    
    // Nothing to do if the player is nil
    guard let player = player else { return }
    
    // Observe the current item
    self.currentItemObservation = player.observe(
      \.currentItem,
      options: [.initial, .old, .new]
    ) { [weak self] player, change in
      self?.setupPlayerItemObservers(
        playerItem: change.newValue ?? nil,
        previousPlayerItem: change.oldValue ?? nil
      )
    }
  }
  
  private func setupTimeObserver(player: AVPlayer?, previousPlayer: AVPlayer?) {
    // Nothing to do if the player didn't change
    guard player !== previousPlayer else { return }
    
    // Remove the timeObserver on the previous player and reset elapsed/total seconds
    if let previousPlayer = previousPlayer, let timeObserver = self.timeObserver {
      previousPlayer.removeTimeObserver(timeObserver)
      self.elapsedSeconds = .nan
      self.totalSeconds = .nan
    }
    
    // Nothing to do if the player is nil
    guard let player = player else { return }
    
    // Add the timeObserver on the new player
    self.timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(
        seconds: 1,
        preferredTimescale: CMTimeScale(NSEC_PER_SEC)
      ),
      queue: VideoPlayerModel.timeObserverQueue
    ) { [weak self] time in
      guard let `self` = self else { return }
      
      // Update elapsed seconds
      self.elapsedSeconds = CMTimeGetSeconds(time)
      
      // Check that we have valid values
      guard self.totalSeconds != 0, !self.totalSeconds.isNaN, self.elapsedSeconds < self.totalSeconds else { return }
      
      // Call delegate on main thread
      DispatchQueue.main.sync { [weak self] in
        guard let `self` = self else { return }
        self.delegate?.videoPlayerModel(
          self,
          elapsedSecondsDidChange: self.elapsedSeconds,
          totalSeconds: self.totalSeconds
        )
      }
    }
  }
  
  private func setupPlayerItemObservers(playerItem: AVPlayerItem?, previousPlayerItem: AVPlayerItem?) {
    // Nothing to do if the player item didn't change
    guard playerItem !== previousPlayerItem else { return }
    
    // Reset previous observers
    self.itemObservations = nil
    
    // Nothing to do if the player item is nil
    guard let playerItem = playerItem else { return }
    
    // Add the kvo observers
    self.itemObservations = [
      // For internal use
      // - duration / totalSeconds
      playerItem.observe(\.duration, options: [.initial, .new]) { [weak self] playerItem, change in
        guard let `self` = self, let duration = change.newValue else { return }
        self.totalSeconds = CMTimeGetSeconds(duration)
      },
      
      // For delegation
      // - status:
      // We check directly on the playerItem instead of `change` due to
      // https://bugs.swift.org/browse/SR-5872
      playerItem.observe(\.status, options: [.initial, .new]) { [weak self] playerItem, change in
        guard let `self` = self else { return }
        self.delegate?.videoPlayerModel(self, statusDidChange: playerItem.status)
      }
    ]
    
    // didPlayToEnd observer
    // - Remove previous observer
    if let itemDidEndObserver = self.itemDidEndObserver {
      NotificationCenter.default.removeObserver(itemDidEndObserver)
    }
    
    // - Add new observer
    self.itemDidEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: playerItem,
      queue: nil
    ) { [weak self] _ in
      guard let `self` = self else { return }
      self.delegate?.videoPlayerModelDidPlayToEnd(self)
    }
    
    /*
    // failedToPlayToEnd observer
    // - Remove previous observer
    if let itemFailedToPlayToEndObserver = self.itemFailedToPlayToEndObserver {
      NotificationCenter.default.removeObserver(itemFailedToPlayToEndObserver)
    }
    
    // - Add new observer
    self.itemFailedToPlayToEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: playerItem,
      queue: nil
    ) { [weak self] notification in
      guard let `self` = self,
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error else { return }
      print("ERRRRRRROOOOOOR", error.localizedDescription)
    }
   */
  }
  
}

// MARK: - VideoPlayerModelDelegate

protocol VideoPlayerModelDelegate: AnyObject {
  
  /// Called when the `status` of the video player model's player item changes
  ///
  /// - Parameters:
  ///   - videoPlayerModel: The video player model which `status` changed
  ///   - status: The new `status`
  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    statusDidChange status: AVPlayerItem.Status
  )
  
  /// Called when the `isReadyForPlayback` of the video player model changes
  ///
  /// `isReadyForPlayback` becomes true when the keys required for playback are loaded
  /// on the player item's asset
  ///
  /// - Parameters:
  ///   - videoPlayerModel: The video player model which `isReadyForPlayback` changed
  ///   - isReadyForPlayback: The new value for `isReadyForPlayback`
  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    isReadyForPlaybackDidChange isReadyForPlayback: Bool
  )
  
  /// Called when the `elapsedSeconds` of the video player model's player item changes
  ///
  /// - Parameters:
  ///   - videoPlayerModel: The video player model which `elapsedSeconds` changed
  ///   - elapsedSeconds: The new value for `elapsedSeconds`
  ///   - totalSeconds: The value for `totalSeconds`
  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  )
  
  /// Called when the player model's player item did play to the end
  ///
  /// - Parameters:
  ///   - videoPlayerModel: The video player model which played to the end
  func videoPlayerModelDidPlayToEnd(
    _ videoPlayerModel: VideoPlayerModel
  )
  
  /// Called when an error occurs while preparing for playback
  ///
  /// - Parameters:
  ///   - videoPlayerModel: The video player model on which `error` occured
  ///   - error: The error
  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    errorWhenLoadingKeys error: Error
  )
  
  
}

