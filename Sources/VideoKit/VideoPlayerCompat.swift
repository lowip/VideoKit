import Foundation

@objc
public enum VideoPlayerStatus: Int {
  case unknown
  case buffering
  case readyToPlay
  case playing
  case paused
  case stopped
  case failed
}

enum VideoPlayerRequestedState {
  case playing
  case paused
  case stopped
}
