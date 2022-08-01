import Foundation
import UIKit

public final class VideoCache {

  public static var main: VideoCache = {
    let cacheURL = try! FileManager.default
      .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
      .appendingPathComponent("com.videokit.VideoCache")

    return VideoCache(
      byteLimit: 50 * 1024 * 1024,
      singleFileByteLimit: 5 * 1024 * 1024,
      cacheURL: cacheURL
    )
  }()

  // MARK: - Types

  typealias Manifest = [String: Entry]
  public typealias Metadata = (contentType: String, contentLength: UInt64)

  private enum LockCondition: Int {
    case notReady
    case ready
  }

  // MARK: - Properties

  private(set) public var byteCount: UInt64 = 0

  public let byteLimit: UInt64
  public let singleFileByteLimit: UInt64
  public let cacheURL: URL

  private var manifestURL: URL { cacheURL.appendingPathComponent("manifest.json") }
  private var manifest: Manifest = [:]

  private let syncLock = NSConditionLock(condition: LockCondition.notReady.rawValue)
  private let queue = DispatchQueue(label: "com.videokit.VideoCache")
  private var sub: AnyObject!

  // MARK: - Initialization

  public init(byteLimit: UInt64, singleFileByteLimit: UInt64, cacheURL: URL) {
    self.byteLimit = byteLimit
    self.singleFileByteLimit = singleFileByteLimit
    self.cacheURL = cacheURL

    sync()

    NotificationCenter.default
      .addObserver(
        self,
        selector: #selector(resignActive),
        name: UIApplication.willResignActiveNotification,
        object: nil
      )
  }

  private func sync() {
    queue.async { [weak self] in
      guard let self = self else { return }

      // Lock all operations until initial sync is complete
      self.syncLock.lock(whenCondition: LockCondition.notReady.rawValue)
      defer { self.syncLock.unlock(withCondition: LockCondition.ready.rawValue) }

      //
      try! FileManager.default.createDirectory(at: self.cacheURL, withIntermediateDirectories: true)
      try! self.synchronizeManifest()
    }
  }

  // MARK: - LifeCycle

  @objc
  private func resignActive() {
    lock(); defer { unlock() }
    saveManifest()
  }

  // MARK: - Cache Methods

  public func get(key: String, range: Range<UInt64>, completion: @escaping ((Data, Metadata)?) -> Void) {
    queue.async { [weak self] in
      guard let self = self else { return }
      let result = self.getSync(key: key, range: range)
      DispatchQueue.main.async {
        completion(result)
      }
    }
  }

