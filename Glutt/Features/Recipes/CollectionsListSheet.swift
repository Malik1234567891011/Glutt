import SwiftData
import SwiftUI

/// A self-contained sheet listing the user's recipe collections, reachable from
/// the Recipes header `+` menu (Collections was cut from the Feed home surface but
/// kept reachable so saved collections are never orphaned).
struct CollectionsListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No collections yet",
                        message: "Group recipes into collections from the Recipes plus menu.",
                        actionLabel: nil,
                        action: nil
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            NavigationLink(value: collection) {
                                HStack(spacing: Theme.Spacing.md) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Theme.Colors.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name)
                                            .font(.gluttHeadline)
                                            .foregroundStyle(Theme.Colors.heading)
                                        Text("^[\(collection.recipes.count) recipe](inflect: true)")
                                            .font(.gluttCaption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationDestination(for: RecipeCollection.self) { CollectionDetailView(collection: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
