//
//  VideoPlayerCompat.swift
//  VideoKit
//
//  Created by Louis Bur on 3/11/19.
//  Copyright © 2019 Fugucam. All rights reserved.
//

import Foundation

public enum VideoPlayerStatus {
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
