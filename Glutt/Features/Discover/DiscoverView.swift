// Glutt/Features/Discover/DiscoverView.swift
import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Bindable var model: DiscoverFeedViewModel
    let tasteTags: [String]
    @Environment(\.modelContext) private var context

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
                } else {
                    EmptyStateView(icon: "checkmark.circle",
                                   title: "That's everything",
                                   message: "Search another dish to keep discovering.")
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .task {
            if model.phase == .idle { await model.loadSuggested(tags: tasteTags) }
        }
    }

    private func retry() async {
        if model.videos.isEmpty { await model.loadSuggested(tags: tasteTags) }
    }
}
