import SwiftData
import SwiftUI

/// The Skills tab: one long scrolling cooking map.
///
/// Deliberately not a dashboard and not a grid of categories. Everything above
/// the map is kept to a single line of progress, because the map is the
/// feature and a header full of statistics would push it below the fold.
struct SkillsView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query private var progressRows: [SkillProgress]
    @State private var modes = SkillLearningModeStore()

    private var reader: SkillsProgressReader { SkillsProgressReader(progress: progressRows) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if !reader.hasStarted {
                        startHere
                    }
                    SkillMapView(reader: reader) { open($0) }
                        .padding(.top, 6)
                }
                .padding(.bottom, GluttTabBar.reservedHeight + 24)
            }
            .background(Theme.Colors.background)
            .navigationBarHidden(true)
        }
    }

    /// Opening a lesson goes through the router, so the SwiftData writes the
    /// lesson makes cannot dismiss it. See `Router.skillLesson`.
    private func open(_ skill: Skill) { router.skillLesson = skill }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Become a better cook")
                        .font(BrandFont.nunito(12, 800)).tracking(1.6).textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Skills")
                        .font(BrandFont.bricolage(31, 700))
                        .foregroundStyle(Theme.Colors.heading)
                }
                Spacer()
                if reader.streak > 0 { streakChip }
            }
            progressLine
            modePicker
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // Photos until a pair of glasses has actually connected on this phone,
        // then watching. The obvious signal, `GlassesSupport.isAvailable`, is
        // the wrong one: it means the toolkit configured, which is true for
        // everybody, and it put the whole world into a mode that needs hardware
        // they do not own. Either way this only ever sets the opening guess and
        // never overrides a cook who has picked for themselves.
        .onAppear {
            modes.suggest(glassesAvailable: SkillLearningModeStore.glassesHaveConnected)
        }
    }

    /// How lessons in this tab are going to be checked.
    ///
    /// At the top of the tab rather than buried in settings, because it changes
    /// what every lesson below it actually is: with glasses Chef watches your
    /// hands while you work, without them she teaches and you send her photos.
    /// Somebody who cannot tell which one they are about to get will be
    /// surprised by whichever one they were not expecting.
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("How Chef checks you", selection: Binding(
                get: { modes.mode },
                set: { modes.choose($0) }
            )) {
                ForEach(SkillLearningMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.glyph).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(modes.mode.explanation)
                .font(BrandFont.nunito(12.5, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var streakChip: some View {
        HStack(spacing: 6) {
            MS.fireFill.sized(16).foregroundStyle(Theme.Colors.coralBright)
            Text("^[\(reader.streak) day](inflect: true)")
                .font(BrandFont.nunito(13, 800)).foregroundStyle(Theme.Colors.amber)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(Capsule().fill(Theme.Colors.amberChip))
        .padding(.top, 6)
    }

    /// Level, skills learned and the bar toward the next level, as one quiet
    /// line rather than a card.
    ///
    /// This used to be a white rounded rectangle with the bear inside it, which
    /// pushed the map below the fold and turned the mascot into a profile
    /// photo. XP, level and skills learned are supporting information; the map
    /// is the product, so they get one line and the bear went to the path.
    private var progressLine: some View {
        let bar = reader.levelProgress
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Level \(bar.level)")
                    .font(BrandFont.nunito(14.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text("·")
                    .foregroundStyle(Theme.Colors.muted)
                Text(reader.learnedCount == 1 ? "1 skill" : "\(reader.learnedCount) skills")
                    .font(BrandFont.nunito(14, 700))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text("\(bar.needed - bar.into) XP to \(bar.level + 1)")
                    .font(BrandFont.nunito(11.5, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface2)
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: max(5, proxy.size.width * fraction(bar)))
                }
            }
            .frame(height: 7)
        }
    }

    private func fraction(_ bar: (level: Int, into: Int, needed: Int)) -> CGFloat {
        guard bar.needed > 0 else { return 0 }
        return min(1, CGFloat(bar.into) / CGFloat(bar.needed))
    }

    /// First run. A map at 0% with nothing pointed at is a dead map, so a cook
    /// who has learned nothing gets one obvious place to begin.
    @ViewBuilder
    private var startHere: some View {
        if let first = reader.recommended {
            Button {
                Haptics.impact(.light)
                open(first)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                Image("bearSpoon")
                    .resizable().scaledToFit().frame(height: 78)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start your cooking journey")
                        .font(BrandFont.bricolage(19, 700))
                        .foregroundStyle(Theme.Colors.heading)
                    Text("Begin with a few fundamentals. You can explore anything you like along the way.")
                        .font(BrandFont.nunito(13.5, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(first.title)
                            .font(BrandFont.nunito(14.5, 800))
                            .foregroundStyle(Theme.Colors.creamText)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Colors.creamText)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.Colors.accent))
                    .padding(.top, 2)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.Colors.greenTint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }
}
