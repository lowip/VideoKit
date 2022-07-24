import AVFoundation

// MARK: - VideoPlayer

@objc
final class VideoPlayer: NSObject {

  // MARK: - Constants

  private static let playerPool = ObjectPool<AVQueuePlayer>(
    constructor: AVQueuePlayer.init,
    reset: {
      $0.cancelPendingPrerolls()
      $0.removeAllItems()
    },
    resetQueue: DispatchQueue(label: "com.videokit.ObjectPool<AVQueuePlayer>")
  )

  private static let playerLayerPool = ObjectPool<AVPlayerLayer>(
    constructor: {
      let layer = AVPlayerLayer(player: nil)
      layer.actions = [
        "onOrderIn": NSNull(),
        "onOrderOut": NSNull(),
        "sublayers": NSNull(),
        "contents": NSNull(),
        "bounds": NSNull(),
        "position": NSNull(),
      ]
      return layer
    },
    reset: {
      $0.removeFromSuperlayer()
      $0.player = nil
    },
    resetQueue: DispatchQueue(label: "com.videokit.ObjectPool<AVPlayerLayer>")
  )

  // MARK: - Properties

  /// The player model
  private(set) var playerModel: VideoPlayerModel?

  /// A flag used to prevent building the player model multiple times
  ///
  /// Building the player model is an asynchronous operation, we need this
  /// flag to prevent reentry
  private var isBuildingPlayerModel = false

  /// The player current status
  private(set) var playerStatus: VideoPlayerStatus = .unknown {
    didSet {
      guard oldValue != self.playerStatus else { return }

      // Update looping behavior
      self.updateLoopingBehavior()

      // Update visibility display link
      self.updateVisibilityDisplayLinkState()

      // Inform delegate
      self.delegate?.videoPlayer(self, statusDidChange: self.playerStatus)
    }
  }

  /// The error if available
  var error: Error? {
    return self.playerModel?.keyError ?? self.playerModel?.playerItem.error
  }

  /// The player requested state
  private(set) var requestedState: VideoPlayerRequestedState = .stopped

  /// The underlying player
  private let player = VideoPlayer.playerPool.get()

  /// The player layer
  lazy var playerLayer = VideoPlayer.playerLayerPool.get()

  /// The player looper
  private var playerLooper: AVPlayerLooper?

  /// The player views associated with the player
  var playerViews = NSHashTable<VideoPlayerView>.weakObjects()

  /// The current player view used for render
  private(set) weak var currentPlayerView: VideoPlayerView?

  /// The url currently loaded
  var url: URL?

  /// The current cache key
  private var cacheKey: String?

  /// The looping behavior
  var isLooping = false {
    didSet {
      guard oldValue != self.isLooping else { return }

      // Update looping behavior
      self.updateLoopingBehavior()
    }
  }

  /// The delegate
  weak var delegate: VideoPlayerDelegate?

  /// The display link to update the current player view
  ///
  /// Runs at 10 fps when the video is playing, otherwise runs at 4 fps.
  /// When only one playerView is registered, the display link is paused
  private var visibilityDisplayLink: CADisplayLink!

  /// The process queue on which most AVPlayer related operations are performed
  ///
  /// ⚠️ This queue is and needs to stay serial
  private let processQueue = DispatchQueue(
    label: "com.videokit.VideoPlayer",
    qos: .userInteractive
  )

  // MARK: - Observation Properties

  /// An array of kvo observations on the AVPlayer
  ///
  /// On deinit, the observers are automatically removed
  private var playerObservations: [NSKeyValueObservation]?

  /// A flag used to prevent setting the observers multiple times
  ///
  /// Setting the observers is an asynchronous operation, we need this
  /// flag to prevent reentry
  private var isSettingPlayerObservers = false

  // MARK: - Initializing

