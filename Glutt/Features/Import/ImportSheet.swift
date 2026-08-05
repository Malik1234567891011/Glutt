import SwiftUI

/// The recipe-import sheet: a card over the dimmed host app that reads the
/// recipe, confirms it landed, and gets out of the way. The user taps nothing
/// while it runs — parsing and saving both happen without input — so there is no
/// progress bar, no percentage and no review step.
///
/// Built 1:1 from block **2a** of the import design board (`design-loading/`).
/// The three states share one skeleton so nothing reflows as one becomes another.
///
/// Lives in the app target as well as the extension so the whole flow can be
/// staged in the simulator (`-importScreen`); the share extension is otherwise
/// almost impossible to drive there.
struct ImportSheet: View {
    @Bindable var viewModel: ShareImportViewModel
    let onViewRecipe: (UUID) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // The host app, dimmed. Nothing back here is tappable — closing is
            // the header's job, so a stray tap can't cancel an import in flight.
            Color.black.opacity(0.4)

            sheet.padding(.top, ImportSheetMetrics.sheetTop)
        }
        .ignoresSafeArea()
    }

    private var sheet: some View {
        ZStack(alignment: .top) {
            Theme.Colors.background

            VStack(spacing: 0) {
                ImportSheetHeader(
                    label: viewModel.headerLabel,
                    labelColor: headerColor,
                    onClose: close
                )
                Spacer(minLength: 0)
            }

            centre.padding(.top, centreTop)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                actions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: ImportSheetMetrics.sheetCorner,
                topTrailingRadius: ImportSheetMetrics.sheetCorner,
                style: .continuous
            )
        )
        // Contents settle in behind the system's sheet slide.
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.easeOut(duration: 0.32)) { hasAppeared = true }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.26), value: stateKey)
    }

    // MARK: - Centre block

    @ViewBuilder
    private var centre: some View {
        switch viewModel.state {
        case .importing(let progress):
            ImportingContent(stage: progress.stage)
                .transition(.opacity)

        case .saved(let draft):
            ImportOutcomeContent(
                outcome: .saved,
                imageData: draft.imageData ?? viewModel.sharedImageData,
                imageURLString: draft.imageURL,
                title: viewModel.dishTitle ?? "Saved to Glutt",
                message: viewModel.savedSummary(for: draft)
            )
            .transition(.opacity)

        case .failed(let reason):
            ImportOutcomeContent(
                outcome: .failed,
                imageData: viewModel.sharedImageData,
                imageURLString: nil,
                title: "No recipe in this one",
                message: "\(reason) Keep the link and it lands in your recipes, ready for you to finish."
            )
            .transition(.opacity)
        }
    }

    private var centreTop: CGFloat {
        if case .importing = viewModel.state {
            ImportSheetMetrics.loadingCentreTop
        } else {
            ImportSheetMetrics.outcomeCentreTop
        }
    }

    /// Amber on failure, never red — tomato is reserved for destructive actions.
    private var headerColor: Color {
        if case .failed = viewModel.state { Theme.Colors.amber } else { Theme.Colors.accent }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch viewModel.state {
        case .importing:
            // The design's "You can close this, Glutt finishes it for you" note
            // belongs here — but closing tears down the extension and the
            // pipeline with it, so the claim isn't true yet. Closing mid-import
            // hands the link to the app rather than losing it; the note earns
            // its place once the app finishes those on its own, unattended.
            EmptyView()

        case .saved(let draft):
            actionStack {
                ImportPrimaryButton(title: viewModel.returnActionLabel, action: onClose)
                ImportTextButton(title: "Open it in Glutt") { onViewRecipe(draft.id) }
            }

        case .failed:
            actionStack {
                // Keeping the link is a decision, not a detour: stub it into the
                // library and hand the user back to where they were.
                ImportPrimaryButton(title: "Keep the link anyway") {
                    viewModel.keepLink()
                    onClose()
                }
                ImportTextButton(title: "Try again") {
                    Task { await viewModel.start() }
                }
            }
        }
    }

    private func actionStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(.top, 18)
            .padding(.horizontal, ImportSheetMetrics.horizontal)
            .padding(.bottom, ImportSheetMetrics.bottomInset)
    }

    private func close() {
        // Mid-import this is the only chance to save the link before the
        // extension goes away.
        viewModel.abandon()
        onClose()
    }

    /// Animation trigger: which state we're in, not what's inside it — a new
    /// status line must not restage the whole sheet.
    private var stateKey: Int {
        switch viewModel.state {
        case .importing: 0
        case .saved:     1
        case .failed:    2
        }
    }
}
