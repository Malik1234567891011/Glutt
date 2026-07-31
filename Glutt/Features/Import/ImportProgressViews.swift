import AVFoundation
import SwiftUI
import UIKit

/// The recipe-import presentation, shared by the share extension (`ShareRootView`)
/// and the in-app import sheet (`ImportRecipeView`).
///
/// Every value here is lifted from block **2a** of the import design board
/// (`design-loading/`). The flow is presentation only: the user taps nothing
/// while a recipe is being read, so there is no progress bar, no percentage and
/// no step counter — one visual, the dish name, and one honest status line.
///
/// Glyph sizes are the one deliberate translation. The board is drawn with
/// Material Symbols, whose point size is the em box; the same number in SF
/// Symbols renders noticeably larger, so glyphs are specified here at the size
/// that matches the reference render rather than at the board's raw value.
enum ImportSheetMetrics {
    /// Distance from the top of the screen to the top of the sheet.
    static let sheetTop: CGFloat = 56
    static let sheetCorner: CGFloat = 26
    static let horizontal: CGFloat = 20
    /// The centre block is pinned, not flowed, so the three states line up
    /// exactly and nothing reflows as one becomes another.
    static let loadingCentreTop: CGFloat = 158
    static let outcomeCentreTop: CGFloat = 150
    /// The cooking loop, rendered 1:1 from a square crop of the source clip.
    static let visual: CGFloat = 338
    static let photo: CGFloat = 214
    static let photoCorner: CGFloat = 26
    static let badge: CGFloat = 52
    static let bottomInset: CGFloat = 34
}

extension View {
    /// The board's CSS `line-height` multiplier, resolved against real font
    /// metrics. SwiftUI's `lineSpacing` is the gap *added* to the font's own
    /// line height, not the line height itself — passing the multiplier straight
    /// through (`lineSpacing(15 * 1.45)`) blows wrapped text apart.
    func designLineHeight(_ multiple: CGFloat, _ font: UIFont) -> some View {
        lineSpacing(max(0, multiple * font.pointSize - font.lineHeight))
    }
}

// MARK: - Sheet chrome

/// Grabber, source label and close button. Identical across all three states.
struct ImportSheetHeader: View {
    let label: String
    var labelColor: Color = Theme.Colors.accent
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.Colors.dotInactive)
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            HStack(alignment: .center, spacing: 12) {
                Text(label.uppercased())
                    .font(BrandFont.nunito(12, 800))
                    .tracking(1.6)
                    .foregroundStyle(labelColor)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.Colors.surface3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.top, 16)
            .padding(.horizontal, ImportSheetMetrics.horizontal)
        }
    }
}

// MARK: - Importing

/// The whole wait: the cooking loop, the dish name as soon as Glutt knows it,
/// and the current pipeline stage. Nothing else.
struct ImportingContent: View {
    /// `nil` until the source has given up a name — skeleton bars until then.
    let title: String?
    let stage: ImportPipeline.Stage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            CookingLoopView()

            ImportTitleBlock(title: title)
                .padding(.top, 24)

            // Any stage can be skipped, so any string has to be able to follow
            // any other — crossfade rather than slide.
            Text(stage.label)
                .font(BrandFont.nunito(13.5, 600))
                .foregroundStyle(Theme.Colors.mutedSoft)
                .multilineTextAlignment(.center)
                .id(stage)
                .transition(.opacity)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.22), value: stage)
    }
}

/// The dish name, or two skeleton bars that crossfade into it when it lands.
private struct ImportTitleBlock: View {
    let title: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let title, !title.isEmpty {
                Text(title)
                    .font(BrandFont.bricolage(21, 600))
                    .tracking(-0.4)
                    .designLineHeight(1.2, BrandFont.uiBricolage(21, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6)),
                                removal: .opacity
                            )
                    )
            } else {
                skeleton.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: title)
    }

    private var skeleton: some View {
        GeometryReader { proxy in
            VStack(spacing: 9) {
                bar(width: proxy.size.width * 0.60)
                bar(width: proxy.size.width * 0.38)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 31)
        .accessibilityLabel("Reading the dish name")
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.Colors.segmentTrack)
            .frame(width: width, height: 11)
    }
}

// MARK: - Cooking loop

/// The looping cooking animation. The clip is cropped square and colour-matched
/// to `Theme.Colors.background` at build time (see `design-loading/README.md`),
/// so it composites straight onto the sheet — no container, border or shadow.
struct CookingLoopView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LoopingVideo(resource: "cooking-loop", isPlaying: !reduceMotion)
            .frame(width: ImportSheetMetrics.visual, height: ImportSheetMetrics.visual)
            .accessibilityHidden(true)
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let resource: String
    /// Reduce Motion holds the poster frame instead of looping.
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else { return view }

        let player = AVQueuePlayer()
        player.isMuted = true
        // The shipped asset has no audio track at all, so playback can never
        // duck or interrupt the host app's audio — there is no session to
        // configure, which is the safest thing a share extension can do.
        context.coordinator.looper = AVPlayerLooper(
            player: player,
            templateItem: AVPlayerItem(url: url)
        )
        context.coordinator.player = player
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = context.coordinator.player else { return }
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Outcome (saved / could not read)

/// The saved and failed screens. Same skeleton as `ImportingContent` so the
/// transition happens in place, with the animation replaced by the recipe photo.
struct ImportOutcomeContent: View {
    enum Outcome {
        case saved
        case failed
    }

    let outcome: Outcome
    let imageData: Data?
    let imageURLString: String?
    let title: String
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card stack scaling in behind the photo.
    @State private var hasSettled = false
    /// The badge springing in, a beat after the stack.
    @State private var badgeSettled = false
    @State private var isFloating = false
    @State private var tickProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            visual

