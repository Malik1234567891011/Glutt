import SwiftUI

/// Compact pill stepper — `–  value  +` in a bordered capsule — matching the redesign's
/// servings control. Each tap fires a selection tick (a system `Stepper` can't buzz natively),
/// and the buttons disable at the range bounds.
///
/// Usage:
///   GluttStepper(value: $servings, in: 1...24, step: 1) { "\($0) serv" }
struct GluttStepper<Value: Strideable>: View where Value.Stride: SignedNumeric {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let format: (Value) -> String

    init(value: Binding<Value>,
         in range: ClosedRange<Value>,
         step: Value.Stride,
         format: @escaping (Value) -> String) {
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        HStack(spacing: 4) {
            stepButton(Ph.minus.bold, enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value.advanced(by: -step))
            }
            Text(format(value))
                .font(BrandFont.nunito(13, 800))
                .foregroundColor(Theme.Colors.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 52)
            stepButton(Ph.plus.bold, enabled: value < range.upperBound) {
                value = min(range.upperBound, value.advanced(by: step))
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.Colors.background)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
    }

    private func stepButton(_ icon: Image, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundColor(enabled ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.35))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

#Preview("GluttStepper") {
    struct Demo: View {
        @State private var servings = 4
        var body: some View {
            GluttStepper(value: $servings, in: 1...24, step: 1) { "\($0) serv" }
                .padding()
                .background(Theme.Colors.background)
        }
    }
    return Demo()
}
