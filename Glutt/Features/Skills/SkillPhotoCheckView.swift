import PhotosUI
import SwiftData
import SwiftUI

/// The glasses-free way to finish a lesson: try it, then show Chef.
///
/// Shaped as one screen rather than a wizard on purpose. The whole thing is
/// "here is what I am looking for, here are your slots, send it when you are
/// ready", and a cook doing this has a knife in one hand. Every extra tap is a
/// tap taken with the wrong hand.
///
/// The self-check list above the slots is doing real work. In the live path
/// Chef fills those parts in as she sees them; here nobody sees anything until
/// the photos are sent, so the list becomes the thing the cook checks against
/// their own hand before shooting. That turns a submission into a rehearsal,
/// which is most of why this mode teaches at all rather than just grading.
struct SkillPhotoCheckView: View {
    let skill: Skill
    let check: SkillVisualCheck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Every scored trial, so a new score can say whether it beat the old one.
    /// Read before the new result is written, which is what makes the
    /// comparison honest.
    @Query private var trials: [TrialResult]

    /// The best this cook had at this trial BEFORE today's attempt.
    private var personalBest: Int? {
        trials.filter { $0.skillID == skill.id }.map(\.score).max()
    }

    @State private var model: SkillPhotoCheckModel
    @State private var picking: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var choosingSource = false

    init(skill: Skill, check: SkillVisualCheck) {
        self.skill = skill
        self.check = check
        _model = State(initialValue: SkillPhotoCheckModel(skill: skill, check: check))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch model.phase {
                    case .collecting: collecting
                    case .assessing: assessing
                    case .answered: verdict
                    case .failed(let message): failure(message)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Theme.Colors.background)
            .navigationTitle(skill.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        // Camera and library both, because "I cooked it an hour ago" is a real
        // way to do this lesson and refusing the photo somebody already has
        // would be pointless. A wrong picture is not a risk worth designing
        // against: the assessor says it cannot see, which is the same thing it
        // says about a bad live frame.
        .confirmationDialog("Add a photo", isPresented: $choosingSource) {
            if CameraPicker.isAvailable {
                Button("Take a photo") { showCamera = true }
            }
            Button("Choose from library") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $picking, matching: .images)
        .onChange(of: picking) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.add(data)
                }
                picking = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { jpeg in model.add(jpeg) }
                .ignoresSafeArea()
        }
    }

    // MARK: Collecting

    @ViewBuilder private var collecting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show Chef")
                .font(BrandFont.bricolage(25, 700))
                .foregroundStyle(Theme.Colors.heading)
            Text(model.framing)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !check.parts.isEmpty { selfCheck }

        slots

        Button {
            Task { await model.send() }
        } label: {
            Text(sendButtonTitle)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!model.hasEnough)
    }

    /// Check it against your own hand before you photograph it.
    private var selfCheck: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Check yourself first")
                .font(.headline)
                .foregroundStyle(Theme.Colors.heading)
            ForEach(check.parts) { part in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accent.opacity(0.5))
                    Text(part.label)
                        .font(BrandFont.nunito(15, 600))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            Theme.Colors.surface2,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    /// Imperative while it is still a job to do, plain once it is done.
    private var sendButtonTitle: String {
        let remaining = model.needed - model.photos.count
        if remaining <= 0 { return "Send to Chef" }
        if model.photos.isEmpty { return "Add \(SkillCount.photos(model.needed))" }
        return "\(SkillCount.photosSentence(remaining)) to go"
    }

    private var slots: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(SkillCount.photosSentence(model.needed))
                .font(.headline)
                .foregroundStyle(Theme.Colors.heading)
            HStack(spacing: 10) {
                ForEach(0..<model.needed, id: \.self) { index in
                    slot(at: index)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func slot(at index: Int) -> some View {
        let filled = model.photos.indices.contains(index)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Colors.surface2)
            if filled, let image = UIImage(data: model.photos[index]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(width: 96, height: 96)
        .overlay(alignment: .topTrailing) {
            if filled {
                Button {
                    model.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Color.black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { if !filled { choosingSource = true } }
        .accessibilityLabel(filled ? "Photo \(index + 1), tap the cross to remove"
                                   : "Add photo \(index + 1)")
    }

    // MARK: Assessing

    private var assessing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Having a look")
                .font(BrandFont.bricolage(25, 700))
                .foregroundStyle(Theme.Colors.heading)
            ProgressView()
                .progressViewStyle(.circular)
            Text("She is reading them now.")
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Verdict

    @ViewBuilder private var verdict: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A trial gets its number, big, before anything else.
            //
            // The one place in the whole feature that is allowed to celebrate.
            // Nothing during the attempt shows a live score, because a HUD
            // ticking over while somebody is trying to cook reads as a
            // gamification demo rather than as cooking. Afterwards is
            // different: they earned it and it should feel like it.
            //
            // Still cream, still the display face, still the region's colour.
            // Turning black and neon because "game" would throw away the
            // visual language the rest of the map is built from.
            if let score = model.trialScore {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(score)")
                        .font(BrandFont.bricolage(64, 700))
                        .foregroundStyle(Theme.Colors.heading)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let best = personalBest, score > best {
                        Text("Personal best")
                            .font(BrandFont.nunito(13, 800))
                            .tracking(0.8)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    Text(skill.title)
                        .font(BrandFont.nunito(13.5, 700))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.bottom, 4)
            }
            Text(model.verdictHeadline)
                .font(BrandFont.bricolage(24, 700))
                .foregroundStyle(model.didPass ? Theme.Colors.accent : Theme.Colors.heading)
                .fixedSize(horizontal: false, vertical: true)
            if !model.verdictDetail.isEmpty {
                Text(model.verdictDetail)
                    .font(BrandFont.nunito(15, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // What could not be judged, said plainly.
            //
            // Admitting this reads as more trustworthy than quietly marking
            // somebody down for a thing nobody could see, and it stops a thin
            // result masquerading as a full one.
            if let unscored = model.unscoredParts, !unscored.isEmpty {
                Text("Not scored: \(unscored.joined(separator: ", "))")
                    .font(BrandFont.nunito(12.5, 600))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        VStack(spacing: 10) {
            Button(model.didPass ? "Done" : "Try it again") {
                if model.didPass {
                    dismiss()
                } else {
                    model.reset()
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            if !model.didPass {
                Button("Close") { dismiss() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .buttonStyle(.plain)
            }
        }
        // Written the moment she answers rather than when the sheet closes, so
        // an attempt survives somebody swiping this away in frustration. The
        // failed ones are the most useful rows in the history.
        .onAppear { model.record(in: context) }
    }

    @ViewBuilder private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("That did not go through")
                .font(BrandFont.bricolage(24, 700))
                .foregroundStyle(Theme.Colors.heading)
            Text(message)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        Button("Send them again") {
            Task { await model.send() }
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}
