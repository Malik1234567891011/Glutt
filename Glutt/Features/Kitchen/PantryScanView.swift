import PhotosUI
import SwiftData
import SwiftUI

/// Photo *or* spoken/typed list → AI candidates → user confirms → inventory.
/// Nothing is committed without a tap; wrong guesses cost one untoggle.
struct PantryScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    enum Phase {
        case pick
        case dictate
        case scanning
        case review
        case failed(String)
    }

    @State private var phase: Phase = .pick
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var items: [PantryScan.ScannedItem] = []
    /// Which path produced `items` — the camera or the voice description. Read
    /// by `commit()`, which cannot otherwise tell them apart.
    @State private var lastInputMethod = "scan"
    @State private var didAddCount: Int?
    @State private var descriptionText = ""
    @State private var dictation = PantryDictationSession()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch phase {
                    case .pick:
                        pickView
                    case .dictate:
                        dictateView
                    case .scanning:
                        loadingView
                    case .review:
                        reviewView
                    case .failed(let message):
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "That didn’t work",
                            message: message,
                            actionLabel: "Try again",
                            action: { phase = .pick }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dictation.stop()
                        dismiss()
                    }
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
            .onChange(of: dictation.transcript) { _, newValue in
                if !newValue.isEmpty { descriptionText = newValue }
            }
            .onDisappear { dictation.stop() }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { data in
                    Task { await scan(data) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var navTitle: String {
        switch phase {
        case .dictate: "Tell us what you have"
        case .review: "Confirm items"
        default: "Add to kitchen"
        }
    }

    // MARK: - Phases

    private var pickView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Scan a fridge photo, or just say what’s there — Glutt lists candidates and you confirm before anything is added.")
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
                        Text("Scan with a photo")
                            .font(.gluttHeadline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                outlinedRow {
                    Ph.images.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Choose a photo")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            Button {
                Haptics.impact(.light)
                descriptionText = dictation.transcript
                phase = .dictate
            } label: {
                outlinedRow {
                    MS.micFill.sized(20).foregroundStyle(Theme.Colors.accent)
                    Text("Tell us what you have")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .buttonStyle(.plain)

            Text("Tip: open the fridge door wide and step back — or rattle off everything casually if you’re not home.")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var dictateView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Say or type what’s in your kitchen. “Eggs, leftover rice, half an onion, soy sauce…” is perfect.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField("What’s in your kitchen?", text: $descriptionText, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(4...10)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.textPrimary.opacity(0.08), lineWidth: 1)
                )

            Button {
                Haptics.impact(.medium)
                Task { await toggleDictation() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    MS.micFill.sized(20)
                        .foregroundStyle(dictation.isListening ? Theme.Colors.creamText : Theme.Colors.accent)
                    Text(dictation.isListening ? "Listening… tap to stop" : "Tap to talk")
                        .font(.gluttHeadline)
                        .foregroundStyle(dictation.isListening ? Theme.Colors.creamText : Theme.Colors.accent)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(dictation.isListening ? Theme.Colors.accent : Theme.Colors.card)
                )
                .overlay(
                    dictation.isListening
                        ? nil
                        : RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            if let error = dictation.errorMessage {
                Text(error)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.tomato)
            }

            Button {
                Haptics.impact(.medium)
                Task { await parseDescription() }
            } label: {
                Text("Find ingredients")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gluttPrimary)
            .disabled(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Back") {
                dictation.stop()
                phase = .pick
            }
            .buttonStyle(.gluttSecondary)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Looking at what you’ve got…")
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
                    message: "Couldn’t make out any food there. Try a clearer photo, or say the items more plainly.",
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
                        if item.id != items.last?.id {
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

                Button("Add more") {
                    Haptics.impact(.light)
                    items = []
                    descriptionText = ""
                    dictation.resetTranscript()
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

    // MARK: - Shared chrome

    private func outlinedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.sm, content: content)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
            )
    }

    // MARK: - Actions

    private func toggleDictation() async {
        if dictation.isListening {
            dictation.stop()
            return
        }
        guard await dictation.requestAccess() else { return }
        dictation.start()
    }

    private func scan(_ rawData: Data) async {
        phase = .scanning
        didAddCount = nil
        lastInputMethod = "scan"
        Analytics.capture(.aiToolUsed, ["tool": "pantry_scan"])
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

    private func parseDescription() async {
        dictation.stop()
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        phase = .scanning
        didAddCount = nil
        lastInputMethod = "voice"
        Analytics.capture(.aiToolUsed, ["tool": "pantry_voice"])
        do {
            items = try await PantryScan.fromDescription(text, existingPantry: pantryItems)
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
        if added > 0 {
            Analytics.capture(.pantryItemAdded, ["method": lastInputMethod, "count": added])
        }
        withAnimation {
            didAddCount = added
            items = []
        }
    }
}
