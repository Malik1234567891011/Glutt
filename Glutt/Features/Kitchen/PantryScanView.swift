import PhotosUI
import SwiftData
import SwiftUI

/// Photo → AI candidate list → user confirms → inventory updates.
/// Nothing is committed without a tap; wrong guesses cost one untoggle.
struct PantryScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    enum Phase {
        case pick
        case scanning
        case review
        case failed(String)
    }

    @State private var phase: Phase = .pick
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var items: [PantryScan.ScannedItem] = []
    @State private var didAddCount: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch phase {
                    case .pick:
                        pickView
                    case .scanning:
                        loadingView
                    case .review:
                        reviewView
                    case .failed(let message):
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Scan didn't work",
                            message: message,
                            actionLabel: "Try another photo",
                            action: { phase = .pick }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Scan your kitchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: photoItem) {
                guard photoItem != nil else { return }
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        await scan(data)
                    }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { data in
                    Task { await scan(data) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Phases

    private var pickView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Take one photo of your fridge, pantry, or counter. Glutt lists what it sees — you confirm before anything is added.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)

            if CameraPicker.isAvailable {
                Button {
                    Haptics.impact(.medium)
                    isShowingCamera = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Ph.camera.bold
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Open camera")
                            .font(.gluttHeadline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.images.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Choose a photo")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                )
            }

            Text("Tip: open the fridge door wide and step back a little — more visible labels, better guesses.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Looking at what you've got…")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl * 2)
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let didAddCount {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.checkCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Added \(didAddCount) items to your kitchen")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.successTint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            } else if items.isEmpty {
                EmptyStateView(
                    icon: "camera.metering.unknown",
                    title: "Nothing recognizable",
                    message: "Couldn't make out any food in that photo. Try better lighting or a closer shot.",
                    actionLabel: "Try again",
                    action: { phase = .pick }
                )
            } else {
                Text("Found \(items.count) items — untoggle anything wrong, tap the amount to adjust.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        itemRow($item)
                        if item != items.last {
                            Divider().overlay(Theme.Colors.border)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .cardStyle(padding: Theme.Spacing.xs)

                Button("Add \(includedCount) to my kitchen") {
                    Haptics.notify(.success)
                    commit()
                }
                .buttonStyle(.gluttPrimary)
                .disabled(includedCount == 0)

                Button("Scan another photo") {
                    Haptics.impact(.light)
                    items = []
                    phase = .pick
                }
                .buttonStyle(.gluttSecondary)
            }
        }
    }

    private func itemRow(_ item: Binding<PantryScan.ScannedItem>) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                Haptics.impact(.light)
                item.wrappedValue.include.toggle()
            } label: {
                if item.wrappedValue.include {
                    Ph.checkCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Ph.circle.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Theme.Colors.border)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.wrappedValue.name)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if item.wrappedValue.isAlreadyInPantry {
                    Text("already in your kitchen — will update the amount")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()

            Button {
                Haptics.impact(.light)
                item.wrappedValue.quantity = item.wrappedValue.quantity.next == .out
                    ? .full
                    : item.wrappedValue.quantity.next
            } label: {
                Chip(label: item.wrappedValue.quantity.label, isSelected: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var includedCount: Int {
        items.filter(\.include).count
    }

    // MARK: - Actions

    private func scan(_ rawData: Data) async {
        phase = .scanning
        didAddCount = nil
        guard let prepared = ImagePrep.prepareForVision(rawData) else {
            phase = .failed("Couldn't read that image.")
            return
        }
        do {
            items = try await PantryScan.scan(imageData: prepared, existingPantry: pantryItems)
            phase = .review
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func commit() {
        var added = 0
        for item in items where item.include {
            let canonical = IngredientCanonicalizer.canonicalize(item.name)
            if let existing = PantryMatcher.item(covering: canonical, in: pantryItems) {
                existing.roughQuantity = item.quantity
                existing.updatedAt = .now
            } else {
                context.insert(PantryItem(
                    name: item.name,
                    category: item.category,
                    roughQuantity: item.quantity
                ))
            }
            added += 1
        }
        withAnimation {
            didAddCount = added
            items = []
        }
    }
}
