import Foundation
import SQLite3
import SwiftData

/// Imports recipes from legacy / backup SwiftData SQLite stores into the active model.
enum LegacyRecipeStoreRecovery {

    struct RecoveryResult: Sendable {
        var importedFromAppGroup: Int = 0
        var importedFromBackups: Int = 0
        var importedFromAlternateStores: Int = 0
        var reassignedHidden: Int = 0
        var restoredSoftDeleted: Int = 0

        var total: Int {
            importedFromAppGroup + importedFromBackups + importedFromAlternateStores
                + reassignedHidden + restoredSoftDeleted
        }
    }

    struct StoreDiagnostics: Sendable {
        var activeStoreRecipeCount: Int
        var visibleForUserCount: Int
        var legacyAppGroupCount: Int
        /// Highest recipe count among on-disk SQLite stores (primary, recovery, backups, App Group).
        var importableOnDiskMaxCount: Int
        var backupStoreCounts: [(path: String, count: Int)]
        var sources: [String]
    }

    static let needsRecoveryImportDefaultsKey = "swiftData.needsRecoveryImport"

    // MARK: - Public API

    /// Max recipe rows across every importable SQLite file (deduped paths; not merged by id).
    static func totalImportableRecipeCountOnDisk() -> Int {
        allImportableStoreURLs()
            .map { recipeCount(inSQLiteStore: $0.url) }
            .max() ?? 0
    }

    /// Import from primary / recovery / backups when Home is empty but recipes still exist on disk.
    @MainActor
    @discardableResult
    static func recoverIfNeeded(modelContext: ModelContext, ownerUserId: String) -> RecoveryResult? {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return nil }

        let diag = diagnostics(modelContext: modelContext, ownerUserId: owner)
        let onDisk = diag.importableOnDiskMaxCount
        let flagged = UserDefaults.standard.bool(forKey: needsRecoveryImportDefaultsKey)

        let shouldRecover = flagged
            || (diag.visibleForUserCount == 0 && (onDisk > 0 || diag.activeStoreRecipeCount > 0))

        guard shouldRecover else { return nil }

