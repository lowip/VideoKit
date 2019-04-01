//
//  VideoPlayerView.swift
//  VideoKit
//
//  Created by Louis Bur on 3/24/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import UIKit
import AVFoundation

@objcMembers
public class VideoPlayerView: UIView {
  
  // MARK: - Properties
  
  /// The player
  private(set) var player: VideoPlayer?
  
  /// The player requested state
  private var requestedState: VideoPlayerRequestedState = .stopped
  
  /// The url
  public private(set) var url: URL?
  
  /// The cache key
  public private(set) var cacheKey: String?
  
  /// The delegate
  public weak var delegate: VideoPlayerViewDelegate?
  
  /// The queue used to retrieve/remove the player
  private let queue = DispatchQueue(label: "com.videokit.VideoPlayerView", qos: .userInteractive)
  
  /// VideoPlayerPlaybackProtocol (Partial)
  
  public var isMuted: Bool = false {
    didSet {
      guard self.player?.currentPlayerView === self else { return }
      self.player?.isMuted = self.isMuted
    }
  }
  
  public var volume: Float = 1.0 {
    didSet {
      guard self.player?.currentPlayerView === self else { return }
      self.player?.volume = self.volume
    }
  }
  
  public var isLooping: Bool = false {
    didSet {
      guard self.player?.currentPlayerView === self else { return }
      self.player?.isLooping = self.isLooping
    }
  }
  
  var contentLayer = CALayer()
  
  // MARK: - Initializing
  
  /// Initilizes a new `VideoPlayerView`
  ///
  /// - Parameters:
  ///   - url: The url of the media
  ///   - cacheKey: The key to use for the cache, defaults to `url.absoluteString`
  public init(url: URL? = nil, cacheKey: String? = nil) {
    // Super
    super.init(frame: .zero)
    
    // Add contentLayer
    self.layer.addSublayer(self.contentLayer)
    
    // Set the url and cacheKey
    self.set(url: url, cacheKey: cacheKey)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  deinit {
    // Unregister self on the player
    self.player?.unregister(playerView: self)
  }
  
  // MARK: - LifeCycle
  
  public override func didMoveToWindow() {
    super.didMoveToWindow()
    
    // Optimization:
    // We register / unregister self on the player when the window property changes
    guard let player = self.player else { return }
    if self.window != nil, player.currentPlayerView != self {
      // Register the player view when added on new window
      player.register(playerView: self)
    } else if self.window == nil {
      // Unregister the player on next run loop
      // Dispatch async is needed to prevent the player to be stopped when pushing
      // in a navigation controller (as the next view controller is not loaded yet)
      DispatchQueue.main.async { [weak self] in
        guard let `self` = self, self.window == nil else { return }
        player.unregister(playerView: self)
      }
    }
  }
  
  // MARK: - Layout
  
  public override func layoutSubviews() {
    super.layoutSubviews()
    
    // Resize the contentLayer
    let selfBounds = self.layer.bounds
    self.contentLayer.bounds = selfBounds
    self.contentLayer.position = CGPoint(x: selfBounds.width / 2, y: selfBounds.height / 2)
    
    // Resize the AVPlayerLayers
    self.contentLayer.sublayers?
      .filter { $0 is AVPlayerLayer }
      .forEach {
        $0.bounds = self.contentLayer.bounds
        $0.position = CGPoint(x: $0.bounds.width / 2, y: $0.bounds.height / 2)
      }
  }
  
  // MARK: - Public Methods
  
  /// Sets the `url` and `cacheKey` of the player view
  ///
  /// By setting `url` to `nil`, underlying resources will be freed
  ///
  /// - Parameters:
  ///   - url: The url of the media
  ///   - cacheKey: The key to use for the cache, defaults to `url.absoluteString`
  public func set(url: URL?, cacheKey: String? = nil) {
    // Update properties
    self.url = url
    self.cacheKey = cacheKey
    
    self.queue.async {
      // Verify that the url and cacheKey hasn't changed since we queued this closure
      if self.url != url || self.cacheKey != cacheKey { return }
      
      // Unregister self on the player
      self.player?.unregister(playerView: self)
      
      // Reset player if url is nil
      guard let url = url else {
        self.player = nil
        return
      }
      
      // Retrieve player from the manager
      let player = VideoPlayerManager.default.player(for: url, cacheKey: cacheKey)
      
      // Set properties
      self.player = player
      player.register(playerView: self)
    }
  }
  
}

// MARK: - VideoPlayerViewProtocol

extension VideoPlayerView: VideoPlayerViewProtocol {
  
  var visibility: CGFloat {
    // The view must have a window and not be hidden to be visible
    guard let window = self.window, !self.isHidden else {
      return 0.0
    }
    
    // Check superviews until finding one that is hidden
    var superview = self.superview
    while let view = superview {
      if view.isHidden {
        return 0.0
      }
      superview = view.superview
    }
    
    // Convert the frame to the window coordinate system
    let frame = self.convert(self.bounds, to: window)
    let intersection = frame.intersection(window.bounds)
    
    // The rectangles don't intersect
    guard !intersection.isNull else {
      return 0.0
    }
    
    return (intersection.width * intersection.height) / (frame.width * frame.height)
  }
  
  var priority: Int {
    return 500
  }
  
