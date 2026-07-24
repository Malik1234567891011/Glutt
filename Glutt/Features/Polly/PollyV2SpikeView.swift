import AVFoundation
import SwiftUI

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

    private var transport: RealtimeWebRTCTransport?
    private var eventTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    /// Set when server VAD reports end-of-speech; cleared when her audio
    /// starts. The delta is the voice-to-voice number that decides whether
    /// OpenAI's edge is close enough from THIS kitchen (vs LiveKit-first-mile).
    private var speechStoppedAt: Date?

    func connect() {
        guard !isBusy else { return }
        isBusy = true
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
                startEventDrain(transport)
                try await transport.connect(token: token.value, model: token.model)

                // Minimal session config: persona + default semantic VAD.
                // Formats/voice are pinned at mint; WebRTC owns the audio path.
                try transport.sendRaw(#"""
                {"type":"session.update","session":{"type":"realtime","instructions":"You are Polly, Glutt's warm, brief live cooking companion. This is a transport test. Keep every reply to one or two short sentences.","audio":{"input":{"turn_detection":{"type":"semantic_vad","eagerness":"auto"}}}}}
                """#)
                try transport.sendRaw(#"""
                {"type":"response.create","response":{"instructions":"Greet the user in one short sentence and ask them to say something back."}}
                """#)
                startMeter()
                finishConnect(ok: true, message: "Connected — listen for the greeting")
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
        append(dormant ? "mic track DISABLED (dormant) — speak to test the hook"
                       : "mic track enabled")
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
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let rms = self.transport?.captureRMS ?? 0
                self.hookRMS = rms
                // Speech at counter distance lands well above this floor; zeros
                // mean the hook died (the failure the vetting doc warns about).
                if self.isDormant, rms > 0.01 {
                    self.hookAliveWhileDormant = true
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

        if name.hasSuffix(".delta") { return } // transcript spam
        append(name)
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
