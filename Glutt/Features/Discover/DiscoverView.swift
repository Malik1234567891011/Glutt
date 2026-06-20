// Glutt/Features/Discover/DiscoverView.swift
import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Bindable var model: DiscoverFeedViewModel
    let tasteTags: [String]
    @Environment(\.modelContext) private var context

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { model.saveError != nil },
            set: { if !$0 { model.clearSaveError() } }
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            case .empty:
                EmptyStateView(icon: "magnifyingglass",
                               title: "No clips found",
                               message: "Try another dish — like \"tofu stir fry\" or \"lemon chicken\".")
            case .failed(let message):
                EmptyStateView(icon: "wifi.slash",
                               title: "Couldn't load videos",
                               message: message,
                               actionLabel: "Try again",
                               action: { Task { await retry() } })
            case .loaded:
                if let video = model.current {
                    DiscoverCardView(
                        video: video,
                        isSaving: model.savingVideoID == video.videoId,
                        isSaved: model.savedVideoIDs.contains(video.videoId),
                        onSave: { Task { await model.save(video, into: context) } },
                        onNext: { Task { await model.showNext() } }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .task {
            if model.phase == .idle { await model.loadSuggested(tags: tasteTags) }
        }
        .alert("Couldn't save recipe", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) { model.clearSaveError() }
        } message: {
            Text(model.saveError ?? "")
        }
    }

    private func retry() async {
        if model.query.isEmpty {
            await model.loadSuggested(tags: tasteTags)
        } else {
            await model.search(model.query)
        }
    }
}