        let result = recoverAll(modelContext: modelContext, ownerUserId: owner)
        if result.total > 0 || result.reassignedHidden > 0 || result.restoredSoftDeleted > 0 {
            UserDefaults.standard.set(false, forKey: needsRecoveryImportDefaultsKey)
        }
        return result
    }

    @MainActor
    static func diagnostics(modelContext: ModelContext, ownerUserId: String) -> StoreDiagnostics {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let visible = owner.isEmpty ? 0 : all.filter {
            $0.deletedAt == nil && $0.ownerUserId == owner
        }.count

        var backupCounts: [(String, Int)] = []
        var sources: [String] = []

        if let legacy = legacyAppGroupStoreURL(), FileManager.default.fileExists(atPath: legacy.path) {
            let c = recipeCount(inSQLiteStore: legacy)
            sources.append("App Group legacy: \(c) recipes")
            backupCounts.append(("App Group", c))
        }

        if let appSupport = activeApplicationSupportDirectory() {
            for name in ["default.store", "default.recovery.store"] {
                let url = appSupport.appending(path: name, directoryHint: .notDirectory)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let c = recipeCount(inSQLiteStore: url)
                sources.append("\(name): \(c) recipes")
                backupCounts.append((name, c))
            }
        }

        for url in backupStoreURLs() {
            let c = recipeCount(inSQLiteStore: url)
            let name = url.lastPathComponent
            sources.append("\(name): \(c) recipes")
            backupCounts.append((name, c))
        }

        let onDiskMax = totalImportableRecipeCountOnDisk()

        return StoreDiagnostics(
            activeStoreRecipeCount: all.count,
            visibleForUserCount: visible,
            legacyAppGroupCount: legacyAppGroupStoreURL().map { recipeCount(inSQLiteStore: $0) } ?? 0,
            importableOnDiskMaxCount: onDiskMax,
            backupStoreCounts: backupCounts,
            sources: sources
        )
    }

    @MainActor
    @discardableResult
    static func recoverAll(modelContext: ModelContext, ownerUserId: String) -> RecoveryResult {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return RecoveryResult() }

        var result = RecoveryResult()
        let defaultCookbookId = CookbookService.ensureLibrary(for: owner, modelContext: modelContext).id
        var existingIds = Set(fetchAllRecipeIds(modelContext: modelContext))

        for (label, url, bucket) in allImportableStoreURLs() {
            let n = importRecipes(
                from: url,
                label: label,
                modelContext: modelContext,
                ownerUserId: owner,
                defaultCookbookId: defaultCookbookId,
                existingIds: &existingIds
            )
            switch bucket {
            case .appGroup: result.importedFromAppGroup += n
            case .backup: result.importedFromBackups += n
            case .alternate: result.importedFromAlternateStores += n
            }
        }

        result.reassignedHidden = reassignHiddenLocalRecipes(
            modelContext: modelContext,
            ownerUserId: owner
        )
        result.restoredSoftDeleted = restoreSoftDeletedRecipes(
            modelContext: modelContext,
            ownerUserId: owner
        )

        if result.total > 0 {
            CookbookService.setActiveCookbookId(defaultCookbookId, ownerUserId: owner)
            try? modelContext.save()
            #if DEBUG
            print("[LegacyRecipeStoreRecovery] recoverAll: \(result)")
            #endif
        }

        return result
    }

    /// Reassigns recipes stuck under onboarding / empty owner to the signed-in user.
    @MainActor
    @discardableResult
    static func reassignHiddenLocalRecipes(
        modelContext: ModelContext,
        ownerUserId: String
    ) -> Int {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return 0 }

        let onboarding = Recipe.localOnboardingOwnerPlaceholder
        let desc = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.deletedAt == nil
                    && ($0.ownerUserId == "" || $0.ownerUserId == onboarding)
            }
        )
        guard let rows = try? modelContext.fetch(desc), !rows.isEmpty else { return 0 }

        let defaultCookbookId = CookbookService.ensureLibrary(for: owner, modelContext: modelContext).id
        for recipe in rows {
            recipe.ownerUserId = owner
            if recipe.cookbookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recipe.cookbookId = defaultCookbookId
            }
            recipe.updatedAt = Date()
        }
        try? modelContext.save()
        return rows.count
    }

    @MainActor
    @discardableResult
    static func restoreSoftDeletedRecipes(
        modelContext: ModelContext,
        ownerUserId: String
    ) -> Int {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return 0 }

        let desc = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.ownerUserId == owner && $0.deletedAt != nil
            }
        )
        guard let rows = try? modelContext.fetch(desc), !rows.isEmpty else { return 0 }

        for recipe in rows {
            recipe.deletedAt = nil
            recipe.updatedAt = Date()
        }
        try? modelContext.save()
        return rows.count
    }

    // MARK: - Store discovery

    static func activeApplicationSupportDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    static func legacyAppGroupStoreURL() -> URL? {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PendingRecipeImport.appGroupSuiteName
        ) else { return nil }
        return group.appending(path: "Library/Application Support/default.store", directoryHint: .notDirectory)
    }

    static func backupStoreURLs() -> [URL] {
        guard let appSupport = activeApplicationSupportDirectory() else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("default.store.backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func alternateActiveStoreURLs() -> [URL] {
        guard let appSupport = activeApplicationSupportDirectory() else { return [] }
        let candidates = ["default.recovery.store", "default.legacy.store"]
        return candidates
            .map { appSupport.appending(path: $0, directoryHint: .notDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private enum ImportBucket { case appGroup, backup, alternate }

    /// Every on-disk SQLite store that may hold recipes (deduped by path).
    private static func allImportableStoreURLs() -> [(label: String, url: URL, bucket: ImportBucket)] {
        var seen = Set<String>()
        var out: [(String, URL, ImportBucket)] = []

        func append(_ label: String, _ url: URL, _ bucket: ImportBucket) {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted, FileManager.default.fileExists(atPath: url.path) else { return }
            guard recipeCount(inSQLiteStore: url) > 0 else { return }
            out.append((label, url, bucket))
        }

        if let legacy = legacyAppGroupStoreURL() {
            append("AppGroup", legacy, .appGroup)
        }

        if let appSupport = activeApplicationSupportDirectory() {
            // Primary store may be unreadable by SwiftData but still importable via SQLite.
            append("primary-default.store", appSupport.appending(path: "default.store"), .backup)
        }

        for backup in backupStoreURLs() {
            append(backup.lastPathComponent, backup, .backup)
        }

        for alt in alternateActiveStoreURLs() {
            append(alt.lastPathComponent, alt, .alternate)
        }

        return out
    }

    // MARK: - SQLite import

    private struct SQLiteRecipeRow {
        let id: String
        let title: String
        let creator: String
        let source: String
        let sourceURL: String
        let timestamp: String
        let ingredients: String
        let ingredientCheckmarks: String
        let notes: String
        let stepsContent: String
        let estimatedCookingMinutes: Int
        let prepMinutes: Int
        let totalSteps: Int
        let triedBefore: Bool
        let rating: Int
        let downloadedVideoURL: String
        let videoPlaybackURL: String
        let stepTimestampsContent: String
        let dishHeroTimestampSeconds: Double
        let isBookmarked: Bool
        let createdAt: Date
        let updatedAt: Date
        let isSoftDeleted: Bool
    }

    @MainActor
    private static func importRecipes(
        from url: URL,
        label: String,
        modelContext: ModelContext,
        ownerUserId: String,
        defaultCookbookId: String,
        existingIds: inout Set<String>
    ) -> Int {
        let rows = readRecipes(from: url)
        guard !rows.isEmpty else { return 0 }

        var imported = 0
        for row in rows {
            guard !row.isSoftDeleted else { continue }
            guard !existingIds.contains(row.id) else { continue }

            let recipe = Recipe(
                id: row.id,
                ownerUserId: ownerUserId,
                cookbookId: defaultCookbookId,
                title: row.title,
                source: RecipeSource(rawValue: row.source) ?? .youtube,
                sourceURL: row.sourceURL,
                creator: row.creator,
                timestamp: row.timestamp,
                ingredients: row.ingredients,
                estimatedCookingMinutes: row.estimatedCookingMinutes,
                prepMinutes: row.prepMinutes,
                totalSteps: row.totalSteps,
                triedBefore: row.triedBefore,
                notes: row.notes,
                stepsContent: row.stepsContent,
                ingredientCheckmarks: row.ingredientCheckmarks,
                downloadedVideoURL: row.downloadedVideoURL,
                videoPlaybackURL: row.videoPlaybackURL,
                stepTimestampsContent: row.stepTimestampsContent,
                dishHeroTimestampSeconds: row.dishHeroTimestampSeconds,
                rating: row.rating,
                isBookmarked: row.isBookmarked,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
            modelContext.insert(recipe)
            existingIds.insert(row.id)
            imported += 1
        }

        if imported > 0 {
            #if DEBUG
            print("[LegacyRecipeStoreRecovery] imported \(imported) from \(label)")
            #endif
        }
        return imported
    }

    private static func recipeCount(inSQLiteStore url: URL) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return 0
        }
        defer { sqlite3_close(db) }

        guard tableExists("ZRECIPE", db: db) else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZRECIPE", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func tableExists(_ name: String, db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func columnSet(in db: OpaquePointer, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var cols = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) {
                cols.insert(String(cString: c).uppercased())
            }
        }
        return cols
    }

    private static func readRecipes(from url: URL) -> [SQLiteRecipeRow] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return []
        }
        defer { sqlite3_close(db) }

        guard tableExists("ZRECIPE", db: db) else { return [] }
        let cols = columnSet(in: db, table: "ZRECIPE")
        guard cols.contains("ZID") || cols.contains("Z_PK") else { return [] }

        let selectList = buildSelectList(columns: cols)
        let sql = "SELECT \(selectList) FROM ZRECIPE"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [SQLiteRecipeRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let row = parseRow(stmt, columns: cols) {
                rows.append(row)
            }
        }
        return rows
    }

    private static func buildSelectList(columns: Set<String>) -> String {
        let wanted = [
            "ZID", "ZTITLE", "ZCREATOR", "ZSOURCE", "ZSOURCEURL", "ZTIMESTAMP",
            "ZINGREDIENTS", "ZINGREDIENTCHECKMARKS", "ZNOTES", "ZSTEPSCONTENT",
            "ZESTIMATEDCOOKINGMINUTES", "ZPREPMINUTES", "ZTOTALSTEPS", "ZTRIEDBEFORE",
            "ZRATING", "ZDOWNLOADEDVIDEOURL", "ZVIDEOPLAYBACKURL", "ZSTEPTIMESTAMPSCONTENT",
            "ZDISHHEROTIMESTAMPSECONDS", "ZISBOOKMARKED", "ZCREATEDAT", "ZUPDATEDAT", "ZDELETEDAT"
        ]
        return wanted.map { col in
            columns.contains(col) ? col : "NULL AS \(col)"
        }.joined(separator: ", ")
    }

    private static func parseRow(_ stmt: OpaquePointer, columns: Set<String>) -> SQLiteRecipeRow? {
        // Column indices match buildSelectList order (0…22).
        _ = columns
        guard let id = uuidString(fromSQLiteID: stmt, column: 0) else { return nil }

        let deletedAt = dateColumn(stmt, 22)
        let created = dateColumn(stmt, 20) ?? Date()
        let updated = dateColumn(stmt, 21) ?? created

        return SQLiteRecipeRow(
            id: id,
            title: stringColumn(stmt, 1),
            creator: stringColumn(stmt, 2),
            source: stringColumn(stmt, 3),
            sourceURL: stringColumn(stmt, 4),
            timestamp: stringColumn(stmt, 5),
            ingredients: stringColumn(stmt, 6),
            ingredientCheckmarks: stringColumn(stmt, 7),
            notes: stringColumn(stmt, 8),
            stepsContent: stringColumn(stmt, 9),
            estimatedCookingMinutes: intColumn(stmt, 10),
            prepMinutes: intColumn(stmt, 11),
            totalSteps: intColumn(stmt, 12),
            triedBefore: intColumn(stmt, 13) != 0,
            rating: intColumn(stmt, 14),
            downloadedVideoURL: stringColumn(stmt, 15),
            videoPlaybackURL: stringColumn(stmt, 16),
            stepTimestampsContent: stringColumn(stmt, 17),
            dishHeroTimestampSeconds: doubleColumn(stmt, 18),
            isBookmarked: intColumn(stmt, 19) != 0,
            createdAt: created,
            updatedAt: updated,
            isSoftDeleted: deletedAt != nil
        )
    }

    @MainActor
    private static func fetchAllRecipeIds(modelContext: ModelContext) -> [String] {
        let desc = FetchDescriptor<Recipe>()
        return (try? modelContext.fetch(desc).map(\.id)) ?? []
    }

    // MARK: - SQLite helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard index >= 0, sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private static func intColumn(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        guard index >= 0, sqlite3_column_type(stmt, index) != SQLITE_NULL else { return 0 }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private static func doubleColumn(_ stmt: OpaquePointer, _ index: Int32) -> Double {
        guard index >= 0, sqlite3_column_type(stmt, index) != SQLITE_NULL else { return 1 }
        return sqlite3_column_double(stmt, index)
    }

    private static func dateColumn(_ stmt: OpaquePointer, _ index: Int32) -> Date? {
        guard index >= 0, sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, index))
    }

    private static func uuidString(fromSQLiteID stmt: OpaquePointer, column: Int32) -> String? {
        guard column >= 0 else { return nil }
        switch sqlite3_column_type(stmt, column) {
        case SQLITE_TEXT:
            let raw = stringColumn(stmt, column).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return nil }
            if raw.contains("-") { return raw.uppercased() }
            return formatUUID(hex: raw)
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(stmt, column)
            let count = Int(sqlite3_column_bytes(stmt, column))
            guard let bytes, count == 16 else { return nil }
            return uuidString(fromUUIDData: Data(bytes: bytes, count: count))
        default:
            return nil
        }
    }

    private static func formatUUID(hex: String) -> String {
        let h = hex.uppercased()
        guard h.count == 32 else { return h }
        var s = h
        for offset in [23, 18, 13, 8] {
            let i = s.index(s.startIndex, offsetBy: offset)
            s.insert("-", at: i)
        }
        return s
    }

    private static func uuidString(fromUUIDData data: Data) -> String {
        guard data.count == 16 else { return UUID().uuidString }
        let u = data.withUnsafeBytes { raw -> uuid_t in
            var id = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            _ = withUnsafeMutableBytes(of: &id) { dest in raw.copyBytes(to: dest) }
            return id
        }
        return UUID(uuid: u).uuidString.uppercased()
    }
}
