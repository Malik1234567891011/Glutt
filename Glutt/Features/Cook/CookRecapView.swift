import SwiftData
import SwiftUI
import UIKit

/// End-of-Polly cook recap: plate photo → soft scores → Polly Saves → share.
/// Framed as a cooking *run*, not an AI taste judgment.
struct CookRecapView: View {
    @Environment(\.modelContext) private var context

    let recipe: Recipe
    let scale: Double
    let durationSeconds: Int
    let stepsCompleted: Int
    let stepsTotal: Int
    let endedEarly: Bool
    let pollySaves: [String]
    let substitutions: [String]
    let summary: String?
    let initialPlateJPEG: Data?
    let previousBestOverall: Double?
    let cookName: String?
    let onComplete: () -> Void

    @State private var plateJPEG: Data?
    @State private var showCamera = false
    @State private var visualSelfScore: Double = 8.0
    @State private var didSetVisual = false
    @State private var improvement: String = ""
    @State private var rating = 0
    @State private var note = ""
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @State private var recap: CookRecap?

    init(
        recipe: Recipe,
        scale: Double,
        durationSeconds: Int,
        stepsCompleted: Int,
        stepsTotal: Int,
        endedEarly: Bool,
        pollySaves: [String],
        substitutions: [String],
        summary: String?,
        initialPlateJPEG: Data?,
        previousBestOverall: Double? = nil,
        cookName: String? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.recipe = recipe
        self.scale = scale
        self.durationSeconds = durationSeconds
        self.stepsCompleted = stepsCompleted
        self.stepsTotal = stepsTotal
        self.endedEarly = endedEarly
        self.pollySaves = pollySaves
        self.substitutions = substitutions
        self.summary = summary
        self.initialPlateJPEG = initialPlateJPEG
        self.previousBestOverall = previousBestOverall
        self.cookName = cookName
        self.onComplete = onComplete
        _plateJPEG = State(initialValue: initialPlateJPEG)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    photoSection
                    if let recap {
                        scoreSection(recap)
                        savesSection(recap)
                        upgradeSection
                        sharePreview(recap)
                    }
                    classicFeedback
                    actions
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Cook Recap")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { rebuildRecap() }
            .onChange(of: visualSelfScore) { _, _ in
                didSetVisual = true
                rebuildRecap()
            }
            .onChange(of: improvement) { _, _ in
                guard var r = recap else { return }
                r.improvement = improvement.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                recap = r
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    plateJPEG = data
                    Haptics.notify(.success)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showShare) {
                if let shareImage {
                    CookRecapActivitySheet(items: shareItems(image: shareImage))
                }
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your plate")
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .tracking(1.2)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.Colors.peachPanel)
                    .frame(height: 220)

                if let plateJPEG, let ui = UIImage(data: plateJPEG) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        MS.skillet.sized(40)
                            .foregroundStyle(Theme.Colors.accent.opacity(0.45))
                        Text("Snap the finished dish to complete your run")
                            .font(BrandFont.nunito(14, 700))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }

