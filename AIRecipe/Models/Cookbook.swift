import Foundation
import SwiftData

@Model
final class Cookbook: Identifiable {
    @Attribute(.unique) var id: String
    var ownerUserId: String
    var name: String
    var isDefault: Bool
    var createdAt: Date
    var sortOrder: Int

    init(
        id: String = "",
        ownerUserId: String,
        name: String,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmedId.isEmpty ? UUID().uuidString : trimmedId
        self.ownerUserId = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