            Text(title)
                .font(BrandFont.bricolage(27, 700))
                .tracking(-0.7)
                .designLineHeight(1.1, BrandFont.uiBricolage(27, 700))
                .foregroundStyle(Theme.Colors.heading)
                .multilineTextAlignment(.center)
                .padding(.top, 44)

            Text(message)
                .font(BrandFont.nunito(15, 600))
                .designLineHeight(1.45, BrandFont.uiNunito(15, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 9)
                // Growing from one line to two must not shove the buttons.
                .animation(.easeInOut(duration: 0.26), value: message)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .onAppear(perform: settle)
    }

    // MARK: Visual

    @ViewBuilder
    private var visual: some View {
        switch outcome {
        case .saved:
            savedVisual
        case .failed:
            failedVisual
        }
    }

    /// Photo over two offset cards. The three layers float on the same 4.4s
    /// cycle but staggered — the lag is what reads as depth rather than bounce,
    /// so they must never be in sync.
    private var savedVisual: some View {
        ZStack {
            backCard(widthInset: 13, drop: 11, corner: 30, fill: Theme.Colors.surface3, delay: 0.5)
            backCard(widthInset: 6, drop: 5, corner: 28, fill: Theme.Colors.stackMid, delay: 0.25)

            photo
                .shadow(color: Theme.Colors.textPrimary.opacity(0.14), radius: 30, y: 14)
                .overlay(alignment: .bottomTrailing) { tickBadge.offset(x: 14, y: 14) }
                .offset(y: isFloating ? -9 : 0)
                .animation(floatAnimation(delay: 0), value: isFloating)
        }
        .scaleEffect(hasSettled ? 1 : 0.94)
    }

    /// No shake, no red — the photo simply recedes and an amber badge settles in.
    private var failedVisual: some View {
        photo
            .opacity(0.45)
            .shadow(color: Theme.Colors.textPrimary.opacity(0.10), radius: 30, y: 14)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.Colors.amberChip)
                    .frame(width: ImportSheetMetrics.badge, height: ImportSheetMetrics.badge)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.Colors.amber)
                    )
                    .offset(x: 12, y: 12)
                    .scaleEffect(badgeSettled ? 1 : 0.8)
                    .opacity(badgeSettled ? 1 : 0)
            }
    }

    private var photo: some View {
        ImportRecipePhoto(imageData: imageData, imageURLString: imageURLString)
            .frame(width: ImportSheetMetrics.photo, height: ImportSheetMetrics.photo)
            .clipShape(RoundedRectangle(cornerRadius: ImportSheetMetrics.photoCorner, style: .continuous))
    }

    private func backCard(
        widthInset: CGFloat,
        drop: CGFloat,
        corner: CGFloat,
        fill: Color,
        delay: Double
    ) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .frame(
                width: ImportSheetMetrics.photo + widthInset * 2,
                height: ImportSheetMetrics.photo
            )
            .offset(y: drop + (isFloating ? -3 : 0))
            .scaleEffect(isFloating ? 0.994 : 1)
            .opacity(isFloating ? 0.88 : 1)
            .animation(floatAnimation(delay: delay), value: isFloating)
    }

    private var tickBadge: some View {
        Circle()
            .fill(Theme.Colors.accent)
            .frame(width: ImportSheetMetrics.badge, height: ImportSheetMetrics.badge)
            .overlay(
                StrokedCheckmark()
                    .trim(from: 0, to: tickProgress)
                    .stroke(
                        Theme.Colors.creamText,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 24, height: 24)
            )
            .shadow(color: Theme.Colors.textPrimary.opacity(0.2), radius: 22, y: 10)
            .scaleEffect(badgeSettled ? 1 : 0.6)
    }

    private func floatAnimation(delay: Double) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(delay)
    }

    // MARK: Entry choreography

    /// The card stack scales in while the animation crossfades out, then the
    /// badge springs and its tick strokes on. The only energetic moment here.
    private func settle() {
        // Reduce Motion: no scale-in, no spring, no float — just be there.
        guard !reduceMotion else {
            hasSettled = true
            badgeSettled = true
            tickProgress = 1
            return
        }
        withAnimation(.easeOut(duration: 0.26)) { hasSettled = true }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55).delay(0.26)) {
            badgeSettled = true
        }
        guard outcome == .saved else { return }
        withAnimation(.easeOut(duration: 0.18).delay(0.34)) { tickProgress = 1 }
        isFloating = true
    }
}

/// The tick in the saved badge. A path rather than an SF Symbol so it can
/// actually stroke on.
struct StrokedCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.20))
        return path
    }
}

/// The imported recipe's photo. Prefers the bytes the share sheet handed us
/// (Instagram reels expose no scrapable thumbnail), then a scraped URL, then a
/// branded tile so the badge still has something to sit on.
struct ImportRecipePhoto: View {
    let imageData: Data?
    let imageURLString: String?

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let imageURLString, let url = URL(string: imageURLString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Theme.Colors.surface3.overlay(
            Image(systemName: "fork.knife")
                .font(.system(size: 42))
                .foregroundStyle(Theme.Colors.accent.opacity(0.35))
        )
    }
}

// MARK: - Actions

/// Full-width primary pill: "Back to Instagram", "Keep the link anyway".
struct ImportPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.nunito(16, 800))
                .foregroundStyle(Theme.Colors.creamText)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Theme.Colors.accent))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.14), radius: 24, y: 10)
        }
        .buttonStyle(.plain)
    }
}

/// The quieter second action underneath: "Open it in Glutt", "Try again".
struct ImportTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.nunito(15, 800))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, 16)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
