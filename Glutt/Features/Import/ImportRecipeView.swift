import PhotosUI
import SwiftUI

/// Entry point for recipe import: paste a link or pick a screenshot.
/// On success, pushes the Import Review screen.
struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss

    /// Prefilled by the share extension / deep link, if present.
    var initialURL: URL?

    enum Phase {
        case input
        case loading(String)
        case failed(String)
        case review(ImportedRecipeDraft)
    }

    @State private var phase: Phase = .input
    @State private var urlText = ""
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    inputView
                case .loading(let message):
                    loadingView(message)
                case .failed(let message):
                    failureView(message)
                case .review(let draft):
                    ImportReviewView(draft: draft) {
                        dismiss()
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Import recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if let initialURL {
                urlText = initialURL.absoluteString
                startLinkImport()
            }
        }
        .onChange(of: photoItem) {
            guard photoItem != nil else { return }
            startPhotoImport()
        }
    }

    // MARK: - Input

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Paste a link")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("TikTok, Instagram, YouTube, or any recipe website.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    HStack {
                        TextField("https://…", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                        Button {
                            if let pasted = UIPasteboard.general.string {
                                urlText = pasted
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .padding(Theme.Spacing.sm)
                        }
                        .buttonStyle(.gluttPill)
                    }

                    Button("Import from link") {
                        startLinkImport()
                    }
                    .buttonStyle(.gluttPrimary)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Or use a screenshot")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("A photo of a recipe, cookbook page, or saved notes. Glutt reads the text on-device.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a screenshot", systemImage: "photo.on.rectangle")
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                    .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
                            )
                    }
                }
                .cardStyle()
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Import failed",
                message: message,
                actionLabel: "Try again",
                action: { phase = .input }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startLinkImport() {
        phase = .loading("Reading the recipe…")
        let urlString = urlText
        Task {
            do {
                var draft = try await RecipeImportService.importFrom(urlString: urlString)
                if DraftCleanup.wouldImprove(draft) {
                    phase = .loading("Cleaning it up with AI…")
                    draft = await DraftCleanup.cleanUp(draft)
                }
                if draft.ingredientLines.isEmpty, draft.isSocialVideo {
                    phase = .loading("No recipe in the caption — drafting the dish…")
                    draft = await DraftCleanup.reconstruct(draft)
                }
                phase = .review(draft)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func startPhotoImport() {
        phase = .loading("Reading the screenshot…")
        Task {
            do {
                guard let data = try await photoItem?.loadTransferable(type: Data.self) else {
                    throw ImportError.unreadableImage
                }
                var draft = try await RecipeImportService.importFrom(imageData: data)
                if DraftCleanup.wouldImprove(draft) {
                    phase = .loading("Cleaning it up with AI…")
                    draft = await DraftCleanup.cleanUp(draft)
                }
                phase = .review(draft)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            photoItem = nil
        }
    }
}
