import SwiftUI

/// Purely decorative stand-in for the iOS share sheet, used by the import
/// tutorial. Not a real share sheet — original styling, no system chrome.
struct ShareSheetMock: View {
    var highlightGlutt: Bool

    private struct App: Identifiable {
        var id: String { name }
        let name: String
        let symbol: String
        let tint: Color
    }

    private let apps: [App] = [
        .init(name: "Messages", symbol: "message.fill", tint: .green),
        .init(name: "Notes", symbol: "note.text", tint: .yellow),
        .init(name: "Glutt", symbol: "fork.knife", tint: Theme.Colors.accent),
        .init(name: "Mail", symbol: "envelope.fill", tint: .blue),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Capsule()
                .fill(Theme.Colors.border)
                .frame(width: 36, height: 5)
                .padding(.top, Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.lg) {
                ForEach(apps) { app in
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(app.tint.opacity(0.18))
                                .frame(width: 56, height: 56)
                            Image(systemName: app.symbol)
                                .font(.title2)
                                .foregroundStyle(app.tint)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.Colors.accent,
                                              lineWidth: highlightGlutt && app.name == "Glutt" ? 3 : 0)
                        )
                        .scaleEffect(highlightGlutt && app.name == "Glutt" ? 1.08 : 1)
                        Text(app.name)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.15), radius: 16, y: -4)
    }
}

#Preview {
    ShareSheetMock(highlightGlutt: true)
        .padding()
        .background(Theme.Colors.background)
}
