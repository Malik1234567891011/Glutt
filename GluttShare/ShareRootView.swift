import SwiftUI

/// The share extension's root. The sheet itself is `ImportSheet`, shared with
/// the app so the flow can be staged in the simulator; this only owns the
/// terminal actions, which belong to the host controller.
struct ShareRootView: View {
    @State var viewModel: ShareImportViewModel
    let onViewRecipe: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        ImportSheet(viewModel: viewModel, onViewRecipe: onViewRecipe, onClose: onClose)
            .task { await viewModel.start() }
    }
}
