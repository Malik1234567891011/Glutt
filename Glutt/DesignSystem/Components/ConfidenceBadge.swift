import SwiftUI

/// Shows how confident the app is about imported/estimated data.
/// Used for import confidence and calorie estimate ranges — honesty over fake precision.
struct ConfidenceBadge: View {
    /// 0.0–1.0
    let confidence: Double

    private var label: String {
        switch confidence {
        case 0.85...: "High confidence"
        case 0.6...: "Mostly confident"
        default: "Needs review"
        }
    }

    private var tint: Color {
        switch confidence {
        case 0.85...: Theme.Colors.accent
        case 0.6...: Theme.Colors.warning
        default: Theme.Colors.tomato
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: confidence >= 0.85 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(label)
                .font(.gluttCaption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}
