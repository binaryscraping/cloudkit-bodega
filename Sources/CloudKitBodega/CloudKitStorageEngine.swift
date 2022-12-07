import Bodega
import CloudKit
import Foundation
import OSLog

public actor CloudKitStorageEngine: StorageEngine {
  private let container: CKContainer
  private let recordType: CKRecord.RecordType
  private lazy var privateDatabase = container.privateCloudDatabase
  private let zoneID = CKRecordZone.ID(
    zoneName: "CloudKitStorageEngineZone",
    ownerName: CKCurrentUserDefaultName
  )
  private let logger = Logger(
    subsystem: "co.binaryscraping.cloudkit-bodega",
    category: "CloudKitStorageEngine"
  )

  public init(container: CKContainer, recordType: CKRecord.RecordType) {
    self.container = container
    self.recordType = recordType
  }

  public func write(_ data: Data, key: CacheKey) async throws {
    await createCustomZoneIfNeeded()

    let record = makeRecord(fromData: data, andKey: key)
    try await privateDatabase.save(record)
  }

  public func write(_ dataAndKeys: [(key: CacheKey, data: Data)]) async throws {
    await createCustomZoneIfNeeded()

    let records = dataAndKeys.map { makeRecord(fromData: $0.data, andKey: $0.key) }
    _ = try await privateDatabase.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
  }

  public func read(key: CacheKey) async -> Data? {
    await createCustomZoneIfNeeded()

    do {
      let record = try await fetchRecord(withKey: key)
      return record["data"] as? Data
    } catch {
      return nil
    }
  }

  public func read(keys: [CacheKey]) async -> [Data] {
    await createCustomZoneIfNeeded()
    return await readDataAndKeys(keys: keys).map(\.data)
  }

  public func readDataAndKeys(keys: [CacheKey]) async -> [(key: CacheKey, data: Data)] {
    await createCustomZoneIfNeeded()

    do {
      let ids = keys.map { CKRecord.ID(recordName: $0.value, zoneID: zoneID) }
      let records = try await privateDatabase.records(for: ids)
      var results: [(key: CacheKey, data: Data)] = []
      results.reserveCapacity(ids.count)

      for (key, id) in zip(keys, ids) {
        let result = records[id]
        if case let .success(record) = result,
           let data = record["data"] as? Data
        {
          results.append((key, data))
        } else {
          fatalError()
        }
      }
      return results
    } catch {
      return []
    }
  }

  public func readAllData() async -> [Data] {
    await createCustomZoneIfNeeded()
    return await readAllDataAndKeys().map(\.data)
  }

  public func readAllDataAndKeys() async -> [(key: CacheKey, data: Data)] {
    await createCustomZoneIfNeeded()

    do {
      let results = try await fetchAllRecords()

      return results.map { id, result in
        let key = CacheKey(verbatim: id.recordName)
        if case let .success(record) = result,
           let data = record["data"] as? Data
        {
          return (key: key, data: data)
        }
        fatalError()
      }
    } catch {
      logger.error("Error reading all data and keys: \(String(describing: error))")
      return []
    }
  }

  public func remove(key: CacheKey) async throws {
    await createCustomZoneIfNeeded()
    try await privateDatabase
      .deleteRecord(withID: CKRecord.ID(recordName: key.value, zoneID: zoneID))
  }

  public func remove(keys: [CacheKey]) async throws {
    await createCustomZoneIfNeeded()
    let ids = keys.map { CKRecord.ID(recordName: $0.value, zoneID: zoneID) }
    _ = try await privateDatabase.modifyRecords(saving: [], deleting: ids)
  }

  public func removeAllData() async throws {
    await createCustomZoneIfNeeded()
    let records = try await fetchAllRecords()
    let ids = records.map(\.0)
    _ = try await privateDatabase.modifyRecords(saving: [], deleting: ids)
  }

  public func keyExists(_ key: CacheKey) async -> Bool {
    await createCustomZoneIfNeeded()
    do {
      _ = try await fetchRecord(withKey: key)
      return true
    } catch {
      return false
    }
  }

  public func keyCount() async -> Int {
    await createCustomZoneIfNeeded()
    return (try? await fetchAllRecords().count) ?? 0
  }

  public func allKeys() async -> [CacheKey] {
    await createCustomZoneIfNeeded()
    return (try? await fetchAllRecords().map(\.0).map {
      CacheKey(verbatim: $0.recordName)
    }) ?? []
  }

  public func createdAt(key: CacheKey) async -> Date? {
    await createCustomZoneIfNeeded()
    return try? await fetchRecord(withKey: key).creationDate
  }

  public func updatedAt(key: CacheKey) async -> Date? {
    await createCustomZoneIfNeeded()
    return try? await fetchRecord(withKey: key).modificationDate
  }

  private var createdCustomZoneKey: String {
    "CREATEDZONE-\(zoneID.zoneName)"
  }

  private var runningZoneCreationTask: Task<Void, Never>?
  private var createdCustomZone: Bool {
    get {
      UserDefaults.standard.bool(forKey: createdCustomZoneKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: createdCustomZoneKey)
    }
  }

  private func createCustomZoneIfNeeded() async {
    if let runningZoneCreationTask {
      return await runningZoneCreationTask.value
    }

    runningZoneCreationTask = Task {
      defer { runningZoneCreationTask = nil }

      guard !createdCustomZone else {
        logger
          .debug("Already have custom zone, skipping creation but checking if zone really exists.")
        await checkCustomZone()
        return
      }

      logger.info("Creating CloudKit zone: \(self.zoneID.zoneName)")

      do {
        let zone = CKRecordZone(zoneID: zoneID)
        try await privateDatabase.save(zone)
        createdCustomZone = true
        logger.info("Zone created successfully")
      } catch {
        logger.error("Error to create custom CloudKit zone: \(String(describing: error))")
        await retryCloudKitOperationIfPossible(error: error) {
          await createCustomZoneIfNeeded()
        }
      }
    }

    await runningZoneCreationTask?.value
  }

  private func checkCustomZone() async {
    do {
      _ = try await privateDatabase.recordZone(for: zoneID)
    } catch {
      logger.error("Failed to check for custom zone existence: \(String(describing: error))")

      if await !retryCloudKitOperationIfPossible(
        error: error,
        operation: { await self.checkCustomZone() }
      ) {
        logger
          .error(
            "Irrecoverable error when fetching custom zone, assuming it doesn't exist: \(String(describing: error))"
          )
        createdCustomZone = false
        await createCustomZoneIfNeeded()
      }
    }
  }

  private func makeRecord(fromData data: Data, andKey key: CacheKey) -> CKRecord {
    let record = CKRecord(
      recordType: recordType,
      recordID: CKRecord.ID(recordName: key.value, zoneID: zoneID)
    )
    record.setValuesForKeys(["key": key.value, "data": data])
    return record
  }

  private func fetchRecord(withKey key: CacheKey) async throws -> CKRecord {
    try await privateDatabase.record(for: CKRecord.ID(recordName: key.value, zoneID: zoneID))
  }

  private func fetchAllRecords() async throws -> [(CKRecord.ID, Result<CKRecord, Error>)] {
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
    var results: [(CKRecord.ID, Result<CKRecord, Error>)] = []
    var (matchResults, queryCursor) = try await privateDatabase.records(matching: query)
    results.append(contentsOf: matchResults)

    while let cursor = queryCursor {
      (matchResults, queryCursor) = try await privateDatabase.records(continuingMatchFrom: cursor)
      results.append(contentsOf: matchResults)
    }

    return results
  }

  @discardableResult
  private func retryCloudKitOperationIfPossible(
    error: Error,
    operation: () async -> Void
  ) async -> Bool {
    guard
      let ckError = error as? CKError,
      let retryDelay = ckError.retryAfterSeconds
    else {
      return false
    }

    try? await Task.sleep(nanoseconds: UInt64(retryDelay) * NSEC_PER_SEC)
    if Task.isCancelled {
      return false
    }

    await operation()
    return true
  }
}