  public func set(
    data: Data,
    key: String,
    offset: UInt64,
    metadata: Metadata? = nil,
    completion: (() -> Void)? = nil
  ) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.setSync(data: data, key: key, offset: offset, metadata: metadata)
      if let completion = completion {
        DispatchQueue.main.async {
          completion()
        }
      }
    }
  }

  public func clear() {
    lock(); defer { unlock() }

    // Clear manifest
    manifest = [:]

    // Clear disk
    try? FileManager.default.removeItem(at: cacheURL)
    try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

    // Update byte count
    updateByteCount()
  }

  // MARK: - Cache Methods (Sync)

  func getSync(key: String, range: Range<UInt64>) -> (Data, Metadata)? {
    lock(); defer { unlock() }

    let stableKey = stableKey(for: key)

    // Check if we have an entry in the manifest, otherwise return nil
    guard let entry = manifest[stableKey] else { return nil }

    // Check if we have a dataEntry containing the range, otherwise return nil
    guard let dataEntry = entry.dataEntry(containing: range) else { return nil }

    // Update lastAccessDate
    dataEntry.lastAccessDate = Date()

    let fileURL = fileURL(for: stableKey, offset: dataEntry.offset)
    let fileHandle = try! FileHandle(forReadingFrom: fileURL)
    fileHandle.seek(toFileOffset: range.lowerBound - dataEntry.offset)
    let data = fileHandle.readData(ofLength: range.count)

    // Check if we successfully read the data
    guard data.count > 0 else { return .none }

    return (data, (entry.contentType, entry.contentLength))
  }

  func setSync(data: Data, key: String, offset: UInt64, metadata: Metadata?) {
    lock(); defer { unlock() }
    let stableKey = stableKey(for: key)

    // Handle singleFileByteLimit
    let fileSize = min(UInt64(data.count), singleFileByteLimit)
    let subdata = data.subdata(in: 0..<Int(fileSize))

    // Create range
    let range: Range<UInt64> = offset..<(offset + fileSize)

    if let entry = manifest[stableKey] {
      // Check if we can skip (already have the data)
      if entry.dataEntry(containing: range) != nil {
        return
      }

      // Create the entry to be saved
      let dataEntry = DataEntry(lastAccessDate: Date(), fileSize: fileSize, offset: offset)

      // Check if we need to merge
      let overlappingDataEntries = entry.dataEntries(overlapping: range)
      if overlappingDataEntries.count > 0 {
        let dataEntriesToMerge = overlappingDataEntries + [dataEntry]
        mergeEntries(dataEntries: dataEntriesToMerge, newDataEntry: dataEntry, data: subdata, key: stableKey)
      } else {
        // Check if we can skip creating a new file (already have singleFileByteLimit data for this key)
        let skipFileCreation = entry.dataEntries.contains { $0.fileSize >= singleFileByteLimit }
        if skipFileCreation { return }

        // Save to file
        saveToFile(dataEntry: dataEntry, data: subdata, key: stableKey, metadata: metadata)
      }
    } else {
      // Save to file
      let dataEntry = DataEntry(lastAccessDate: Date(), fileSize: fileSize, offset: offset)
      saveToFile(dataEntry: dataEntry, data: subdata, key: stableKey, metadata: metadata)
    }

    // Trim
    unlock()
    trimSync()
    lock()
  }

  private func trimSync() {
    lock(); defer { unlock() }

    // Nothing to do if the cache is not bigger than the limit
    if byteCount <= byteLimit { return }

    // Get all the dataEntries sorted by lastAccessDate
    let dataEntries = manifest
      .reduce([]) { p, c -> [(String, DataEntry)] in p + c.value.dataEntries.map { (c.key, $0) } }
      .sorted { $0.1.lastAccessDate < $1.1.lastAccessDate }

    // Remove dataEntries until we are below the limit
    var afterByteCount = byteCount
    for (key, dataEntry) in dataEntries {
      // - Calculate the size after removal
      afterByteCount -= dataEntry.fileSize

      // Remove the file
      let fileURL = fileURL(for: key, offset: dataEntry.offset)
      try? FileManager.default.removeItem(at: fileURL)

      // Remove from the manifest
      let entry = manifest[key]!
      entry.dataEntries.remove(at: entry.dataEntries.firstIndex(of: dataEntry)!)

      // As soon as we are under the byteLimit, break
      if afterByteCount <= byteLimit {
        break
      }
    }
  }

  // MARK: - Manifest

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    #if DEBUG
    var formatting: JSONEncoder.OutputFormatting = .prettyPrinted
    if #available(iOS 11, *) { formatting.formUnion(.sortedKeys) }
    if #available(iOS 13, *) { formatting.formUnion(.withoutEscapingSlashes) }
    encoder.outputFormatting = formatting
    #endif
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private func loadManifest() -> Manifest {
    do {
      let data = try Data(contentsOf: manifestURL)
      let manifest = try Self.decoder.decode(Manifest.self, from: data)
      return manifest
    } catch {
      return [:]
    }
  }

  private func saveManifest() {
    try? Self.encoder.encode(manifest)
      .write(to: manifestURL)
  }

  private func synchronizeManifest() throws {
    // Load manifest
    manifest = loadManifest()

    // Retrieve files in cache
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
    let files = try FileManager.default.contentsOfDirectory(
      at: cacheURL,
      includingPropertiesForKeys: Array(keys),
      options: .skipsHiddenFiles
    )
      .filter { $0 != manifestURL }

    let filenames = files.map { $0.lastPathComponent }
    // Remove elements that does not exist on disk from the manifest
    for (key, entry) in manifest {
      entry.dataEntries = entry.dataEntries.filter {
        let filename = fileURL(for: key, offset: $0.offset).lastPathComponent
        return filenames.contains(filename)
      }
      // Delete the entry if there are no files
      if entry.dataEntries.count == 0 {
        manifest[key] = nil
      }
    }

    // Add files that exist on disk but not in the manifest to the manifest
    for fileURL in files {
      // Get the offset from the url
      let offset = try offset(for: fileURL)
      let fileKey = key(for: fileURL)
      let entry = manifest[fileKey]

      // Check that we need to process this fileURL
      if (entry?.dataEntries.contains { $0.offset == offset }) == true { continue }

      // Retrieve infos
      let resources = try fileURL.resourceValues(forKeys: keys)
      let date = resources.contentModificationDate!
      let fileSize = UInt64(resources.totalFileAllocatedSize!)

      // Add to the manifest if there is already an entry
      if let entry = entry {
        entry.dataEntries.append(DataEntry(lastAccessDate: date, fileSize: fileSize, offset: offset))
      } else {
        // Delete file
        try? FileManager.default.removeItem(at: fileURL)
      }
    }

    // Update byteCount
    updateByteCount()
  }

  private func stableKey(for key: String) -> String {
    key.sha256()
  }

  private func offset(for url: URL) throws -> UInt64 {
    return UInt64(try url
      .absoluteString
      .replacing(pattern: ".*~(\\d+)$", with: "$1")
    )!
  }

  private func fileURL(for key: String, offset: UInt64) -> URL {
    let fileName = "\(key)~\(offset)"
    return self.cacheURL.appendingPathComponent(fileName, isDirectory: false)
  }

  private func key(for fileURL: URL) -> String {
    let fileName = try! fileURL
      .deletingPathExtension()
      .lastPathComponent
      .replacing(pattern: "(.*)~\\d+$", with: "$1")
    return fileName
  }

  private func updateByteCount() {
    byteCount = manifest.values.reduce(0) {
      $0 + $1.dataEntries.reduce(0) { $0 + $1.fileSize }
    }
  }

  private func lock() {
    syncLock.lock(whenCondition: LockCondition.ready.rawValue)
  }

  private func unlock() {
    syncLock.unlock(withCondition: LockCondition.ready.rawValue)
  }

  // MARK: - FileSystem

  private func saveToFile(
    dataEntry: DataEntry,
    data: Data,
    key: String,
    metadata: Metadata?
  ) {
    let fileURL = fileURL(for: key, offset: dataEntry.offset)

    // Create the file
    FileManager.default.createFile(atPath: fileURL.path, contents: data)

    // Update entry
    if let entry = manifest[key] {
      entry.dataEntries.append(dataEntry)
    } else if let (contentType, contentLength) = metadata {
      let entry = Entry(contentType: contentType, contentLength: contentLength)
      entry.dataEntries.append(dataEntry)
      manifest[key] = entry
    } else {
      fatalError("No manifest entry, no metadata, unable to create an entry")
    }

    // Update byteCount
    updateByteCount()
  }

  private func mergeEntries(
    dataEntries: [DataEntry],
    newDataEntry: DataEntry,
    data: Data,
    key: String
  ) {
    let entry = manifest[key]!
    // We merge all the entries in the entry with the lowest offset
    var sortedDataEntries = dataEntries.sorted { $0.offset < $1.offset }
    let firstDataEntry = sortedDataEntries.removeFirst()
    let fileURL = fileURL(for: key, offset: firstDataEntry.offset)

    // Create file if it does not exist (case where newDataEntry is the firstDataEntry)
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: data)
    }

    // Check firstDataEntry for singleFileByteLimit
    guard firstDataEntry.fileSize < singleFileByteLimit else {
      // Delete all the other overlapping files and entries
      sortedDataEntries.forEach {
        // Remove from manifest
        if let entryIndex = entry.dataEntries.firstIndex(of: $0) {
          entry.dataEntries.remove(at: entryIndex)
          // Remove from disk
          let fileURL = self.fileURL(for: key, offset: $0.offset)
          try? FileManager.default.removeItem(at: fileURL)
        }
      }
      return
    }

    // Get file handle
    let fileHandle = try! FileHandle(forUpdating: fileURL)

    // We iterate on all the remaining sortedDataEntries (all overlapping entries minus the first dataEntry) to append
    // the data of each entry to the file (within singleFileByteLimit)
    var fileSize: UInt64 = firstDataEntry.fileSize
    for (i, dataEntry) in sortedDataEntries.enumerated() {
      // Seek to the right offset
      fileHandle.seek(toFileOffset: dataEntry.offset - firstDataEntry.offset)

      // Check if we need to write a patial data
      let nextSize = (dataEntry.offset + dataEntry.fileSize) - firstDataEntry.offset
      var partialSize: UInt64?
      if nextSize > singleFileByteLimit {
        partialSize = singleFileByteLimit - (dataEntry.offset - firstDataEntry.offset)
      }

      // Update fileSize
      fileSize = min(nextSize, singleFileByteLimit)

      if dataEntry == newDataEntry {
        // Handle case where the dataEntry is the new dataEntry responsible for the merge
        fileHandle.write(data.subdata(in: 0..<Int(partialSize ?? dataEntry.fileSize)))
      } else {
        // Handle merge for an entry data into the fileHandle
        let currentFileURL = self.fileURL(for: key, offset: dataEntry.offset)
        let currentFileHandle = try! FileHandle(forReadingFrom: currentFileURL)
        let currentData = currentFileHandle.readData(ofLength: Int(partialSize ?? dataEntry.fileSize))
        fileHandle.write(currentData)

        // Delete the file that was merged
        try? FileManager.default.removeItem(at: currentFileURL)
      }

      // If we have a partialSize, delete all other files and break
      if partialSize != nil {
        let nextIndex = min(i + 1, sortedDataEntries.count - 1)
        sortedDataEntries[nextIndex...].forEach {
          let currentFileURL = self.fileURL(for: key, offset: $0.offset)
          try? FileManager.default.removeItem(at: currentFileURL)
        }
        break
      }
    }

    // Flush buffers
    fileHandle.synchronizeFile()

    // Update manifest
    // - Remove merged dataEntries
    entry.dataEntries = entry.dataEntries.filter { !dataEntries.contains($0) }

    // - Create the merged dataEntry and add it to the manifest
    let finalDataEntry = DataEntry(
      lastAccessDate: Date(),
      fileSize: fileSize,
      offset: firstDataEntry.offset
    )
    entry.dataEntries.append(finalDataEntry)

    // Update byteCount
    updateByteCount()
  }

}
