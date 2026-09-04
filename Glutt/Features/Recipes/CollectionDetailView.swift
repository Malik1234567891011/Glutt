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
                        message: "Add recipes from any recipe\u{2019}s menu \u{2014} look for \u{201C}Collections\u{201D}."
                    )
                } else {
                    ForEach(collection.recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCard(recipe: recipe)
                        }
                        .zoomCard(ZoomCardID(recipe.persistentModelID, slot: "collection"))
                        .simultaneousGesture(TapGesture().onEnded {
                            Haptics.impact(.light)
                        })
                        .contextMenu {
                            Button("Remove from collection", systemImage: "folder.badge.minus", role: .destructive) {
                                Haptics.notify(.warning)
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
                    Ph.dotsThreeCircle.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .alert("Rename collection", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                Haptics.notify(.success)
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    collection.name = trimmed
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \u{201C}\(collection.name)\u{201D}? Recipes stay in your library.",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete collection", role: .destructive) {
                Haptics.notify(.error)
                // Unhook any planned week pointing at this collection FIRST.
                //
                // `MealPlan.collection` is a to-one reference with no inverse
                // and therefore no delete rule, so deleting the collection used
                // to leave the plan holding a dangling row. The Recipes tab
                // reads `plan.collection?.recipes` while it builds the library
                // list, that tab is the one the app launches on, and the result
                // was an app that crashed on every launch until the plan was
                // gone too. Deleting a collection is a thing people do.
                let planID = collection.persistentModelID
                let plans = (try? context.fetch(FetchDescriptor<MealPlan>())) ?? []
                for plan in plans where plan.collection?.persistentModelID == planID {
                    plan.collection = nil
                }
                context.delete(collection)
                dismiss()
            }
        }
    }
}
