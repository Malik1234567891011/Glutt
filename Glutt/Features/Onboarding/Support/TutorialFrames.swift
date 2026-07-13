import SwiftUI

/// Phase 0 — the social video post with a coached share button.
struct SocialPostFrame: View {
    var body: some View {
        ZStack {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).frame(maxHeight: .infinity, alignment: .top)
            LinearGradient(colors: [.black.opacity(0.82), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 300).frame(maxHeight: .infinity, alignment: .bottom)

            // Creator row (top-left, y≈64)
            HStack(spacing: 9) {
                Circle().fill(LinearGradient(colors: [OnboardingTheme.coralBright, Color(hex: 0xF0A24A)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                Text("thesapor").font(OnboardingFonts.bricolage(15, 700)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                Text("Follow").font(OnboardingFonts.nunito(11, 800)).foregroundStyle(.white)
                    .padding(.vertical, 2).padding(.horizontal, 10)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 18).padding(.top, 64)

            // Action rail (right, bottom 118), share icon coached
            VStack(spacing: 20) {
                railItem(MS.favoriteFill, 34, "44.7K")
                railItem(MS.modeComment, 33, "46")
                VStack(spacing: 4) {
                    ZStack {
                        MS.send.sized(33).foregroundStyle(.white)
                        CoachMark(diameter: 48)
                    }
                    .frame(width: 48, height: 48)
                    Text("14.8K").font(OnboardingFonts.nunito(12, 700)).foregroundStyle(.white)
                }
                railItem(MS.bookmark, 33, "Save")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12).padding(.bottom, 118)

            // Caption (bottom-left)
            VStack(alignment: .leading, spacing: 6) {
                Text("Crispy hot honey chicken bites 🍯🔥")
                    .font(.custom("Georgia-Italic", size: 21))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                Text("with cheesy ramen · 12 min · #weeknight")
                    .font(OnboardingFonts.nunito(13, 600)).foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 16).padding(.trailing, 80).padding(.bottom, 24)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
    }

    private func railItem(_ glyph: MS, _ size: CGFloat, _ count: String) -> some View {
        VStack(spacing: 4) {
            glyph.sized(size).foregroundStyle(.white)
            Text(count).font(OnboardingFonts.nunito(12, 700)).foregroundStyle(.white)
        }
    }
}

/// Phase 1 — the app's own share menu over the dimmed post.
struct AppShareSheetFrame: View {
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            Color.black.opacity(0.58)

            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0x3C3C43).opacity(0.3))
                    .frame(width: 40, height: 5).padding(.top, 11)
                HStack(spacing: 9) {
                    MS.search.sized(19).foregroundStyle(Color(hex: 0x8A8A8E))
                    Text("Search").font(OnboardingFonts.nunito(14, 600))
                        .foregroundStyle(Color(hex: 0x8A8A8E))
                    Spacer()
                }
                .padding(.vertical, 11).padding(.horizontal, 13)
                .background(Color(hex: 0x787880).opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 18).padding(.top, 16)

                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(Color(hex: 0x3C3C43).opacity(0.1))
                            .frame(width: 54, height: 54)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 6)

                Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.12)).frame(height: 1)
                    .padding(.horizontal, 18).padding(.top, 10)

                HStack(alignment: .top, spacing: 6) {
                    shareCircle(icon: MS.addCircle, tint: Color(hex: 0x2A2A2C), bg: .white, label: "Story", labelColor: Color(hex: 0x3A3A3C))
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(.white)
                                .shadow(color: OnboardingTheme.greenDeep.opacity(0.3), radius: 4, y: 2)
                            MS.iosShare.sized(26).foregroundStyle(OnboardingTheme.greenDeep)
                            CoachMark(diameter: 54)
                        }
                        .frame(width: 54, height: 54)
                        Text("Share to…").font(OnboardingFonts.nunito(11, 700))
                            .foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(maxWidth: .infinity)
                    shareCircle(icon: MS.link, tint: Color(hex: 0x2A2A2C), bg: .white, label: "Copy", labelColor: Color(hex: 0x3A3A3C))
                    shareCircle(icon: MS.chatFill, tint: .white, bg: Color(hex: 0x25D366), label: "WhatsApp", labelColor: Color(hex: 0x3A3A3C))
                }
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 22)
            }
            .background(Color(hex: 0xECEBED), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.35), radius: 20, y: -12)
            .offset(y: shown ? 0 : 400)
            .animation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.4), value: shown)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
        .onAppear { shown = true }
    }

    private func shareCircle(icon: MS, tint: Color, bg: Color, label: String, labelColor: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(bg).shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                icon.sized(26).foregroundStyle(tint)
            }
            .frame(width: 54, height: 54)
            Text(label).font(OnboardingFonts.nunito(11, 600)).foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Phase 2 — the system share sheet; Glutt is the coached target.
