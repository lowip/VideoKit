import Foundation

final class ObjectPool<T: Hashable> {

  // MARK: - Constants

  /// The default capacity of the pool
  private static var defaultCapacity: Int {
    return 8
  }

  // MARK: - Properties

  /// A constructor function used to build the object instances
  private let constructor: () -> T

  /// A function used to reset the object when added to the pool
  private let reset: ((T) -> Void)?

  /// The max number of items in the pool
  private let capacity: Int

  /// The actual pool
  private var objects: Set<T>

  /// The queue on which items are removed/added
  private let queue: DispatchQueue

  /// The queue on which items are reset
  private let resetQueue: DispatchQueue

  // MARK: - Initializing

  /// Creates an ObjectPool
  ///
  /// - Parameters:
  ///   - constructor: The constructor function to build the object if none available in the pool
  ///   - reset: The reset function executed when an object is added back to the pool
  ///   - capacity: The max number of item in the pool
  ///   - queue: The queue used to process the pool
  ///   - resetQueue: The queue used when resetting the object added
  init(
    constructor: @escaping () -> T,
    reset: ((T) -> Void)? = nil,
    capacity: Int = ObjectPool.defaultCapacity,
    queue: DispatchQueue = .main,
    resetQueue: DispatchQueue = .main
  ) {
    // Create the set of objects for the capacity
    self.constructor = constructor
    self.reset = reset
    self.capacity = capacity
    self.objects = Set(minimumCapacity: capacity)

    // Set the queues
    self.queue = queue
    self.resetQueue = resetQueue
  }

  // MARK: - Public Methods

  /// Gets an item from the pool
  ///
  /// If the pool is empty, it will use the `constructor` to create a new item
  /// and return it
  ///
  /// - Returns: An item
  func get() -> T {
    return self.execute(queue: self.queue) {
      // Check in the pool
      if let object = self.objects.randomElement() {
        // Remove it from the pool and return it
        self.objects.remove(object)
        return object
      }

      // Create a new object
      let object = self.constructor()
      return object
    }
  }

  /// Adds an item to the pool
  ///
  /// If the pool is at max capacity, the items is not added to the pool.
  /// Before adding the item to the pool, this method will execute the
  /// `reset` closure on the item if available
  ///
  /// - Parameters:
  ///   - object: The item to add to the pool
  func add(_ object: T) {
    self.resetQueue.async {
      // Reset
      self.reset?(object)

      self.execute(queue: self.queue) {
        // We don't add the object to the pool if we're at max capacity
        guard self.objects.count < self.capacity else { return }

        // Add it to the pool
        self.objects.insert(object)
      }
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
