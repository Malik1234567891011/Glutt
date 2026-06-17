import SwiftUI
import UIKit

/// The share-sheet UI. Terminal actions (open app, close) are owned by the host
/// controller, so they're passed in as closures.
struct ShareRootView: View {
    @State var viewModel: ShareImportViewModel
    let sourceURLString: String
    let onViewRecipe: (UUID) -> Void
    let onClose: () -> Void
    let onOpenInApp: (String) -> Void

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            switch viewModel.state {
            case .importing(let message): importing(message)
            case .preview:                preview
            case .saved:                  saved
            case .failed(let message):    failed(message)
            }
        }
        .task { await viewModel.start() }
    }

    // MARK: - States

    private func importing(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.large)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(Theme.Spacing.lg)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                recipeImage

                TextField("Recipe title", text: $viewModel.editableTitle)
                    .font(.gluttTitle)
                if let creator = viewModel.draft?.creator {
                    Text("by \(creator)")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Stepper("Servings: \(viewModel.editableServings)",
                        value: $viewModel.editableServings, in: 1...24)
                    .font(.gluttBody)

                Text(summaryLine)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if let lines = viewModel.draft?.ingredientLines, !lines.isEmpty {
                    section(title: "INGREDIENTS") {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text("•  \(line)")
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let steps = viewModel.draft?.stepTexts, !steps.isEmpty {
                    section(title: "STEPS") {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                            Text("\(index + 1).  \(text)")
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Button("Save recipe") { viewModel.save() }
                    .buttonStyle(.gluttPrimary)
                Button("Discard", role: .destructive) { onClose() }
                    .font(.gluttCaption)
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.md)
        }
    }

    /// Prefer the share sheet's image bytes (e.g. an IG reel thumbnail), then a
    /// scraped/oembed URL. Shows nothing when neither is available.
    @ViewBuilder
    private var recipeImage: some View {
        if let data = viewModel.draft?.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if let urlString = viewModel.draft?.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Theme.Colors.accent.opacity(0.08))
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else {
            // No thumbnail available (e.g. Instagram reels, which expose none) —
            // a branded placeholder reads as intentional, not broken.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.08))
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.Colors.accent.opacity(0.5))
                )
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saved: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.accent)
            Text("Saved to Glutt")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Button("Add more recipes") { onClose() }
                .buttonStyle(.gluttPrimary)
            Button("View recipe") {
                if let id = viewModel.draft?.id { onViewRecipe(id) }
            }
            .font(.gluttHeadline)
            .foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.lg)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.warning)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Button("Open in Glutt") { onOpenInApp(sourceURLString) }
                .buttonStyle(.gluttPrimary)
            Button("Close") { onClose() }
                .font(.gluttCaption)
        }
        .padding(Theme.Spacing.lg)
    }

    private var summaryLine: String {
        let draft = viewModel.draft
        let ingredients = draft?.ingredientLines.count ?? 0
        let steps = draft?.stepTexts.count ?? 0
        let minutes = (draft?.prepMinutes ?? 0) + (draft?.cookMinutes ?? 0)
        var parts = ["\(ingredients) ingredients", "\(steps) steps"]
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }
}