struct SystemShareSheetFrame: View {
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("tutorialHotHoney").resizable().scaledToFill()
                .frame(width: 390, height: 830).clipped()
            Color.black.opacity(0.58)

            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0x3C3C43).opacity(0.3))
                    .frame(width: 40, height: 5).padding(.top, 11)

                HStack(spacing: 12) { // link preview row
                    Image("tutorialHotHoney").resizable().scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Crispy hot honey chicken bites")
                            .font(OnboardingFonts.nunito(14, 700)).foregroundStyle(Color(hex: 0x1C1C1E))
                            .lineLimit(1)
                        Text("thesapor.com")
                            .font(OnboardingFonts.nunito(12, 600)).foregroundStyle(Color(hex: 0x8A8A8E))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.top, 16)

                HStack(alignment: .top, spacing: 6) { // app targets
                    appTile(label: "AirDrop", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(RadialGradient(colors: [Color(hex: 0x4AA3FF), Color(hex: 0x0A6CF0)],
                                                 center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 40))
                        MS.wifiTethering.sized(27).foregroundStyle(.white)
                    }
                    VStack(spacing: 8) { // coached Glutt
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [Color(hex: 0x3C6B4B), Color(hex: 0x244430)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: OnboardingTheme.greenDeep.opacity(0.45), radius: 6, y: 4)
                            MS.skilletFill.sized(29).foregroundStyle(OnboardingTheme.creamText)
                            CoachMark(diameter: 56, ringRadius: 20)
                        }
                        .frame(width: 56, height: 56)
                        Text("Glutt").font(OnboardingFonts.nunito(11, 700))
                            .foregroundStyle(OnboardingTheme.greenDeep)
                    }
                    .frame(maxWidth: .infinity)
                    appTile(label: "Messages", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Color(hex: 0x5BE36A), Color(hex: 0x12B32A)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        MS.chatBubbleFill.sized(27).foregroundStyle(.white)
                    }
                    appTile(label: "Mail", labelColor: Color(hex: 0x3A3A3C)) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(colors: [Color(hex: 0x4AA3FF), Color(hex: 0x0A6CF0)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        MS.mailFill.sized(26).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 4)

                VStack(spacing: 0) { // actions list
                    listRow("Copy", MS.contentCopy)
                    Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.12)).frame(height: 1)
                        .padding(.leading, 16)
                    listRow("Add to Reading List", MS.chromeReaderMode)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 22)
            }
            .background(Color(hex: 0xECEBED), in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
            .shadow(color: .black.opacity(0.35), radius: 20, y: -12)
            .offset(y: shown ? 0 : 400)
            .animation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.4), value: shown)
        }
        .frame(width: 390, height: 830)
        .background(Color(hex: 0x0D0D0F))
        .onAppear { shown = true }
    }

    private func appTile<Icon: View>(label: String, labelColor: Color, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 8) {
            ZStack { icon() }.frame(width: 56, height: 56)
            Text(label).font(OnboardingFonts.nunito(11, 600)).foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func listRow(_ title: String, _ glyph: MS) -> some View {
        HStack {
            Text(title).font(OnboardingFonts.nunito(15, 600)).foregroundStyle(Color(hex: 0x1C1C1E))
            Spacer()
            glyph.sized(21).foregroundStyle(Color(hex: 0x1C1C1E))
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
    }
}

#Preview("Phase 0 — Social post") {
    MiniPhoneFrame { SocialPostFrame() }
}

#Preview("Phase 1 — App share sheet") {
    MiniPhoneFrame { AppShareSheetFrame() }
}

#Preview("Phase 2 — System share sheet") {
    MiniPhoneFrame { SystemShareSheetFrame() }
}

