import Foundation
import CloudKitBodega
import Boutique

struct Account: Identifiable, Hashable, Codable {
  let id: UUID
  var name: String
  var balance: Double
  var createdAt: Date
}

extension Store where Item == Account {
  static let accounts = Store(storage: CloudKitStorageEngine(container: .default(), recordType: "Account"))
}
