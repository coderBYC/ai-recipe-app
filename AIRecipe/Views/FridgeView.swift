import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum FridgePhotoLoader {
    static func jpegData(from item: PhotosPickerItem) async -> Data? {
        if let payload = try? await item.loadTransferable(type: FridgePickedImage.self) {
            return payload.jpegData
        }
        if let data = try? await item.loadTransferable(type: Data.self) {
            return jpegData(fromRaw: data)
        }
        return nil
    }

    static func jpegData(fromRaw data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.85)
    }
}

private struct FridgePickedImage: Transferable {
    let jpegData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { data in
            guard let jpeg = FridgePhotoLoader.jpegData(fromRaw: data) else {
                throw TransferError.importFailed
            }
            return FridgePickedImage(jpegData: jpeg)
        }
        DataRepresentation(importedContentType: .heic) { data in
            guard let jpeg = FridgePhotoLoader.jpegData(fromRaw: data) else {
                throw TransferError.importFailed
            }
            return FridgePickedImage(jpegData: jpeg)
        }
        DataRepresentation(importedContentType: .png) { data in
            guard let jpeg = FridgePhotoLoader.jpegData(fromRaw: data) else {
                throw TransferError.importFailed
            }
            return FridgePickedImage(jpegData: jpeg)
        }
        DataRepresentation(importedContentType: .image) { data in
            guard let jpeg = FridgePhotoLoader.jpegData(fromRaw: data) else {
                throw TransferError.importFailed
            }
            return FridgePickedImage(jpegData: jpeg)
        }
    }

    enum TransferError: Error {
        case importFailed
    }
}

// MARK: - Main tab

struct FridgeView: View {
    let filterOwnerId: String

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var subManager = SubscriptionManager.shared
    @Query private var allItems: [FridgeItem]
    @State private var addItemZone: FridgeZone?
    @State private var editingItem: FridgeItem?
    @State private var cameraZone: FridgeZone?
    @State private var libraryPickerZone: FridgeZone?
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isScanning = false
    @State private var scanStatus: String?
    @State private var scanError: String?
    @State private var showPaywall = false

    init(filterOwnerId: String) {
        self.filterOwnerId = filterOwnerId
        let oid = filterOwnerId
        _allItems = Query(
            filter: #Predicate<FridgeItem> { $0.ownerUserId == oid },
            sort: [
                SortDescriptor(\.expirationDate),
                SortDescriptor(\.name),
            ]
        )
    }

    private var itemsByZone: [FridgeZone: [FridgeItem]] {
        Dictionary(grouping: allItems, by: \.zone)
    }

