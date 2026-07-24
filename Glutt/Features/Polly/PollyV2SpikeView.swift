import AVFoundation
import SwiftUI
import UIKit

/// Phase 1 spike harness for the Polly v2 WebRTC transport. Launch-arg gated
/// (`-pollyV2Spike`), device-only in practice (sim has no reliable VPIO), and
/// DELETED before the v2 merge — this is scaffolding, not product.
///
/// Exit criteria it must demonstrate (docs/plan-polly-v2-voice.md, Phase 1):
/// 1. Connect via `/v1/realtime/calls` and hear the greeting on speakerphone.
/// 2. Barge-in: talking over Polly interrupts her (WebRTC AEC, no RMS gate).
/// 3. THE invariant: capture-hook frames stay live (non-zero RMS) while the
///    mic track is disabled — that's what the wake word will feed on.
struct PollyV2SpikeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = PollyV2SpikeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Polly v2 transport spike")
                    .font(.headline)
                Spacer()
                Button(model.justCopied ? "Copied ✓" : "Copy log") {
                    model.copyLog()
                }
                Button("Close") {
                    model.disconnect()
                    dismiss()
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(model.isConnected ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(model.status)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            // Capture-hook liveness. The bar must keep moving when you speak
            // even while "Dormant" is ON — that's the wake-word invariant.
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "capture hook RMS: %.4f", model.hookRMS))
                    .font(.caption.monospaced())
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(model.isDormant ? Color.orange : Color.green)
                        .frame(width: max(4, geo.size.width * CGFloat(min(model.hookRMS * 8, 1))))
                }
                .frame(height: 8)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                if model.isDormant {
                    Text(model.hookAliveWhileDormant
                         ? "✅ hook frames LIVE while track disabled — wake word can hear"
                         : "…speak now to verify the hook still hears while dormant")
                        .font(.caption)
                        .foregroundStyle(model.hookAliveWhileDormant ? .green : .secondary)
                }
            }

            HStack(spacing: 12) {
                Button(model.isConnected ? "Disconnect" : "Connect") {
                    model.isConnected ? model.disconnect() : model.connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)

                Toggle("Dormant (mic track off)", isOn: Binding(
                    get: { model.isDormant },
                    set: { model.setDormant($0) }
                ))
                .disabled(!model.isConnected)
            }
            .font(.subheadline)

            Text("Say something after the greeting; then talk over her mid-sentence to test barge-in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Voice bake-off: tap a chip → fresh session in that voice reads
            // the same 4 Polly lines (greeting / step / repair / wrap-up).
            // Pick by ear at counter distance; the winner becomes POLLY_VOICE.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PollyV2SpikeModel.bakeVoices, id: \.self) { voice in
                        Button(voice) { model.auditionVoice(voice) }
                            .font(.caption.weight(model.auditioningVoice == voice ? .bold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                Capsule().fill(model.auditioningVoice == voice
                                               ? Color.accentColor.opacity(0.3)
                                               : Color.secondary.opacity(0.15)))
                            .disabled(model.isBusy)
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(line.hasPrefix("!") ? .red : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: model.log.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .onDisappear { model.disconnect() }
    }
}

@MainActor
@Observable
final class PollyV2SpikeModel {
    private(set) var status = "Idle — tap Connect"
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var isDormant = false
    private(set) var hookRMS: Float = 0
    private(set) var hookAliveWhileDormant = false
    private(set) var log: [String] = []
    private(set) var justCopied = false
    private(set) var auditioningVoice: String?

    /// GA realtime voices worth auditioning for Polly.
    static let bakeVoices = ["marin", "cedar", "coral", "sage", "shimmer", "ballad", "alloy", "ash", "verse", "echo"]

    private var transport: RealtimeWebRTCTransport?
    private var eventTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    /// Set when server VAD reports end-of-speech; cleared when her audio
    /// starts. The delta is the voice-to-voice number that decides whether
    /// OpenAI's edge is close enough from THIS kitchen (vs LiveKit-first-mile).
    private var speechStoppedAt: Date?
    /// Log timestamps are relative to this (connect time).
    private var connectedAt: Date?
    // Greeting hold, half-duplex, and voice-reopen all live in the
    // transport's governor now (the production engine) — the spike only
    // drives micMode and observes.

    /// Bake-off: fresh session in the chosen voice reading the fixed script.
    /// (Voice is only changeable before the model's first audio, so each
    /// audition is its own session.)
    func auditionVoice(_ voice: String) {
        auditioningVoice = voice
        disconnect()
        connect(voice: voice)
    }

    func connect(voice: String? = nil) {
        guard !isBusy else { return }
        isBusy = true
        if voice == nil { auditioningVoice = nil }
        status = "Requesting microphone…"
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                finishConnect(ok: false, message: "Microphone permission denied")
                return
            }
            do {
                status = "Minting token…"
                let token = try await PollyTokenService.live.mint()
                append("token minted — model=\(token.model) voice=\(token.voice)")

                status = "Connecting WebRTC…"
                let transport = RealtimeWebRTCTransport()
                self.transport = transport
                transport.onRawEvent = { [weak self] raw in
                    Task { @MainActor in self?.appendRaw(raw) }
                }
                transport.onGraphInfo = { [weak self] info in
                    Task { @MainActor in self?.append(info) }
                }
                transport.onBargeInReopen = { [weak self] in
                    Task { @MainActor in self?.append("🔊 voice during her turn — mic reopened for barge-in") }
                }
                startEventDrain(transport)
                try await transport.connect(token: token.value, model: token.model)

                // v1's proven server-side armor: far-field noise reduction +
                // low-eagerness semantic VAD (walked back up during the soak
                // once echo is confirmed dead). Input transcription is on so
                // the log PROVES what the server thinks the "user" said —
                // echo shows up as Polly's own words coming back as input.
                try transport.sendRaw(#"""
                {"type":"session.update","session":{"type":"realtime","instructions":"You are Polly, Glutt's warm, brief live cooking companion. This is a transport test. Keep every reply to one or two short sentences.","audio":{"input":{"turn_detection":{"type":"semantic_vad","eagerness":"low"},"noise_reduction":{"type":"far_field"},"transcription":{"model":"gpt-4o-transcribe","language":"en"}}}}}
                """#)
                transport.setMicMode(.open)
                transport.holdMicForGreeting()
                if let voice {
                    // Override the mint-pinned voice for this audition — legal
                    // only before her first audio, hence the fresh session.
                    try transport.sendRaw(#"{"type":"session.update","session":{"type":"realtime","audio":{"output":{"voice":"\#(voice)"}}}}"#)
                    try transport.sendRaw(#"""
                    {"type":"response.create","response":{"instructions":"Say exactly these four lines, naturally, with a short pause between each. 1: Hey, I'm Polly — let's cook this together. 2: Melt two thirds of a cup of butter in a medium pot, then add the chopped celery and onion. 3: Sorry — say that again for me? 4: That's everything — you cooked that beautifully. See you next time."}}
                    """#)
                    append("🎙 auditioning voice: \(voice)")
                } else {
                    try transport.sendRaw(#"""
                    {"type":"response.create","response":{"instructions":"Greet the user in one short sentence and ask them to say something back."}}
                    """#)
                }
                startMeter()
                connectedAt = Date()
                finishConnect(ok: true, message: "Connected — listen for the greeting")
                append("governor: mic held through greeting (AEC converging)")
                append(transport.audioDiagnostics())

                // The echo verdict, from the horse's mouth: if Apple's platform
                // echo canceller isn't ACTIVE shortly after the engine starts,
                // flip on libWebRTC's software AEC (mobile mode) live.
                try? await Task.sleep(for: .seconds(1.5))
                append(transport.audioDiagnostics())
                if !transport.isPlatformAECActive {
                    transport.enableSoftwareAEC()
                    append("! platform AEC inactive → software AEC3 (mobile) enabled")
                    try? await Task.sleep(for: .milliseconds(500))
                    append(transport.audioDiagnostics())
                }
            } catch {
                finishConnect(ok: false, message: "Connect failed: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        eventTask?.cancel()
        meterTask?.cancel()
        eventTask = nil
        meterTask = nil
        let transport = transport
        self.transport = nil
        Task { await transport?.close() }
        isConnected = false
        isDormant = false
        hookAliveWhileDormant = false
        status = "Disconnected"
    }

    /// The Phase 1 invariant test: track off, hook still hearing.
    func setDormant(_ dormant: Bool) {
        isDormant = dormant
        hookAliveWhileDormant = false
        transport?.setMicEnabled(!dormant)
        append(dormant ? "dormant (track disabled) — SPEAK NOW; watching hook + renderer feeds"
                       : "awake (track enabled) — she can hear again")
        if let transport { append(transport.audioDiagnostics()) }
    }

    private func finishConnect(ok: Bool, message: String) {
        isBusy = false
        isConnected = ok
        status = message
        if !ok { append("! \(message)") }
    }

    private func startEventDrain(_ transport: RealtimeWebRTCTransport) {
        eventTask = Task { [weak self] in
            for await event in transport.events {
                if case let .error(code, message) = event {
                    let line = "! error [\(code ?? "?")] \(message)"
                    await MainActor.run { self?.append(line) }
                }
            }
            await MainActor.run {
                guard let self, self.isConnected else { return }
                self.isConnected = false
                self.status = "Transport stream ended"
                self.append("! transport stream ended")
            }
        }
    }

    private func startMeter() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                let rms = self.transport?.captureRMS ?? 0
                self.hookRMS = rms
                // Speech at counter distance lands well above this floor; zeros
                // mean the hook died (the failure the vetting doc warns about).
                if self.isDormant, rms > 0.01, !self.hookAliveWhileDormant {
                    self.hookAliveWhileDormant = true
                    self.append(String(format: "✅ hook heard you while dormant (RMS %.3f) — wake-word feed proven", rms))
                }
            }
        }
    }

    private func appendRaw(_ raw: String) {
        // Log just the event type; payloads are huge (audio transcripts etc.).
        let type = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        let name = type?["type"] as? String ?? "unparsed"

        // Voice-to-voice turn latency: end of user speech → her audio starts
        // (output_audio_buffer.started is WebRTC-specific per the GA docs).
        if name == "input_audio_buffer.speech_stopped" { speechStoppedAt = Date() }
        if name == "output_audio_buffer.started", let t0 = speechStoppedAt {
            speechStoppedAt = nil
            append(String(format: "⏱ voice-to-voice %.0f ms", Date().timeIntervalSince(t0) * 1000))
        }

        // The echo verdict, in plain text: what the server believes the user
        // said vs what Polly said. Echo = her words arriving as "heard:".
        if name == "conversation.item.input_audio_transcription.completed",
           let transcript = type?["transcript"] as? String {
            append("🎤 heard: \"\(transcript.prefix(90))\"")
        }
        if name == "response.output_audio_transcript.done",
           let transcript = type?["transcript"] as? String {
            append("🗣 polly: \"\(transcript.prefix(90))\"")
        }

        if name.hasSuffix(".delta") { return } // transcript spam
        append(name)
    }

    func copyLog() {
        let device = UIDevice.current
        let header = "Polly v2 spike — \(device.systemName) \(device.systemVersion) — \(Date().formatted())"
        UIPasteboard.general.string = ([header] + log).joined(separator: "\n")
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private func append(_ line: String) {
        if let connectedAt {
            log.append(String(format: "%6.1f  %@", Date().timeIntervalSince(connectedAt), line))
        } else {
            log.append(line)
        }
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
