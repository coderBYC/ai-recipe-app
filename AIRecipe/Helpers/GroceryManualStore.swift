import Foundation

struct ManualGroceryItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var unit: String
    var isChecked: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        unit: String = "",
        isChecked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.isChecked = isChecked
    }
}

enum GroceryManualStore {
    private static func storageKey(ownerUserId: String) -> String {
        "manualGroceryItems.\(ownerUserId)"
    }

    static func load(ownerUserId: String) -> [ManualGroceryItem] {
        let key = storageKey(ownerUserId: ownerUserId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ManualGroceryItem].self, from: data)) ?? []
    }

    static func save(_ items: [ManualGroceryItem], ownerUserId: String) {
        let key = storageKey(ownerUserId: ownerUserId)
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func mergedStorageKey(ownerUserId: String) -> String {
        "mergedGroceryItems.\(ownerUserId)"
    }

    private static func mergedViewKey(ownerUserId: String) -> String {
        "mergedGroceryViewActive.\(ownerUserId)"
    }

    static func isShowingMergedView(ownerUserId: String) -> Bool {
        UserDefaults.standard.bool(forKey: mergedViewKey(ownerUserId: ownerUserId))
    }

    static func setShowingMergedView(_ active: Bool, ownerUserId: String) {
        UserDefaults.standard.set(active, forKey: mergedViewKey(ownerUserId: ownerUserId))
    }

    static func loadMerged(ownerUserId: String) -> [ManualGroceryItem] {
        let key = mergedStorageKey(ownerUserId: ownerUserId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ManualGroceryItem].self, from: data)) ?? []
    }

    static func saveMerged(_ items: [ManualGroceryItem], ownerUserId: String) {
        let key = mergedStorageKey(ownerUserId: ownerUserId)
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clearMerged(ownerUserId: String) {
        UserDefaults.standard.removeObject(forKey: mergedStorageKey(ownerUserId: ownerUserId))
        setShowingMergedView(false, ownerUserId: ownerUserId)
    }
}