  init(url: URL? = nil, cacheKey: String? = nil) {
    // Super
    super.init()

    // Set url if available
    if let url = url {
      self.set(url: url, cacheKey: cacheKey)
    }

    // Setup visibility display link
    // We use a `WeakProxy` for `self` as `CADisplayLink` retains the target
    let visibilityDisplayLink = CADisplayLink(
      target: WeakProxy(self), selector: #selector(self.updateCurrentPlayerView))
    visibilityDisplayLink.isPaused = true
    visibilityDisplayLink.preferredFramesPerSecond = 4
    visibilityDisplayLink.add(to: .main, forMode: .common)
    self.visibilityDisplayLink = visibilityDisplayLink
  }

  deinit {
    // Add the player and playerLayer to the pools
    VideoPlayer.playerPool.add(self.player)
    VideoPlayer.playerLayerPool.add(self.playerLayer)

    // Invalidate visibility display link
    self.visibilityDisplayLink.invalidate()
  }

  // MARK: - Public Methods

  func set(url: URL, cacheKey: String? = nil) {
    // Nothing to do if the url or cacheKey hasn't changed
    if self.url == url && self.cacheKey == cacheKey && self.playerModel != nil {
      return
    }

    // Set properties
    self.url = url
    self.cacheKey = cacheKey

    // Build player model
    self.buildPlayerModel()
  }

  func register(playerView: VideoPlayerView) {
    // Add the player view to the list of player views
    self.playerViews.add(playerView)

    // Update visibility display link
    self.updateVisibilityDisplayLinkState()

    // Update the current player view
    if Thread.isMainThread {
      self.updateCurrentPlayerView()
    } else {
      DispatchQueue.main.sync(execute: self.updateCurrentPlayerView)
    }
  }

  func unregister(playerView: VideoPlayerView) {
    // Remove the player view from the list of player views
    self.playerViews.remove(playerView)

    // Update visibility display link
    self.updateVisibilityDisplayLinkState()

    // Update the current player view
    if Thread.isMainThread {
      self.updateCurrentPlayerView()
    } else {
      DispatchQueue.main.sync(execute: self.updateCurrentPlayerView)
    }
  }

  // MARK: - Private Methods

  private func buildPlayerModel() {
    guard let url = self.url, !self.isBuildingPlayerModel else { return }

    // Set flag to true
    self.isBuildingPlayerModel = true

    // Reset previous player model
    self.playerModel?.player = nil
    self.playerModel?.delegate = nil

    self.processQueue.async {
      // Create new playerModel
      let playerModel = VideoPlayerModel(url: url, cacheKey: self.cacheKey)

      // Setup playerModel
      playerModel.player = self.player
      playerModel.delegate = self
      self.playerModel = playerModel

      // Refresh looping behavior
      //    self.setupWithLoopingBehavior(self.loopingBehavior)

      self.isBuildingPlayerModel = false
    }
  }

  private func updateLoopingBehavior() {
    guard self.playerStatus == .playing || self.playerStatus == .paused else { return }

    if self.isLooping {
      self.player.actionAtItemEnd = .advance
    } else {
      self.player.actionAtItemEnd = .pause
    }
  }

  private func updateVisibilityDisplayLinkState() {
    // Pause the visibility display link when no player views are registered
    self.visibilityDisplayLink.isPaused = self.playerViews.count == 0

    // Update framerate
    self.visibilityDisplayLink.preferredFramesPerSecond = self.playerStatus == .playing ? 10 : 4
  }

  @objc private func updateCurrentPlayerView() {
    // Find the most visible player view
    let (currentPlayerView, _) =
      self.playerViews.allObjects
      .map { (view: $0, visibility: $0.visibility) }
      .filter { $0.visibility > 0 }
      .sorted { $0.visibility > $1.visibility }
      .first ?? (view: nil, visibility: 0.0)

    // Stop and remove layer if not visible
    if currentPlayerView == nil {
      if self.playerStatus != .stopped { self.stop() }
      self.playerLayer.removeFromSuperlayer()
    }

    // Nothing more to do if the current player view hasn't changed
    guard self.currentPlayerView !== currentPlayerView else { return }

    // Inform self.currentPlayerView that it resigned current
    self.currentPlayerView?.willResignCurrent(from: self)

    // Attach the playerLayer to the current player view
    currentPlayerView?.contentLayer.insertSublayer(self.playerLayer, at: 0)
    currentPlayerView?.setNeedsLayout()

    // Update property
    self.currentPlayerView = currentPlayerView

    // Set the delegate on the current player view
    self.delegate = currentPlayerView

    // Inform currentPlayerView that it became current
    currentPlayerView?.didBecomeCurrent(with: self)
  }

  private func setupObservers() {
    // Nothing to do if playerObservations already exist or we are currently setting
    // the observers
    if self.playerObservations != nil || self.isSettingPlayerObservers { return }

    // Set flag to true
    self.isSettingPlayerObservers = true

    self.processQueue.async {
      // Setup kvo observers
      self.playerObservations = [
        // - timeControlStatus
        // We check directly on the `player` instead of `change` due to
        // https://bugs.swift.org/browse/SR-5872
        self.player.observe(\.timeControlStatus, options: [.initial, .new]) {
          [weak self] player, change in
          guard let `self` = self else { return }

          // Update player status depending of the timeControlStatus
          switch player.timeControlStatus {
          case .playing:
            self.playerStatus = .playing
          case .waitingToPlayAtSpecifiedRate:
            guard let reason = player.reasonForWaitingToPlay,
              reason == .toMinimizeStalls
            else { break }
            self.playerStatus = .buffering
          default:
            break
          }
        }
      ]

      // Set flag to false
      self.isSettingPlayerObservers = false
    }
  }

}

// MARK: - VideoPlayerPlaybackProtocol extension

extension VideoPlayer: VideoPlayerPlaybackProtocol {
  var rate: Float {
    get { return self.player.rate }
    set { self.player.rate = newValue }
  }

  var isMuted: Bool {
    get { return self.player.isMuted }
    set { self.player.isMuted = newValue }
  }

  var volume: Float {
    get { return self.player.volume }
    set { self.player.volume = newValue }
  }

  var elapsedSeconds: TimeInterval {
    return self.playerModel?.elapsedSeconds ?? .nan
  }

