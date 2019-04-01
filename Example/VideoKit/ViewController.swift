//
//  ViewController.swift
//  VideoKit
//
//  Created by lowip on 03/31/2019.
//  Copyright (c) 2019 lowip. All rights reserved.
//

import UIKit
import VideoKit

class ViewController: UIViewController {
  
  // MARK: - Properties
  
  private var videoPlayerView: VideoPlayerView!
  
  // MARK: - LifeCycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // VideoPlayerView
    let url = URL(string: "https://giant.gfycat.com/CompleteBareClingfish.mp4")!
    let videoPlayerView = VideoPlayerView(url: url)
    self.videoPlayerView = videoPlayerView
    videoPlayerView.play()
    videoPlayerView.isLooping = true
    videoPlayerView.delegate = self
    
    // Hierarchy
    self.view.addSubview(videoPlayerView)
  }
  
  // MARK: - Layout
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    
    self.videoPlayerView.frame = self.view.bounds
  }
}

extension ViewController: VideoPlayerViewDelegate {
  
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    playerStatusDidChange status: VideoPlayerStatus
  ) {
    print(status)
  }
  
  func videoPlayerView(
    _ videoPlayerView: VideoPlayerView,
    elapsedSecondsDidChange elapsedSeconds: TimeInterval,
    totalSeconds: TimeInterval
  ) {
    
  }
  
  func videoPlayerViewDidPlayToEnd(_ videoPlayerView: VideoPlayerView) {
    print("DID PLAY TO END")
  }
  
}

