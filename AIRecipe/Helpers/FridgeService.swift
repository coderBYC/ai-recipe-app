import Foundation
import SwiftData

enum FridgeService {
    static let expiringSoonWindowDays = FridgeItem.expiringSoonWindowDays

    // MARK: - Migration

    @MainActor
    static func migrateLegacyZoneLabels(modelContext: ModelContext) {
        guard let all = try? modelContext.fetch(FetchDescriptor<FridgeItem>()) else { return }
        var changed = false
        for item in all {
            switch item.zoneRaw {
            case "Crisper Drawer":
                item.zoneRaw = FridgeZone.crisperDrawer.rawValue
                changed = true
            case "Fridge Door":
                item.zoneRaw = FridgeZone.leftDoor.rawValue
                changed = true
            default:
                break
            }
        }
        if changed { try? modelContext.save() }
    }

    // MARK: - Fetch

    @MainActor
    static func fetchItems(
        ownerUserId: String,
        zone: FridgeZone? = nil,
        modelContext: ModelContext
    ) -> [FridgeItem] {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return [] }

        if let zone {
            let zoneRaw = zone.rawValue
            let desc = FetchDescriptor<FridgeItem>(
                predicate: #Predicate<FridgeItem> {
                    $0.ownerUserId == owner && $0.zoneRaw == zoneRaw
                },
                sortBy: [
                    SortDescriptor(\.expirationDate),
                    SortDescriptor(\.name),
                ]
            )
            return (try? modelContext.fetch(desc)) ?? []
        }

        let desc = FetchDescriptor<FridgeItem>(
            predicate: #Predicate<FridgeItem> { $0.ownerUserId == owner },
            sortBy: [
                SortDescriptor(\.expirationDate),
                SortDescriptor(\.name),
            ]
        )
        return (try? modelContext.fetch(desc)) ?? []
    }

    @MainActor
    static func itemsGroupedByZone(
        ownerUserId: String,
        modelContext: ModelContext
    ) -> [FridgeZone: [FridgeItem]] {
        let items = fetchItems(ownerUserId: ownerUserId, modelContext: modelContext)
        return Dictionary(grouping: items, by: \.zone)
    }

    @MainActor
    static func expiringSoonItems(
        ownerUserId: String,
        modelContext: ModelContext
    ) -> [FridgeItem] {
        fetchItems(ownerUserId: ownerUserId, modelContext: modelContext)
            .filter(\.isExpiringSoon)
    }

    @MainActor
    static func expiredItems(
        ownerUserId: String,
        modelContext: ModelContext
    ) -> [FridgeItem] {
        fetchItems(ownerUserId: ownerUserId, modelContext: modelContext)
            .filter(\.isExpired)
    }

    // MARK: - Mutations

    @MainActor
    @discardableResult
    static func addItem(
        name: String,
        zone: FridgeZone,
        expirationDate: Date,
        quantityDisplay: String,
        ownerUserId: String,
        modelContext: ModelContext
    ) -> FridgeItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !owner.isEmpty else { return nil }

        let item = FridgeItem(
            ownerUserId: owner,
            name: trimmedName,
            zone: zone,
            expirationDate: expirationDate,
            quantityDisplay: quantityDisplay
        )
        modelContext.insert(item)
        try? modelContext.save()
        return item
    }

    @MainActor
    @discardableResult
    static func updateItem(
        _ item: FridgeItem,
        name: String? = nil,
        zone: FridgeZone? = nil,
        expirationDate: Date? = nil,
        quantityDisplay: String? = nil,
        modelContext: ModelContext
    ) -> Bool {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            item.name = trimmed
        }
        if let zone { item.zone = zone }
        if let expirationDate { item.expirationDate = expirationDate }
        if let quantityDisplay {
            item.quantityDisplay = quantityDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        item.updatedAt = Date()
        try? modelContext.save()
        return true
    }

    @MainActor
    @discardableResult
    static func moveItem(
        _ item: FridgeItem,
        to zone: FridgeZone,
        modelContext: ModelContext
    ) -> Bool {
        item.zone = zone
        item.updatedAt = Date()
        try? modelContext.save()
        return true
    }

    @MainActor
    @discardableResult
    static func deleteItem(_ item: FridgeItem, modelContext: ModelContext) -> Bool {
        modelContext.delete(item)
        try? modelContext.save()
        return true
    }
}