    /// Items in the order they were added (each scan appends at the bottom).
    private func items(for zone: FridgeZone) -> [FridgeItem] {
        (itemsByZone[zone] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    private var totalItemCount: Int { allItems.count }

    var body: some View {
        ProLockedOverlay(isLocked: !subManager.isPremium, onUnlock: { showPaywall = true }) {
            fridgeContent
        }
        .task { await subManager.checkStatus() }
        .proPaywallSheet(isPresented: $showPaywall)
    }

    private var fridgeContent: some View {
        NavigationStack {
            ZStack {
                Group {
                    if totalItemCount == 0 {
                        emptyState
                    } else {
                        listContent
                    }
                }
                .background(AppTheme.surface.ignoresSafeArea())

                if isScanning {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView(scanStatus ?? "Scanning fridge…")
                        .padding(20)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: 3,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: showPhotoPicker) { _, isPresented in
                guard !isPresented else { return }
                guard let zone = libraryPickerZone else { return }
                let batch = selectedPhotos
                libraryPickerZone = nil
                selectedPhotos = []
                guard !batch.isEmpty else { return }
                Task { await scanPhotoBatch(batch, zone: zone) }
            }
            .onAppear {
                FridgeService.migrateLegacyZoneLabels(modelContext: modelContext)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Fridge")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .sheet(item: $addItemZone) { zone in
                FridgeItemFormSheet(mode: .add(zone: zone), filterOwnerId: filterOwnerId)
            }
            .sheet(item: $editingItem) { item in
                FridgeItemFormSheet(mode: .edit(item: item), filterOwnerId: filterOwnerId)
            }
            .fullScreenCover(item: $cameraZone) { zone in
                FridgeCameraPicker { image in
                    cameraZone = nil
                    Task { await scanImage(image, zone: zone) }
                } onCancel: {
                    cameraZone = nil
                }
            }
            .alert("Could not scan photo", isPresented: Binding(
                get: { scanError != nil },
                set: { if !$0 { scanError = nil } }
            )) {
                Button("OK", role: .cancel) { scanError = nil }
            } message: {
                Text(scanError ?? "")
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "refrigerator.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppTheme.primary.opacity(0.85))
                    .padding(.top, 40)

                Text("Your fridge is empty")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Use + or the camera on a zone below to track what you have and when it expires.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                zoneCards
            }
            .padding(.bottom, 24)
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("⚠️ Warning: Default expiration day is after a week from now. Always rely on your physical inspection over AI-generated expiration dates and smart scanner readings.")
                    .appFont(.caption2)
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 16)
                zoneCards
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            
            
        }
    }

    private var zoneCards: some View {
        VStack(spacing: 16) {
            ForEach(FridgeZone.displayZones) { zone in
                FridgeZoneCard(
                    zone: zone,
                    items: items(for: zone),
                    onAdd: { addItemZone = zone },
                    onOpenLibrary: {
                        libraryPickerZone = zone
                        selectedPhotos = []
                        showPhotoPicker = true
                    },
                    onOpenCamera: { cameraZone = zone },
                    onEdit: { editingItem = $0 }
                )
            }
        }
    }

    @MainActor
    private func scanPhotoBatch(_ items: [PhotosPickerItem], zone: FridgeZone) async {
        guard !filterOwnerId.isEmpty else {
            scanError = "Sign in to scan fridge photos."
            return
        }

        var payloads: [Data] = []
        for item in items.prefix(3) {
            if let data = await FridgePhotoLoader.jpegData(from: item) {
                payloads.append(data)
            }
        }

        guard !payloads.isEmpty else {
            scanError = "Could not read the selected photos. Try JPEG or PNG images."
            return
        }

        await scanImagePayloads(payloads, zone: zone)
    }

    @MainActor
    private func scanImage(_ image: UIImage, zone: FridgeZone) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            scanError = "Could not prepare the photo."
            return
        }
        await scanImagePayloads([data], zone: zone)
    }

    @MainActor
    private func scanImagePayloads(_ payloads: [Data], zone: FridgeZone) async {
        guard !filterOwnerId.isEmpty else {
            scanError = "Sign in to scan fridge photos."
            return
        }

        isScanning = true
        scanError = nil
        defer {
            isScanning = false
            scanStatus = nil
        }

        var totalAdded = 0

        for (index, data) in payloads.enumerated() {
            if payloads.count > 1 {
                scanStatus = "Scanning photo \(index + 1) of \(payloads.count)…"
            }

            do {
                let detected = try await RecipeBackendService.shared.scanFridge(
                    zone: zone.rawValue,
                    imageData: data,
                    mimeType: "image/jpeg",
                    existingItems: items(for: zone).map(\.name)
                )
                let added = appendDetectedItems(detected, zone: zone)
                totalAdded += added
            } catch let error as RecipeBackendError {
                switch error {
                case .serverError(let msg): scanError = msg
                case .network(let err): scanError = err.localizedDescription
                case .invalidURL: scanError = "Invalid server URL."
                case .invalidResponse: scanError = "Invalid server response."
                }
                return
            } catch {
                scanError = error.localizedDescription
                return
            }
        }

        if totalAdded == 0 {
            scanError = payloads.count == 1
                ? "No food items were detected in that photo."
                : "No food items were detected in those photos."
        }
    }

    @MainActor
    private func appendDetectedItems(_ detected: [FridgeScanItem], zone: FridgeZone) -> Int {
        var added = 0
        for item in detected {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            _ = FridgeService.addItem(
                name: name,
                zone: zone,
                expirationDate: Self.parseExpirationDate(item.expiration_date),
                quantityDisplay: item.quantity_display ?? "",
                ownerUserId: filterOwnerId,
                modelContext: modelContext
            )
            added += 1
        }
        return added
    }

    private static func parseExpirationDate(_ raw: String?) -> Date {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        if !trimmed.isEmpty, let date = formatter.date(from: String(trimmed.prefix(10))) {
            return date
        }
        return Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }
}

// MARK: - Zone card