/// Phase 3 — cream loader: 3 bouncing dots + sweeping bar. Auto-advance is the
/// screen's job (1800ms), not this view's.
struct ImportingFrame: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 11) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(OnboardingTheme.greenDeep)
                        .frame(width: 14, height: 14)
                        .offset(y: reduceMotion ? 0 : (animating ? -13 : 0))
                        .opacity(reduceMotion ? 1 : (animating ? 1 : 0.45))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16), value: animating)
                }
            }
            Text("Pulling out the recipe…")
                .font(OnboardingFonts.bricolage(22, 600))
                .foregroundStyle(OnboardingTheme.textHeading)
            ZStack(alignment: .leading) {
                Capsule().fill(OnboardingTheme.greenDeep.opacity(0.14))
                Capsule().fill(OnboardingTheme.greenDeep)
                    .frame(width: 180 * 0.42)
                    .offset(x: reduceMotion ? 52 : (animating ? 180 * 1.3 : -180 * 0.55))
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false), value: animating)
            }
            .frame(width: 180, height: 6)
            .clipShape(Capsule())
        }
        .frame(width: 390, height: 830)
        .background(OnboardingTheme.cream)
        .onAppear { animating = true }
    }
}

/// Phase 4 — the captured recipe with a popping "Saved" badge.
struct SavedRecipeFrame: View {
    @State private var badgeShown = false

    private static let ingredients = [
        "3 packs Otoki Cheesy Ramen", "1 lb chicken breast", "1 cup buttermilk",
        "Mozzarella + heavy cream", "Hot honey glaze",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 52)
            ZStack(alignment: .topLeading) {
                Image("tutorialHotHoney").resizable().scaledToFill()
                    .frame(width: 390, height: 230).clipped()
                LinearGradient(stops: [
                    .init(color: OnboardingTheme.cream, location: 0.02),
                    .init(color: .clear, location: 0.46),
                ], startPoint: .bottom, endPoint: .top)
                HStack(spacing: 6) {
                    MS.checkCircleFill.sized(16).foregroundStyle(.white)
                    Text("Saved to your recipes")
                        .font(OnboardingFonts.nunito(12.5, 800)).foregroundStyle(.white)
                }
                .padding(.vertical, 7).padding(.horizontal, 13)
                .background(OnboardingTheme.greenDeep.opacity(0.96), in: Capsule())
                .shadow(color: OnboardingTheme.greenDeep.opacity(0.35), radius: 8, y: 6)
                .padding(.top, 14).padding(.leading, 16)
                .scaleEffect(badgeShown ? 1 : 0.7)
                .opacity(badgeShown ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.4), value: badgeShown)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Crispy hot honey chicken bites")
                    .font(OnboardingFonts.bricolage(25, 600)).kerning(-0.4)
                    .foregroundStyle(OnboardingTheme.textHeading)
                HStack(spacing: 16) {
                    meta(MS.schedule, "12 min")
                    meta(MS.fire, "540 cal")
                    meta(MS.restaurant, "Serves 4")
                }
                .padding(.top, 11)
                Text("INGREDIENTS")
                    .font(OnboardingFonts.nunito(11, 800)).kerning(0.7)
                    .foregroundStyle(OnboardingTheme.muted)
                    .padding(.top, 20).padding(.bottom, 11)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.ingredients, id: \.self) { item in
                        HStack(spacing: 10) {
                            MS.checkCircleFill.sized(16)
                                .foregroundStyle(OnboardingTheme.greenDeep.opacity(0.75))
                            Text(item).font(OnboardingFonts.nunito(14.5, 600))
                                .foregroundStyle(OnboardingTheme.textList)
                        }
                    }
                    Text("+ 4 more ingredients")
                        .font(OnboardingFonts.nunito(13.5, 600))
                        .foregroundStyle(OnboardingTheme.muted)
                        .padding(.leading, 26)
                }
            }
            .padding(.horizontal, 24).padding(.top, 34)
            Spacer(minLength: 0)
        }
        .frame(width: 390, height: 830, alignment: .top)
        .background(OnboardingTheme.cream)
        .onAppear { badgeShown = true }
    }

    private func meta(_ glyph: MS, _ text: String) -> some View {
        HStack(spacing: 5) {
            glyph.sized(17).foregroundStyle(OnboardingTheme.muted)
            Text(text).font(OnboardingFonts.nunito(13, 700)).foregroundStyle(OnboardingTheme.muted)
        }
    }
}
