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
        case loading(ImportPipeline.Progress)
        case failed(String)
        case review(ImportedRecipeDraft)
    }

    @State private var phase: Phase = .input
    @State private var urlText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingShareSetup = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    inputView
                case .loading(let progress):
                    loadingView(progress)
                case .failed(let reason):
                    failureView(reason)
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
                shareCard

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Paste a link")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("TikTok, Instagram, YouTube, Pinterest, Reddit, or any recipe website.")
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
                            Haptics.impact(.light)
                            if let pasted = UIPasteboard.general.string {
                                urlText = pasted
                            }
                        } label: {
                            Ph.clipboard.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .padding(Theme.Spacing.sm)
                        }
                        .buttonStyle(.gluttPill)
                    }

                    Button("Import from link") {
                        Haptics.impact(.medium)
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
                        HStack(spacing: Theme.Spacing.sm) {
                            Ph.image.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Choose a screenshot")
                                .font(.gluttHeadline)
                        }
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
        .sheet(isPresented: $isShowingShareSetup) {
            ShareSheetSetupView()
        }
    }

    /// The best import path is also the least obvious, so it leads.
    private var shareCard: some View {
        Button {
            Haptics.impact(.light)
            isShowingShareSetup = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Ph.export.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save straight from TikTok & Instagram")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Tap Share in any app → Glutt. See how →")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    /// The same wait the share sheet shows — one visual, the dish name as soon
    /// as it's known, one status line. See `ImportProgressViews`.
    private func loadingView(_ progress: ImportPipeline.Progress) -> some View {
        ImportingContent(stage: progress.stage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ reason: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ImportOutcomeContent(
                outcome: .failed,
                imageData: nil,
                imageURLString: nil,
                title: "No recipe in this one",
                message: keptLinkOffer(after: reason)
            )
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if !trimmedURL.isEmpty {
                    ImportPrimaryButton(title: "Keep the link anyway") {
                        var stub = ImportedRecipeDraft()
                        stub.sourceURL = trimmedURL
                        stub.platform = SourcePlatform(urlString: trimmedURL)
                        phase = .review(stub)
                    }
                }
                ImportTextButton(title: "Try again") { phase = .input }
            }
            .padding(.horizontal, ImportSheetMetrics.horizontal)
            .padding(.bottom, Theme.Spacing.md)
        }
    }

    /// Only offer to keep something there is something to keep.
    private func keptLinkOffer(after reason: String) -> String {
        trimmedURL.isEmpty
            ? reason
            : "\(reason) Keep the link and it lands in your recipes, ready for you to finish."
    }

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actions

    private func startLinkImport() {
        phase = .loading(ImportPipeline.Progress(stage: .reading))
        let urlString = urlText
        // Success has no event of its own: a start with no `recipe_created`
        // behind it is the drop-off, and reaching review is not the same as
        // keeping the recipe.
        Analytics.capture(.importStarted, ["source": "link"])
        Task {
            do {
                let draft = try await ImportPipeline.run(urlString: urlString) { progress in
                    phase = .loading(progress)
                }
                Haptics.notify(.success)
                phase = .review(draft)
            } catch {
                Haptics.notify(.error)
                Analytics.capture(.importFailed, ["source": "link", "reason": error.localizedDescription])
                phase = .failed(ImportPipeline.failureReason(for: error))
            }
        }
    }

    private func startPhotoImport() {
        phase = .loading(ImportPipeline.Progress(stage: .reading))
        Analytics.capture(.importStarted, ["source": "screenshot"])
        Task {
            do {
                guard let data = try await photoItem?.loadTransferable(type: Data.self) else {
                    throw ImportError.unreadableImage
                }
                var draft = try await RecipeImportService.importFrom(imageData: data)
                if DraftCleanup.wouldImprove(draft) {
                    phase = .loading(ImportPipeline.Progress(stage: .cleaning, title: draft.title))
                    draft = await DraftCleanup.cleanUp(draft)
                }
                if draft.stepTexts.isEmpty, !draft.ingredientLines.isEmpty {
                    phase = .loading(ImportPipeline.Progress(stage: .steps, title: draft.title))
                    draft = await DraftCleanup.inferSteps(draft)
                }
                Haptics.notify(.success)
                phase = .review(draft)
            } catch {
                Haptics.notify(.error)
                Analytics.capture(.importFailed, ["source": "screenshot", "reason": error.localizedDescription])
                phase = .failed(ImportPipeline.failureReason(for: error))
            }
            photoItem = nil
        }
    }
}
