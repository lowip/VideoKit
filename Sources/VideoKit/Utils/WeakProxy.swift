import Foundation

class WeakProxy: NSObject {

  // MARK: - Properties

  private weak var target: AnyObject?

  // MARK: - Initializing

  init(_ target: AnyObject) {
    self.target = target
    super.init()
  }

  // MARK: - NSObjectProtocol

  override func responds(to aSelector: Selector!) -> Bool {
    return (self.target?.responds(to: aSelector) ?? false) || super.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    return self.target
  }
}
