import UIKit

protocol VideoPlayerViewProtocol {

  /// The visibility of the player view
  ///
  /// A value between `0.0` (not visible) and `1.0` (fully visible)
  var visibility: CGFloat { get }

  /// The priority of the player view
  ///
  /// TODO: Start using it
  var priority: Int { get }

  /// The layer in which the player layer is added
  var contentLayer: CALayer { get }

  /// Called by the `player` right after the player view becoming current
  func didBecomeCurrent(with player: VideoPlayer)

  /// Called by the `player` right before the player view resigning current
  func willResignCurrent(from player: VideoPlayer)
}