  var totalSeconds: TimeInterval {
    return self.playerModel?.totalSeconds ?? .nan
  }

  var currentTime: CMTime {
    return self.player.currentTime()
  }

  @discardableResult
  func seek(to time: CMTime, forceResume: Bool) -> Bool {
    guard self.playerModel != nil, time.isValid else {
      return false
    }

    guard self.playerStatus != .unknown, self.playerStatus != .failed, self.playerStatus != .stopped
    else {
      return false
    }

    let needResume = self.rate != 0 || forceResume
    self.pause()

    self.player.seek(to: time) { [weak self] finished in
      guard finished, needResume else { return }
      self?.play()
    }

    return true
  }

  func pause() {
    // Update requested state
    self.requestedState = .paused

    self.processQueue.async { [weak self] in
      guard let `self` = self,
        self.requestedState == .paused,
        self.playerStatus != .paused
      else { return }

      // Pause
      self.player.pause()

      // Update status
      self.playerStatus = .paused
    }
  }

  func play() {
    // Update requested state
    self.requestedState = .playing

    // If the video player was stopped, we need to rebuild the player model
    if self.playerModel == nil, self.url != nil {
      self.buildPlayerModel()
    }

    self.processQueue.async { [weak self] in
      guard let `self` = self,
        self.requestedState == .playing
      else { return }

      // Nothing to do if no playerModel has been set
      guard let playerModel = self.playerModel else { return }

      // Starts playback immediately if player model ready
      if playerModel.isReadyForPlayback == true {
        // Setup observers if needed
        self.setupObservers()

        // Set player on playerLayer if needed
        if self.playerLayer.player != self.player {
          self.playerLayer.player = self.player
        }

        self.player.play()

        // Set the current item if needed
        if self.player.currentItem?.asset != playerModel.playerItem.asset {
          self.playerLooper = AVPlayerLooper(
            player: self.player,
            templateItem: playerModel.playerItem
          )
        }
        return
      }

      // Prepare the player model for playback
      // Playback will start automatically if `self.requestedState == .playing`
      playerModel.prepareForPlayback()
    }
  }

  func stop() {
    // Update requested state
    self.requestedState = .stopped

    self.processQueue.async { [weak self] in
      guard let `self` = self,
        self.requestedState == .stopped,
        self.playerStatus != .stopped
      else { return }

      // Pause
      self.player.pause()

      // Remove current item and reset playerModel
      self.player.cancelPendingPrerolls()
      self.player.removeAllItems()
      self.playerModel = nil

      // Update status
      self.playerStatus = .stopped
    }
  }
}

// MARK: - VideoPlayerModelDelegate extension

extension VideoPlayer: VideoPlayerModelDelegate {
  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    statusDidChange status: AVPlayerItem.Status
  ) {
    switch status {
    case .unknown:
      self.playerStatus = .unknown
    case .readyToPlay:
      self.playerStatus = .readyToPlay
    case .failed:
      self.playerStatus = .failed
    @unknown default:
      self.playerStatus = .unknown
    }
  }

  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    errorWhenLoadingKeys error: Error
  ) {
    // Update status to failed
    self.playerStatus = .failed
  }

  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    isReadyForPlaybackDidChange isReadyForPlayback: Bool
  ) {
    // Resume playback if needed
    guard self.playerModel === videoPlayerModel,
      self.requestedState == .playing,
      isReadyForPlayback
    else {
      return
    }

    self.play()
  }

  func videoPlayerModel(
    _ videoPlayerModel: VideoPlayerModel,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  ) {
    self.delegate?.videoPlayer(
      self,
      elapsedSecondsDidChange: elapsedSeconds,
      totalSeconds: totalSeconds
    )
  }

  func videoPlayerModelDidPlayToEnd(_ videoPlayerModel: VideoPlayerModel) {
    // Update status to .paused if self.isLooping is false
    if !self.isLooping {
      self.requestedState = .paused
      self.playerStatus = .paused
    }

    // Delegate
    self.delegate?.videoPlayerDidPlayToEnd(self)
  }
}

// MARK: - VideoPlayerDelegate

protocol VideoPlayerDelegate: AnyObject {

  /// Called when the status of the video player changes
  ///
  /// - Parameters:
  ///   - videoPlayer: The video player which `status` changed
  ///   - status: The new `status`
  func videoPlayer(_ videoPlayer: VideoPlayer, statusDidChange status: VideoPlayerStatus)

  /// Called when the `elapsedSeconds` of the video player's player item changes
  ///
  /// - Parameters:
  ///   - videoPlayer: The video player which `elapsedSeconds` changed
  ///   - elapsedSeconds: The new value for `elapsedSeconds`
  ///   - totalSeconds: The value for `totalSeconds`
  func videoPlayer(
    _ videoPlayer: VideoPlayer,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  )

  /// Called when the player's player item did play to the end
  ///
  /// - Parameters:
  ///   - videoPlayer: The video player which played to the end
  func videoPlayerDidPlayToEnd(_ videoPlayer: VideoPlayer)
}
