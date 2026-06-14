import Foundation
import SwiftData

enum FridgeZone: String, CaseIterable, Codable, Identifiable {
    case topShelf = "Top Shelf"
    case middleShelf = "Middle Shelf"
    case bottomShelf = "Bottom Shelf"
    case crisperDrawer = "Product Preserver"
    case leftDoor = "Left Door"
    case rightDoor = "Right Door"
    case freezer = "Freezer"

    var id: String { rawValue }

    /// Zones exposed as tappable regions on the fridge illustration.
    static let interactiveZones: [FridgeZone] = [.leftDoor, .rightDoor, .crisperDrawer]

    var sfSymbol: String {
        switch self {
        case .topShelf: return "rectangle.split.3x1"
        case .middleShelf: return "rectangle.split.3x1.fill"
        case .bottomShelf: return "square.split.bottom.quarter"
        case .crisperDrawer: return "leaf.box.fill"
        case .leftDoor: return "door.left.hand.open"
        case .rightDoor: return "door.right.hand.open"
        case .freezer: return "snowflake"
        }
    }
}

@Model
final class FridgeItem: Identifiable {
    static let expiringSoonWindowDays = 3

    var id: UUID
    var ownerUserId: String
    var name: String
    var zoneRaw: String
    var expirationDate: Date
    var quantityDisplay: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerUserId: String,
        name: String,
        zone: FridgeZone,
        expirationDate: Date,
        quantityDisplay: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerUserId = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.zoneRaw = zone.rawValue
        self.expirationDate = expirationDate
        self.quantityDisplay = quantityDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var zone: FridgeZone {
        get {
            if zoneRaw == "Fridge Door" || zoneRaw == "Crisper Drawer" {
                return zoneRaw == "Fridge Door" ? .leftDoor : .crisperDrawer
            }
            return FridgeZone(rawValue: zoneRaw) ?? .middleShelf
        }
        set { zoneRaw = newValue.rawValue }
    }

    var isExpiringSoon: Bool {
        Self.isExpiringSoon(expirationDate: expirationDate)
    }

    var isExpired: Bool {
        Self.isExpired(expirationDate: expirationDate)
    }

    static func isExpiringSoon(
        expirationDate: Date,
        withinDays: Int = expiringSoonWindowDays,
        from reference: Date = Date()
    ) -> Bool {
        let calendar = Calendar.current
        guard let warningDate = calendar.date(byAdding: .day, value: withinDays, to: reference) else {
            return false
        }
        return expirationDate <= warningDate
    }

    static func isExpired(expirationDate: Date, from reference: Date = Date()) -> Bool {
        expirationDate < Calendar.current.startOfDay(for: reference)
    }
}
