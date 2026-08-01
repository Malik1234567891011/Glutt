import SwiftData
import SwiftUI

/// Kitchen › Tools: a checklist of equipment you own. Presets come from
/// `KitchenToolCatalog`; checking one stores a `KitchenTool`, unchecking removes
/// it. Custom tools live in their own section. Polly and recipe "missing gear"
/// badges read the owned set.
struct ToolsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \KitchenTool.name) private var owned: [KitchenTool]
    @State private var isAddingCustom = false
    @State private var customName = ""

    private var ownedCanonical: Set<String> { Set(owned.map(\.canonicalName)) }

    /// Owned tools that aren't presets — the user's own additions.
    private var customTools: [KitchenTool] {
        owned.filter { !KitchenToolCatalog.canonicalAll.contains($0.canonicalName) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                intro
                ForEach(KitchenToolCatalog.groups, id: \.category) { group in
                    presetSection(group.category, tools: group.tools)
                }
                customSection
            }
            .padding(Theme.Spacing.md)
        }
        .alert("Add a tool", isPresented: $isAddingCustom) {
            TextField("e.g. Sous vide, mortar & pestle", text: $customName)
            Button("Add") { addCustom() }
            Button("Cancel", role: .cancel) { customName = "" }
        } message: {
            Text("Anything not in the lists above.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's in your kitchen?")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Check off the gear you own. Chef uses it while you cook, and recipes flag when they need something you don't have.")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func presetSection(_ category: String, tools: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: category)
                .padding(.leading, Theme.Spacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                    toolRow(tool, category: category)
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.md)
                    if index < tools.count - 1 {
                        Divider()
                            .overlay(Theme.Colors.border)
                            .padding(.leading, Theme.Spacing.md)
                    }
                }
            }
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
            )
        }
    }

    private func toolRow(_ tool: String, category: String) -> some View {
        let isOwned = ownedCanonical.contains(tool.lowercased())
        return Button {
            Haptics.impact(.light)
            toggle(tool, category: category, isOwned: isOwned)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(tool)
                    .font(.gluttBody.weight(.medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                checkmark(isOwned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkmark(_ isOwned: Bool) -> some View {
        Group {
            if isOwned {
                Ph.check.bold
                    .resizable().scaledToFit().frame(width: 13, height: 13)
                    .foregroundStyle(Theme.Colors.creamText)
                    .frame(width: 26, height: 26)
                    .background(Theme.Colors.accent)
                    .clipShape(Circle())
            } else {
                Circle()
                    .strokeBorder(Theme.Colors.border, lineWidth: 1.5)
                    .frame(width: 26, height: 26)
            }
        }
    }

    // MARK: - Custom

    private var customSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(text: "Your own")
                .padding(.leading, Theme.Spacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(customTools.enumerated()), id: \.element.id) { index, tool in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(tool.name)
                            .font(.gluttBody.weight(.medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Button {
                            Haptics.notify(.warning)
                            context.delete(tool)
                        } label: {
                            Ph.x.regular
                                .resizable().scaledToFit().frame(width: 12, height: 12)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(Theme.Colors.border, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    if index < customTools.count - 1 {
                        Divider().overlay(Theme.Colors.border).padding(.leading, Theme.Spacing.md)
                    }
                }

                if !customTools.isEmpty {
                    Divider().overlay(Theme.Colors.border).padding(.leading, Theme.Spacing.md)
                }
                Button {
                    Haptics.impact(.light)
                    customName = ""
                    isAddingCustom = true
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Ph.plus.bold
                            .resizable().scaledToFit().frame(width: 13, height: 13)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Add your own")
                            .font(.gluttBody.weight(.bold))
                            .foregroundStyle(Theme.Colors.accent)
                        Spacer()
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
            )
        }
    }

    // MARK: - Mutations

    private func toggle(_ tool: String, category: String, isOwned: Bool) {
        if isOwned {
            if let existing = owned.first(where: { $0.canonicalName == tool.lowercased() }) {
                context.delete(existing)
            }
        } else {
            context.insert(KitchenTool(name: tool, category: category))
        }
    }

    private func addCustom() {
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        customName = ""
        guard !trimmed.isEmpty else { return }
        // Ignore duplicates (including presets typed by hand).
        guard !ownedCanonical.contains(trimmed.lowercased()) else { return }
        context.insert(KitchenTool(name: trimmed, category: KitchenToolCatalog.category(for: trimmed)))
    }
}
