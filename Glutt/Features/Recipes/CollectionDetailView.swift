import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var collection: RecipeCollection

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if collection.recipes.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "Empty collection",
                        message: "Add recipes from any recipe's menu — look for “Collections”."
                    )
                } else {
                    ForEach(collection.recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from collection", systemImage: "folder.badge.minus", role: .destructive) {
                                collection.recipes.removeAll { $0 === recipe }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        newName = collection.name
                        isRenaming = true
                    }
                    Button("Delete collection", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename collection", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    collection.name = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(collection.name)”? Recipes stay in your library.",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete collection", role: .destructive) {
                context.delete(collection)
                dismiss()
            }
        }
    }
}
