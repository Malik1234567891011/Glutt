import SwiftUI

extension View {
    /// Fires a selection tick whenever `value` changes — for system `Toggle`/`Stepper`/`Picker`
    /// that can't emit haptics natively. Mirrors the app's existing `.onChange { Haptics… }` pattern.
    ///
    ///   Toggle("Frozen", isOn: $isFrozen).hapticOnChange(of: isFrozen)
    func hapticOnChange<V: Equatable>(of value: V) -> some View {
        onChange(of: value) { _, _ in Haptics.selection() }
    }

    /// Fires a selection tick when the view is tapped, *without* consuming the tap — for
    /// `NavigationLink`s, which navigate but don't buzz. Runs alongside the link's own gesture.
    func hapticTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
    }
}
