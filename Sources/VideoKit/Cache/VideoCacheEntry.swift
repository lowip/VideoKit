import Foundation

extension VideoCache {

  final class Entry {

    // MARK: - Properties

    let contentType: String
    let contentLength: UInt64
    var dataEntries: [DataEntry] = []

    // MARK: - Initialization

    init(contentType: String, contentLength: UInt64, dataEntries: [VideoCache.DataEntry] = []) {
      self.contentType = contentType
      self.contentLength = contentLength
      self.dataEntries = dataEntries
    }

    // MARK: - Public Methods

    func dataEntry(containing range: Range<UInt64>) -> DataEntry? {
      dataEntries.first { $0.contains(range) }
    }

    func dataEntries(overlapping range: Range<UInt64>) -> [DataEntry] {
      dataEntries.filter { $0.overlaps(range) }
    }

  }

}

extension VideoCache.Entry: Codable {}
