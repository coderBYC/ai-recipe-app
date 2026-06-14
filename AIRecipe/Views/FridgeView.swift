import SwiftData
import SwiftUI

// MARK: - Main tab

struct FridgeView: View {
    let filterOwnerId: String

    @Environment(\.modelContext) private var modelContext
    @State private var selectedZone: FridgeZone?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                InteractiveFridgeGraphic(hotspots: FridgeLayout.hotspots) { zone in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectedZone = zone
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(AppTheme.surface.ignoresSafeArea())
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
            .sheet(item: $selectedZone) { zone in
                FridgeZoneItemsSheet(zone: zone, filterOwnerId: filterOwnerId)
            }
        }
    }
}

// MARK: - Illustration + hotspots

private struct FridgeHotspot: Identifiable {
    let zone: FridgeZone
    /// Normalized rect within the fridge image (0…1).
    let rect: CGRect

    var id: String { zone.id }
}

private enum FridgeLayout {
    /// Normalized tap rects for `fridge` asset (760×900 interior photo).
    static let hotspots: [FridgeHotspot] = [
        // Upper cavity — left / right halves
        FridgeHotspot(zone: .leftDoor, rect: CGRect(x: 0.03, y: 0.14, width: 0.47, height: 0.58)),
        FridgeHotspot(zone: .rightDoor, rect: CGRect(x: 0.50, y: 0.14, width: 0.47, height: 0.58)),
        FridgeHotspot(zone: .bottomShelf, rect: CGRect(x: 0.50, y: 0.14, width: 0.47, height: 0.58)),
        FridgeHotspot(zone: .middleShelf, rect: CGRect(x: 0.50, y: 0.14, width: 0.47, height: 0.58)),
        FridgeHotspot(zone: .topShelf, rect: CGRect(x: 0.50, y: 0.14, width: 0.47, height: 0.58)),
        // Bottom crisper drawers — product preserver
        FridgeHotspot(zone: .crisperDrawer, rect: CGRect(x: 0.03, y: 0.74, width: 0.94, height: 0.22)),
        FridgeHotspot(zone: .freezer, rect: CGRect(x: 0.03, y: 0.74, width: 0.94, height: 0.22)),
    ]
}

private struct InteractiveFridgeGraphic: View {
    let hotspots: [FridgeHotspot]
    var showsHotspotOverlay: Bool = false
    var onZoneTapped: (FridgeZone) -> Void

    var body: some View {
        Image("fridge")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height

                    ForEach(hotspots) { hotspot in
                        Button {
                            onZoneTapped(hotspot.zone)
                        } label: {
                            ZStack {
                                if showsHotspotOverlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(overlayColor(for: hotspot.zone).opacity(0.38))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(overlayColor(for: hotspot.zone), lineWidth: 2)
                                        }
                                    Text(hotspot.zone.rawValue)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(.black.opacity(0.55), in: Capsule())
                                } else {
                                    Color.clear
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(
                            width: hotspot.rect.width * width,
                            height: hotspot.rect.height * height
                        )
                        .position(
                            x: hotspot.rect.midX * width,
                            y: hotspot.rect.midY * height
                        )
                        .accessibilityLabel(hotspot.zone.rawValue)
                        .accessibilityHint("Shows items stored in this area")
                    }
                }
            }
            .accessibilityHidden(!showsHotspotOverlay)
    }

    private func overlayColor(for zone: FridgeZone) -> Color {
        switch zone {
        case .leftDoor: return .blue
        case .rightDoor: return .green
        case .crisperDrawer: return .orange
        default: return .purple
        }
    }
}

// MARK: - Zone item list sheet

private struct FridgeZoneItemsSheet: View {
    let zone: FridgeZone
    let filterOwnerId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [FridgeItem]
    @State private var showAddItemSheet = false

    init(zone: FridgeZone, filterOwnerId: String) {
        self.zone = zone
        self.filterOwnerId = filterOwnerId
        let oid = filterOwnerId
        let zoneRaw = zone.rawValue
        _items = Query(
            filter: #Predicate<FridgeItem> {
                $0.ownerUserId == oid && $0.zoneRaw == zoneRaw
            },
            sort: [
                SortDescriptor(\.expirationDate),
                SortDescriptor(\.name),
            ]
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: zone.sfSymbol,
                        description: Text("Tap + to add food to \(zone.rawValue.lowercased()).")
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            FridgeItemRow(item: item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(zone.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItemSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(AppTheme.bitterFont(size: 18, weight: .regular))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .accessibilityLabel("Add item")
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddFridgeItemSheet(zone: zone, filterOwnerId: filterOwnerId)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            FridgeService.deleteItem(items[index], modelContext: modelContext)
        }
    }
}

private struct FridgeItemRow: View {
    let item: FridgeItem

