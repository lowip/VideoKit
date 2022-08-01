import Foundation

extension VideoCache {

  final class DataEntry {

    // MARK: - Properties

    var lastAccessDate: Date
    var fileSize: UInt64
    var offset: UInt64

    private var range: Range<UInt64> { offset..<(offset + fileSize) }

    // MARK: - Initialization

    init(lastAccessDate: Date, fileSize: UInt64, offset: UInt64) {
      self.lastAccessDate = lastAccessDate
      self.fileSize = fileSize
      self.offset = offset
    }

    // MARK: - Public Methods

    func contains(_ range: Range<UInt64>) -> Bool {
      self.range.contains(range)
    }

    func overlaps(_ range: Range<UInt64>) -> Bool {
      self.range.overlaps(range)
        || self.range.upperBound == range.lowerBound
        || self.range.lowerBound == range.upperBound
    }

  }

}

extension VideoCache.DataEntry: Codable {}
extension VideoCache.DataEntry: Equatable {

  static func == (lhs: VideoCache.DataEntry, rhs: VideoCache.DataEntry) -> Bool {
    lhs.fileSize == rhs.fileSize
      && lhs.offset == rhs.offset
  }

}

extension Range {

  func contains(_ other: Range) -> Bool {
    return self.lowerBound <= other.lowerBound && self.upperBound >= other.upperBound
  }

}