private struct FridgeZoneCard: View {
    let zone: FridgeZone
    let items: [FridgeItem]
    var onAdd: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenCamera: () -> Void
    var onEdit: (FridgeItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(zone.rawValue, systemImage: zone.sfSymbol)
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                Menu {
                    Button(action: onOpenLibrary) {
                        Label("Photo Library (up to 3)", systemImage: "photo.on.rectangle")
                    }
                    Button(action: onOpenCamera) {
                        Label("Take Photo", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "camera")
                        .font(AppTheme.bitterFont(size: 18, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Add items from photo in \(zone.rawValue)")

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(AppTheme.bitterFont(size: 18, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add item to \(zone.rawValue)")
            }

            if items.isEmpty {
                Text("Nothing here yet")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(items) { item in
                    FridgeItemRow(
                        item: item,
                        onEdit: { onEdit(item) }
                    )
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .padding(.horizontal, 16)
    }
}

// MARK: - Camera picker

private struct FridgeCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }
    }
}

// MARK: - Item row

private struct FridgeItemRow: View {
    let item: FridgeItem
    var onEdit: () -> Void

    private static let expirationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .appFont(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.isExpired {
                        statusBadge("Expired", color: .red.opacity(0.85))
                    } else if item.isExpiringSoon {
                        statusBadge("Soon", color: .orange.opacity(0.9))
                    }
                }

                HStack(spacing: 12) {
                    Label(
                        Self.expirationFormatter.string(from: item.expirationDate),
                        systemImage: "calendar"
                    )
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                    if !item.quantityDisplay.isEmpty {
                        Label(item.quantityDisplay, systemImage: "scalemass")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            Button("Edit", action: onEdit)
                .appFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .appFont(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

// MARK: - Add / edit sheet

private enum FridgeItemFormMode: Identifiable {
    case add(zone: FridgeZone)
    case edit(item: FridgeItem)

    var id: String {
        switch self {
        case .add(let zone): return "add-\(zone.id)"
        case .edit(let item): return "edit-\(item.id.uuidString)"
        }
    }
}

private struct FridgeItemFormSheet: View {
    let mode: FridgeItemFormMode
    let filterOwnerId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantityDisplay = ""
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedZone: FridgeZone
    @FocusState private var focusedField: Field?

    private enum Field { case name, quantity }

    init(mode: FridgeItemFormMode, filterOwnerId: String) {
        self.mode = mode
        self.filterOwnerId = filterOwnerId

        switch mode {
        case .add(let zone):
            _selectedZone = State(initialValue: zone)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _quantityDisplay = State(initialValue: item.quantityDisplay)
            _expirationDate = State(initialValue: item.expirationDate)
            _selectedZone = State(initialValue: item.zone)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("e.g. Greek yogurt", text: $name)
                        .textFieldStyle(.plain)
                        .appFont(.body)
                        .padding(14)
                        .boxStyle()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .quantity }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quantity")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("e.g. Half full, 1 bag", text: $quantityDisplay)
                        .textFieldStyle(.plain)
                        .appFont(.body)
                        .padding(14)
                        .boxStyle()
                        .focused($focusedField, equals: .quantity)
                        .submitLabel(.done)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Expires")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    DatePicker(
                        "Expiration",
                        selection: $expirationDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .boxStyle()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Zone")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("Zone", selection: $selectedZone) {
                        ForEach(FridgeZone.displayZones) { z in
                            Label(z.rawValue, systemImage: z.sfSymbol)
                                .tag(z)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(14)
                    .boxStyle()
                }

                if isEditing, case .edit(let item) = mode {
                    Button(role: .destructive) {
                        FridgeService.deleteItem(item, modelContext: modelContext)
                        dismiss()
                    } label: {
                        Text("Delete item")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "Edit item" : "Add item")
                        .nanumAppFont(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .onAppear {
                if !isEditing { focusedField = .name }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        switch mode {
        case .add:
            guard FridgeService.addItem(
                name: name,
                zone: selectedZone,
                expirationDate: expirationDate,
                quantityDisplay: quantityDisplay,
                ownerUserId: filterOwnerId,
                modelContext: modelContext
            ) != nil else { return }
        case .edit(let item):
            guard FridgeService.updateItem(
                item,
                name: name,
                zone: selectedZone,
                expirationDate: expirationDate,
                quantityDisplay: quantityDisplay,
                modelContext: modelContext
            ) else { return }
        }
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Fridge tab") {
    FridgeView(filterOwnerId: "preview-user")
        .modelContainer(for: [FridgeItem.self], inMemory: true)
}
#endif