    private static let expirationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .appFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
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

// MARK: - Add item sheet

private struct AddFridgeItemSheet: View {
    let zone: FridgeZone
    let filterOwnerId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantityDisplay = ""
    @State private var expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var selectedZone: FridgeZone
    @FocusState private var focusedField: Field?

    private enum Field { case name, quantity }

    init(zone: FridgeZone, filterOwnerId: String) {
        self.zone = zone
        self.filterOwnerId = filterOwnerId
        _selectedZone = State(initialValue: zone)
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
                        ForEach(FridgeZone.interactiveZones) { z in
                            Label(z.rawValue, systemImage: z.sfSymbol)
                                .tag(z)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(14)
                    .boxStyle()
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
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .principal) {
                    Text("Add item")
                        .nanumAppFont(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .onAppear { focusedField = .name }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard FridgeService.addItem(
            name: name,
            zone: selectedZone,
            expirationDate: expirationDate,
            quantityDisplay: quantityDisplay,
            ownerUserId: filterOwnerId,
            modelContext: modelContext
        ) != nil else { return }
        dismiss()
    }
}

// MARK: - Previews

#if DEBUG
private struct FridgeHotspotTuningPreview: View {
    @State private var rects: [FridgeZone: CGRect] = [
        .leftDoor: CGRect(x: 0.00, y: 0.07, width: 0.21, height: 0.81),
        .rightDoor: CGRect(x: 0.72, y: 0.70, width: 0.23, height: 0.80),
        .crisperDrawer: CGRect(x: 0.24, y: 0.71, width: 0.43, height: 0.84),
        .bottomShelf: CGRect(x: 0.03, y: 0.40, width: 0.94, height: 0.30),
        .middleShelf: CGRect(x: 0.03, y: 0.30, width: 0.94, height: 0.10),
        .topShelf: CGRect(x: 0.03, y: 0.00, width: 0.94, height: 0.30),
        .freezer: CGRect(x: 0.03, y: 0.22, width: 0.94, height: 0.10)
    ]
    @State private var selectedZone: FridgeZone = .leftDoor

    private var hotspots: [FridgeHotspot] {
        FridgeZone.interactiveZones.compactMap { zone in
            guard let rect = rects[zone] else { return nil }
            return FridgeHotspot(zone: zone, rect: rect)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    InteractiveFridgeGraphic(
                        hotspots: hotspots,
                        showsHotspotOverlay: true
                    ) { zone in
                        selectedZone = zone
                    }
                    .padding(.horizontal, 20)

                    tuningControls
                    copyPasteBlock
                }
                .padding(.bottom, 24)
            }
            .background(AppTheme.surface)
            .navigationTitle("Hotspot tuning")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var tuningControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected zone")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Picker("Zone", selection: $selectedZone) {
                ForEach(FridgeZone.interactiveZones) { zone in
                    Text(zone.rawValue).tag(zone)
                }
            }
            .pickerStyle(.segmented)

            sliderRow("X", value: rectBinding(\.origin.x), range: 0...0.95)
            sliderRow("Y", value: rectBinding(\.origin.y), range: 0...0.95)
            sliderRow("Width", value: rectBinding(\.size.width), range: 0.05...1)
            sliderRow("Height", value: rectBinding(\.size.height), range: 0.05...1)
        }
        .padding(.horizontal, 20)
    }

    private var copyPasteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste into FridgeLayout.hotspots")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text(hotspotCodeSnippet)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .boxStyle()
        }
        .padding(.horizontal, 20)
    }

    private var hotspotCodeSnippet: String {
        let lines = FridgeZone.interactiveZones.compactMap { zone -> String? in
            guard let r = rects[zone] else { return nil }
            let caseName: String
            switch zone {
            case .leftDoor: caseName = "leftDoor"
            case .rightDoor: caseName = "rightDoor"
            case .crisperDrawer: caseName = "crisperDrawer"
            default: caseName = zone.rawValue
            }
            return String(
                format: "FridgeHotspot(zone: .%@, rect: CGRect(x: %.2f, y: %.2f, width: %.2f, height: %.2f)),",
                caseName,
                r.origin.x, r.origin.y, r.size.width, r.size.height
            )
        }
        return lines.joined(separator: "\n")
    }

    private func sliderRow(
        _ label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Slider(value: value, in: range, step: 0.01)
        }
    }

    private func rectBinding(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { rects[selectedZone]?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                var rect = rects[selectedZone] ?? .zero
                rect[keyPath: keyPath] = newValue
                rects[selectedZone] = rect
            }
        )
    }
}

#Preview("Fridge — hotspot tuning") {
    FridgeHotspotTuningPreview()
}

#Preview("Fridge tab") {
    FridgeView(filterOwnerId: "preview-user")
        .modelContainer(for: [FridgeItem.self], inMemory: true)
}
#endif
