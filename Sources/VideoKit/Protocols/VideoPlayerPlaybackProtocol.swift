import AVFoundation

public protocol VideoPlayerPlaybackProtocol {
  /// The playback rate
  var rate: Float { get set }

  /// The muted state
  var isMuted: Bool { get set }

  /// The audio playback volume, ranging from 0.0 through 1.0 on a linear scale.
  var volume: Float { get set }

  /// The number of seconds elapsed in the video
  var elapsedSeconds: TimeInterval { get }

  /// The total number of seconds of the video
  var totalSeconds: TimeInterval { get }

  /// The current time in the video
  var currentTime: CMTime { get }

  /// The looping behavior
  var isLooping: Bool { get set }

  /// Seek the playback cursor to a specific time
  ///
  /// - Parameters:
  ///   - time: The time to which seek
  ///   - forceResume: Force the player to resume, when `false` the player
  ///                  resumes playback only if it was already playing before
  ///
  /// - Returns: The result of moving the playback cursor, true if successful,
  ///            false otherwise
  func seek(to time: CMTime, forceResume: Bool) -> Bool

  /// Pause the playback of the video
  func pause()

  /// Resume the playback of the video
  func play()

  /// Stop the playback of the video
  func stop()
}
