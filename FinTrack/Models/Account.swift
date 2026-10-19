import Foundation
import SwiftData

/// Dormant model kept for schema compatibility and future account-system expansion.
/// It is no longer part of the main finance flow, but removing it now would force a
/// migration and still break legacy account-management, export, and reset surfaces.
@Model
final class Account {
    var name: String
    var type: String
    var balance: Double
    var currency: String
    var createdAt: Date

    init(
        name: String,
        type: String,
        balance: Double,
        currency: String,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.type = type
        self.balance = balance
        self.currency = currency
        self.createdAt = createdAt
    }
}
