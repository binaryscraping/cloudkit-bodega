import Bodega
import Foundation
import CloudKit

public actor CloudKitStorageEngine: StorageEngine {
  private let container: CKContainer
  private let recordType: CKRecord.RecordType
  private lazy var privateDatabase = container.privateCloudDatabase
  private let zoneID = CKRecordZone.ID(zoneName: "")

  public init(container: CKContainer, recordType: CKRecord.RecordType) {
    self.container = container
    self.recordType = recordType
  }

  public func write(_ data: Data, key: CacheKey) async throws {
    let record = record(fromData: data, andKey: key)
    try await privateDatabase.save(record)
  }

  public func write(_ dataAndKeys: [(key: CacheKey, data: Data)]) async throws {
    let records = dataAndKeys.map { record(fromData: $0.data, andKey: $0.key) }
    _ = try await privateDatabase.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
  }

  public func read(key: CacheKey) async -> Data? {
    do {
      let record = try await fetchRecord(withKey: key)
      return record["data"] as? Data
    } catch {
      return nil
    }
  }

  public func read(keys: [CacheKey]) async -> [Data] {
    await readDataAndKeys(keys: keys).map(\.data)
  }

  public func readDataAndKeys(keys: [CacheKey]) async -> [(key: CacheKey, data: Data)] {
    do {
      let ids = keys.map { CKRecord.ID(recordName: $0.value, zoneID: zoneID) }
      let records = try await privateDatabase.records(for: ids)
      var results: [(key: CacheKey, data: Data)] = []
      results.reserveCapacity(ids.count)

      for (key, id) in zip(keys, ids) {
        let result = records[id]
        if case .success(let record) = result,
           let data = record["data"] as? Data {
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
    await readAllDataAndKeys().map(\.data)
  }

  public func readAllDataAndKeys() async -> [(key: CacheKey, data: Data)] {
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
    do {
      var results: [(CKRecord.ID, Result<CKRecord, Error>)] = []
      var (matchResults, queryCursor) = try await privateDatabase.records(matching: query)
      results.append(contentsOf: matchResults)

      while let cursor = queryCursor {
        (matchResults, queryCursor) = try await privateDatabase.records(continuingMatchFrom: cursor)
        results.append(contentsOf: matchResults)
      }

      return results.map { id, result in
        let key = CacheKey(verbatim: id.recordName)
        if case .success(let record) = result,
           let data = record["data"] as? Data {
          return (key: key, data: data)
        }
        fatalError()
      }
    } catch {
      return []
    }
  }

  public func remove(key: CacheKey) async throws {
    try await privateDatabase.deleteRecord(withID: CKRecord.ID(recordName: key.value, zoneID: zoneID))
  }

  public func remove(keys: [CacheKey]) async throws {
    let ids = keys.map { CKRecord.ID(recordName: $0.value, zoneID: zoneID) }
    _ = try await privateDatabase.modifyRecords(saving: [], deleting: ids)
  }

  public func removeAllData() async throws {
    let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
    // TODO:
  }

  public func keyExists(_ key: CacheKey) async -> Bool {
    false
  }

  public func keyCount() async -> Int {
    0
  }

  public func allKeys() async -> [CacheKey] {
    []
  }

  public func createdAt(key: CacheKey) async -> Date? {
    try? await fetchRecord(withKey: key).creationDate
  }

  public func updatedAt(key: CacheKey) async -> Date? {
    try? await fetchRecord(withKey: key).modificationDate
  }

  private func record(fromData data: Data, andKey key: CacheKey) -> CKRecord {
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
}
