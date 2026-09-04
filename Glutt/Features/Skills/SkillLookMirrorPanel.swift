import SwiftUI

/// The exact pictures the reader was handed, and what it said about each one.
///
/// A cook held a knife with their whole hand on the blade and was told it was
/// perfect, through several rounds of fixes, each aimed at pixels nobody could
/// see at the time. Every explanation was a guess. This ends the guessing.
///
/// The live camera feed used to sit alongside these and has been taken out. It
/// answered a question that only came up once, "is she even pointed at my
/// hand", and in exchange it sat on top of the copy log button, which is the
/// thing anybody actually needs during a test.
///
/// Tap the header to collapse it. **Debug builds only.**
#if DEBUG
struct SkillLookMirrorPanel: View {
    @State private var mirror = SkillLookMirror.shared
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "eye.fill" : "eye.slash.fill")
                    Text(expanded ? "what she sees" : "show what she sees")
                    Spacer()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(mirror.sent.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(.black.opacity(0.65), in: Circle())
                                        .padding(3)
                                }
                        }
                        if mirror.sent.isEmpty {
                            Text("nothing sent yet")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(height: 96)
                        }
                    }
                }

                if !mirror.verdict.isEmpty {
                    Text(mirror.verdict)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                // The line that matters: what she said about each picture. When
                // a ring is sitting on obvious steel and this says `onHandle`,
                // the problem is her reading and not our framing.
                ForEach(mirror.readings, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