  func didBecomeCurrent(with player: VideoPlayer) {
    // Set properties on player
    player.isMuted = self.isMuted
    player.volume = self.volume
    player.isLooping = self.isLooping
    
    // Update delegate methods
    self.delegate?.videoPlayerView?(self, playerStatusDidChange: player.playerStatus)
    self.delegate?.videoPlayerView?(
      self,
      elapsedSecondsDidChange: player.elapsedSeconds,
      totalSeconds: player.totalSeconds
    )
    if player.elapsedSeconds == player.totalSeconds, player.playerStatus == .paused {
      self.delegate?.videoPlayerViewDidPlayToEnd?(self)
    }
    
    // Nothing to do if we have the same requested state of the player
    guard self.requestedState != player.requestedState else { return }
    
    // Update playback for requested state
    switch self.requestedState {
    case .playing: self.play()
    case .paused: self.pause()
    case .stopped: self.stop()
    }
    
    // Delegate
    self.delegate?.videoPlayerViewDidBecomeCurrent?(self)
  }
  
  func willResignCurrent(from player: VideoPlayer) {
    // Delegate
    self.delegate?.videoPlayerViewWillResignCurrent?(self)
  }
}

// MARK: - VideoPlayerPlaybackProtocol

extension VideoPlayerView: VideoPlayerPlaybackProtocol {
  
  public var rate: Float {
    get { return self.player?.rate ?? .nan }
    set {
      guard let player = self.player, player.currentPlayerView === self else { return }
      player.rate = newValue
    }
  }
  
  public var elapsedSeconds: TimeInterval {
    return self.player?.elapsedSeconds ?? .nan
  }
  
  public var totalSeconds: TimeInterval {
    return self.player?.totalSeconds ?? .nan
  }
  
  public var currentTime: CMTime {
    return self.player?.currentTime ?? CMTime.invalid
  }
  
  public func seek(to time: CMTime, forceResume: Bool) -> Bool {
    guard let player = self.player, player.currentPlayerView === self else { return false }
    return player.seek(to: time, forceResume: forceResume)
  }
  
  public func pause() {
    self.requestedState = .paused
    guard let player = self.player, player.currentPlayerView === self else { return }
    player.pause()
  }
  
  public func play() {
    self.requestedState = .playing
    guard let player = self.player, player.currentPlayerView === self else { return }
    player.play()
  }
  
  public func stop() {
    self.requestedState = .stopped
    guard let player = self.player, player.currentPlayerView === self else { return }
    player.stop()
  }
  
}

// MARK: - VideoPlayerDelegate extension

extension VideoPlayerView: VideoPlayerDelegate {
  
  func videoPlayer(_ videoPlayer: VideoPlayer, statusDidChange status: VideoPlayerStatus) {
    self.delegate?.videoPlayerView?(self, playerStatusDidChange: status)
  }
  
  func videoPlayer(
    _ videoPlayer: VideoPlayer,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  ) {
    self.delegate?.videoPlayerView?(
      self,
      elapsedSecondsDidChange: elapsedSeconds,
      totalSeconds: totalSeconds
    )
  }
  
  func videoPlayerDidPlayToEnd(_ videoPlayer: VideoPlayer) {
    self.delegate?.videoPlayerViewDidPlayToEnd?(self)
  }
  
}

// MARK: - VideoPlayerViewDelegate

@objc(VideoPlayerViewDelegate)
public protocol VideoPlayerViewDelegate: AnyObject {
  
  /// Called when the status of the video player changes
  ///
  /// - Parameters:
  ///   - videoPlayerView: The video player view which `status` changed
  ///   - status: The new `status`
  @objc optional
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    playerStatusDidChange status: VideoPlayerStatus
  )
  
  /// Called when the `elapsedSeconds` of the video player's player item changes
  ///
  /// - Parameters:
  ///   - videoPlayerView: The video player view which `elapsedSeconds` changed
  ///   - elapsedSeconds: The new value for `elapsedSeconds`
  ///   - totalSeconds: The new value for `totalSeconds`
  @objc optional
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  )
  
  /// Called when the player's player item did play to the end
  ///
  /// - Parameters:
  ///   - videoPlayerView: The video player view which played to the end
  @objc optional
  func videoPlayerViewDidPlayToEnd(_ videoPlayerView: VideoPlayerView)
  
  /// Called when the player view becomes current
  ///
  /// VideoPlayerView becomes current when it is the most visible player view
  /// for a specific url/cacheKey tuple
  ///
  /// - Parameters:
  ///   - videoPlayerView: The video player view which became current
  @objc optional
  func videoPlayerViewDidBecomeCurrent(_ videoPlayerView: VideoPlayerView)
  
  /// Called when the player view changes from current to not current
  ///
  /// VideoPlayerView becomes current when it is the most visible player view
  /// for a specific url/cacheKey tuple
  ///
  /// - Parameters:
  ///   - videoPlayerView: The video player view which became current
  @objc optional
  func videoPlayerViewWillResignCurrent(_ videoPlayerView: VideoPlayerView)
  
}

// Default implementation

/*
public extension VideoPlayerViewDelegate {
  
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    playerStatusDidChange status: VideoPlayerStatus
  ) {}
  
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  ) {}
  
  func videoPlayerViewDidPlayToEnd(_ videoPlayerView: VideoPlayerView) {}
  
  func videoPlayerViewDidBecomeCurrent(_ videoPlayerView: VideoPlayerView) {}
  
  func videoPlayerViewWillResignCurrent(_ videoPlayerView: VideoPlayerView) {}
}
*/