            HStack(spacing: 10) {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label(plateJPEG == nil ? "Take photo" : "Retake", systemImage: "camera.fill")
                            .font(BrandFont.nunito(14, 800))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.gluttPrimary)
                }
                PhotosPickerButton(plateJPEG: $plateJPEG)
            }
        }
    }

    private func scoreSection(_ recap: CookRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recap.runTitle)
                .font(BrandFont.bricolage(24, 600))
                .foregroundStyle(Theme.Colors.heading)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", recap.overallScore))
                    .font(BrandFont.bricolage(44, 600))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overall vibe")
                        .font(BrandFont.nunito(13, 800))
                        .foregroundStyle(Theme.Colors.heading)
                    Text(recap.timeLabel + " cook")
                        .font(BrandFont.nunito(12, 700))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                if let badge = recap.badge {
                    Text(badge)
                        .font(BrandFont.nunito(11, 800))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Colors.greenTint)
                        .clipShape(Capsule())
                }
            }

            Text(recap.headline)
                .font(BrandFont.nunito(14, 600))
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("How’s the plate looking?")
                    .font(BrandFont.nunito(13, 700))
                    .foregroundStyle(Theme.Colors.heading)
                HStack {
                    Text("Rough")
                        .font(BrandFont.nunito(11, 700))
                        .foregroundStyle(Theme.Colors.muted)
                    Slider(value: $visualSelfScore, in: 4...10, step: 0.1)
                        .tint(Theme.Colors.accent)
                    Text("Glossy")
                        .font(BrandFont.nunito(11, 700))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Text("Your read: \(String(format: "%.1f", visualSelfScore)) — AI can’t taste, so this is your call.")
                    .font(BrandFont.nunito(12, 600))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .padding(14)
            .cardStyle()

            VStack(alignment: .leading, spacing: 8) {
                if let note = recap.timingNote {
                    Text(note)
                        .font(BrandFont.nunito(13, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let note = recap.techniqueNote {
                    Text(note)
                        .font(BrandFont.nunito(13, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private func savesSection(_ recap: CookRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chef Saves")
                    .font(BrandFont.nunito(12, 800))
                    .foregroundStyle(Theme.Colors.muted)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Spacer()
                Text("\(recap.saves.count)")
                    .font(BrandFont.nunito(18, 800))
                    .foregroundStyle(Theme.Colors.accent)
            }

            if recap.saves.isEmpty {
                Text("Clean run — Chef didn’t need to pull an emergency save. Nice.")
                    .font(BrandFont.nunito(14, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recap.saves.enumerated()), id: \.offset) { index, save in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(BrandFont.nunito(12, 800))
                                .foregroundStyle(Theme.Colors.creamText)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Theme.Colors.accent))
                            Text(save.moment)
                                .font(BrandFont.nunito(14, 600))
                                .foregroundStyle(Theme.Colors.heading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < recap.saves.count - 1 {
                            Divider().overlay(Theme.Colors.border)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardStyle()
            }
        }
    }

    private var upgradeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next upgrade")
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .tracking(1.2)
            TextField("One thing for next time…", text: $improvement, axis: .vertical)
                .font(BrandFont.nunito(15, 600))
                .lineLimit(2...4)
                .cardStyle()
        }
    }

    private func sharePreview(_ recap: CookRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share card")
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .tracking(1.2)

            CookRecapCardView(
                recap: patchedRecap(recap),
                plateImage: plateJPEG.flatMap(UIImage.init(data:))
            )
            .allowsHitTesting(false)

            Button {
                Haptics.impact(.medium)
                renderAndShare(recap)
            } label: {
                Label("Challenge a friend", systemImage: "square.and.arrow.up")
                    .font(BrandFont.nunito(15, 800))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.gluttPrimary)
        }
    }

    private var classicFeedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick stars (optional)")
                .font(BrandFont.nunito(12, 800))
                .foregroundStyle(Theme.Colors.muted)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Haptics.impact(.light)
                        rating = rating == star ? 0 : star
                    } label: {
                        if star <= rating {
                            Ph.star.fill
                                .resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Theme.Colors.warning)
                        } else {
                            Ph.star.regular
                                .resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Theme.Colors.warning)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Private note — add more lemon, too salty…", text: $note, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(2...4)
                .cardStyle()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Save recap & finish") {
                Haptics.notify(.success)
                save()
            }
            .buttonStyle(.gluttPrimary)

            Button("Skip — just close") {
                onComplete()
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Logic

    private func rebuildRecap() {
        let built = CookRecapBuilder.build(.init(
            dishTitle: recipe.title,
            cookName: cookName,
            durationSeconds: durationSeconds,
            expectedMinutes: recipe.estimatedMinutes > 0 ? recipe.estimatedMinutes : nil,
            stepsCompleted: stepsCompleted,
            stepsTotal: stepsTotal,
            endedEarly: endedEarly,
            pollySaves: pollySaves,
            substitutions: substitutions,
            summary: summary,
            visualSelfScore: didSetVisual ? visualSelfScore : nil,
            previousBestOverall: previousBestOverall
        ))
        if improvement.isEmpty, let tip = built.improvement {
            improvement = tip
        }
        var next = built
        next.improvement = improvement.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        recap = next
    }

    private func patchedRecap(_ recap: CookRecap) -> CookRecap {
        var copy = recap
        copy.improvement = improvement.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return copy
    }

    private func renderAndShare(_ recap: CookRecap) {
        let image = CookRecapShareService.renderCard(
            recap: patchedRecap(recap),
            plateImage: plateJPEG.flatMap(UIImage.init(data:))
        )
        shareImage = image
        showShare = image != nil
    }

    private func shareItems(image: UIImage) -> [Any] {
        let caption: String
        if let badge = recap?.badge {
            caption = "I scored \(String(format: "%.1f", recap?.overallScore ?? 0)) on \(recipe.title). Badge: \(badge). Beat my run on Glutt."
        } else {
            caption = "I scored \(String(format: "%.1f", recap?.overallScore ?? 0)) on \(recipe.title). Beat my run on Glutt."
        }
        return [image, caption]
    }

    private func save() {
        let servingsMade = max(1, Int((Double(recipe.servings) * scale).rounded()))
        let session = CookSession(servingsMade: servingsMade, recipe: recipe)
        session.rating = rating > 0 ? rating : nil
        session.notes = note.isEmpty ? nil : note
        session.durationSeconds = durationSeconds
        session.plateImageData = plateJPEG
        if let recap = recap {
            let final = patchedRecap(recap)
            session.overallScore = final.overallScore
            session.visualScore = final.visualScore
            session.timingScore = final.timingScore
            session.techniqueScore = final.techniqueScore
            session.pollySaveCount = final.saves.count
            session.improvementNote = final.improvement
            session.badge = final.badge
        }
        context.insert(session)

        if recipe.rating == nil, rating > 0 {
            recipe.rating = rating
        }
        try? context.save()
        onComplete()
    }
}

// MARK: - Photos picker (library fallback)

import PhotosUI

private struct PhotosPickerButton: View {
    @Binding var plateJPEG: Data?
    @State private var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            Label("Library", systemImage: "photo.on.rectangle")
                .font(BrandFont.nunito(14, 800))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Theme.Colors.accent)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.Colors.accent.opacity(0.35), lineWidth: 1.5)
                )
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { plateJPEG = data }
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
