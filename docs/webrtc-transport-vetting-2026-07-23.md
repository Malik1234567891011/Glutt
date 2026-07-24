# WebRTC transport vetting — OpenAI Realtime + "Polly" wake word (2026-07-23)

Decision input for rebuilding Polly's voice client from raw WebSocket to OpenAI's first-party
WebRTC endpoint, while keeping our GA-verified Codable event codec and on-device wake-word
listening (SFSpeechRecognizer/SpeechAnalyzer) during a dormant call. All facts below were
verified against the primary sources on 2026-07-23 (headers were grepped from the actual
downloaded xcframework binaries).

## Recommendation (TL;DR)

- **Binary:** `livekit/webrtc-xcframework` (SPM product `LiveKitWebRTC`), **pinned to release
  144.7559.11** — NOT via LiveKit's Swift SDK, and NOT `branch: main`.
- **Integration:** hand-rolled thin transport (~250 LOC), pattern-mined from
  m1guelpf/swift-realtime-openai's `WebRTCConnector` but speaking OUR event codec.
- **Wake word:** capture-side hook inside the WebRTC stack — inject
  `LKRTCDefaultAudioProcessingModule(capturePostProcessingDelegate:)` into the peer-connection
  factory; the delegate keeps receiving real mic frames while the call is dormant (track muted).
  Simpler alternative in the same binary: `LKRTCAudioTrack.addRenderer:` → `AVAudioPCMBuffer`.
  Do **not** run a second AVAudioEngine input tap concurrently with the VPIO capture.

## 1. m1guelpf/swift-realtime-openai — verdict: steal patterns, don't depend

- MIT. iOS 17+ / macOS 14+ / visionOS 1+ (Package.swift). 434 stars.
- Single release ever: `1.0.0-beta` (2025-09-10). Last push 2025-10-06 (~9 months stale).
  Open issue #64 literally asks the author to archive the repo; #55/#56 show event-name drift
  vs the GA API; #52 no clean disconnect; #33 TestFlight dSYM failure for WebRTC.framework.
- Depends on `livekit/webrtc-xcframework` at **`branch: "main"`** — a floating, non-reproducible
  dependency (deal-breaker for a shipping app on its own).
- Transport is NOT standalone: `Connector` protocol is hardwired to its own MetaCodable
  `ClientEvent`/`ServerEvent` types (`Sources/Core/Protocols/Connector.swift`), so our codec
  can't be injected without forking.
- No capture-audio exposure: `WebRTCConnector` never touches the audio-processing module or
  renderers; mic is a plain `LKRTCAudioTrack`, mute = `audioTrack.isEnabled.toggle()`.
- Echo history: #24 "Microphone Echo" (speaker feedback on iPhone) was only truly fixed by the
  WebRTC rewrite (AEC in libWebRTC); audio session it sets: `.playAndRecord` + `.videoChat` +
  `.defaultToSpeaker`.
- **Value to us:** `Sources/WebRTC/WebRTCConnector.swift` (~230 LOC) is a complete, correct
  template for the calls-endpoint handshake (offer → POST → expect **HTTP 201** → answer),
  `oai-events` channel wiring, and AVAudioSession setup.
  https://github.com/m1guelpf/swift-realtime-openai

## 2. stasel/WebRTC — solid binary, but NO capture hooks

- Community build of **upstream** Google libWebRTC. 620 stars. License: WebRTC BSD-3 + patent
  grant (repo shows "Other"; the xcframework bundles the WebRTC LICENSE).
- Cadence: tracks Chromium milestones — M150 (2026-07-11), M149, M148, M147, M146… but note a
  ~6-month gap (M141 2025-10 → M146 2026-03). Zip ~44 MB; ios-arm64 framework binary **11 MB**
  (same as LiveKit's); slices: iOS dev/sim, Catalyst, macOS only.
- **No `RTCAudioCustomProcessingDelegate`, no `RTCAudioProcessingModule`, no `RTCAudioRenderer`**
  in the M150 headers (verified by grep). The only escape hatch is upstream `RTCAudioDevice`
  (a full custom audio-device implementation — you re-own all of audio I/O; heavy). Users keep
  asking for buffer access and it isn't there: issues #103 ("can't find RTCAudioBuffer"),
  #119 ("can't find RTCAudioSink"), #127 (raw audio access), #110, #81, #90.
- Manual session control: YES — `RTCAudioSession.useManualAudio` / `isAudioEnabled` /
  `lockForConfiguration` present (same as LiveKit build).
- iOS 26: open #130 "Crash Xcode 26 real device, works in simulator"; #138 audio-resume issue
  on iOS 18.4.1/26.x (old M124 build). Nothing systemic reported against M148–M150.
- **Verdict:** fine for a hook-less transport, wrong choice for our wake-word requirement.
  https://github.com/stasel/WebRTC

## 3. livekit/webrtc-xcframework — hooks ARE in the binary; fully standalone

- SPM: package + product both named **`LiveKitWebRTC`** (single binaryTarget, iOS 13+,
  Catalyst/macOS/tvOS/visionOS slices). Wrapper repo MIT; core WebRTC BSD-3 (LICENSE bundled);
  LiveKit-added headers Apache-2.0. Built from the `webrtc-sdk/webrtc` fork.
- Standalone consumption without the LiveKit SDK is normal — m1guelpf's SDK does exactly that.
  Symbols are `LK`-prefixed (`LKRTCPeerConnection`…); zero open issues on the repo.
- Releases: 144.7559.11 (2026-07-08), .10, .09, .08… — near-monthly patch cadence on M144.
  Zip 66.6 MB (9 slices); ios-arm64 framework binary **11 MB** — identical size to stasel.
- **The audio hooks live at the xcframework/ObjC layer**, NOT only in LiveKit's Swift SDK
  (verified in the downloaded 144.7559.11 headers):
  - `LKRTCAudioCustomProcessingDelegate` — `audioProcessingInitialize(sampleRate:channels:)`,
    `audioProcessingProcess(audioBuffer:)`, `audioProcessingRelease` (RTCAudioCustomProcessingDelegate.h).
  - `LKRTCDefaultAudioProcessingModule.init(config:capturePostProcessingDelegate:renderPreProcessingDelegate:)`
    + runtime-swappable delegate properties + `muted` (RTCDefaultAudioProcessingModule.h).
  - Injection point: `LKRTCPeerConnectionFactory.init(audioDeviceModuleType:bypassVoiceProcessing:encoderFactory:decoderFactory:audioProcessingModule:)`.
  - `LKRTCAudioBuffer` — `channels`, `frames`, `rawBuffer(forChannel:)` float pointers.
  - `LKRTCAudioTrack.addRenderer(_: LKRTCAudioRenderer)` — observe-only; delivers
    **`AVAudioPCMBuffer`** directly (`render(pcmBuffer:)`), on local and remote tracks.
- LiveKit's Swift SDK (`client-sdk-swift`) merely wraps these:
  `AudioManager.shared.capturePostProcessingDelegate` sets
  `RTC.audioProcessingModule.capturePostProcessingDelegate` (AudioManager.swift:193–213). The SDK
  also proves the muted-capture model: `onMutedSpeechActivity` ("detect voice activity even if
  the mic is muted") and `startLocalRecording()` ("buffers flow into … capturePostProcessingDelegate"
  with no Room at all).
  https://github.com/livekit/webrtc-xcframework · https://github.com/livekit/client-sdk-swift

## 4. Hand-rolled thin layer — the OpenAI flow (GA, verified)

From https://developers.openai.com/api/docs/guides/realtime-webrtc (platform.openai.com 301s here):

1. Mint ephemeral key server-side: `POST https://api.openai.com/v1/realtime/client_secrets`.
2. Create `LKRTCPeerConnection`, add mic `LKRTCAudioTrack`, create data channel **`"oai-events"`**.
3. Create SDP offer, `setLocalDescription`, then
   `POST https://api.openai.com/v1/realtime/calls?model=…` with headers
   `Authorization: Bearer <EPHEMERAL_KEY>` and `Content-Type: application/sdp`, body = offer SDP.
4. Response body is the answer SDP (m1guelpf checks **201 Created**); `setRemoteDescription(.answer)`.
5. All events are JSON over the data channel, both directions — `session.update` etc. are sent
   as `dc.send(JSON encode(event))`; server events arrive as data-channel messages (our Codable
   codec plugs straight in).
6. Audio out: model speech arrives as a remote audio track; on iOS libWebRTC's ADM plays it —
   no render code needed. Mic mute: `track.isEnabled = false` (per OpenAI docs `track.enabled`).

**LOC estimate:** ~220–300 Swift LOC for `connect(token) -> AsyncThrowingStream<ServerEvent>`,
`send(event)`, mute, disconnect, audio-session config (m1guelpf's connector is ~230 LOC doing
exactly this), plus ~40–80 LOC for the wake-word buffer bridge. Roughly a day of code; the risk
is in audio-session tuning, not the transport.

## Wake-word coexistence on iOS — the concrete answer

**Can a separate AVAudioEngine inputNode tap run while WebRTC voice-processing capture is
active (same session, .playAndRecord/.videoChat)? Effectively no — don't build on it.**

- libWebRTC's iOS ADM uses the Voice-Processing I/O unit (VPIO). Apple Core Audio engineer on
  mixing I/O units in-app: "You can't have a voiceprocessing audiounit with remoteIO … VPIO
  requires specific AVAudioSession Category/Modes which are not the ones you can use with
  remoteIO" — and dual VPIO is only "tolerated" with broken AGC/volume.
  https://developer.apple.com/forums/thread/110816 (see also thread/751100 — one VPIO cuts off
  the other's input; WWDC19 session 510 for VPIO constraints).
- Field reports match: second-engine taps deliver zeros/silence or die on route changes; Twilio's
  own answer to "tap the mic during a call" is their custom-audio-device example, not a second
  engine (https://github.com/twilio/voice-quickstart-ios/issues/483).
- Real-world wake-word-on-WebRTC project (kmazanec/jarvis, LiveKit + on-device wake word)
  enforces a **"TIME-DISJOINT INVARIANT: the wake-word tap runs ONLY while the room is
  disconnected … a single capture owner on the shared session at any instant"**
  (ios/Jarvis/Audio/AudioSessionManager+WakeWord.swift, ADR-018). That is the correct pattern
  when you have no in-stack hook — but we will have one.

**Proven hook path (what we should do):** pull capture buffers from inside the WebRTC stack.
- LiveKit documents `capturePostProcessingDelegate` as the official way to access/modify local
  mic frames, and ships production processors on it (Krisp noise filter;
  livekit-examples/swift-example-collection `krisp-minimal`; community AFE
  https://github.com/smplrtc/smpl-webrtc-afe-spm implements `LKRTCAudioCustomProcessingDelegate`).
- No public repo was found feeding `SFSpeechAudioBufferRecognitionRequest` specifically from this
  hook (GitHub code search), but the bridge is mechanical: wrap `LKRTCAudioBuffer` channel-0
  floats (10 ms frames at the APM rate) into an `AVAudioPCMBuffer` and call
  `request.append(buffer)` — SFSpeech accepts any PCM format. Jarvis's `WakeWordAudio.swift`
  shows the equivalent resample/quantize framing for a 16 kHz detector.
- Dormancy: mute with `audioTrack.isEnabled = false` (downstream of the APM capture hook, so the
  delegate keeps seeing real audio — the same mechanism behind LiveKit's `onMutedSpeechActivity`
  muted-VAD feature). Avoid `audioProcessingModule.muted` for dormancy until verified — it may
  zero frames before the hook. **Spike task #1: assert hook frames are non-silent while
  `track.isEnabled == false`.** Fallback if that ever breaks: `LKRTCAudioTrack.addRenderer:` on
  the local track (AVAudioPCMBuffer, zero conversion), or Jarvis's time-disjoint tap swap.

## Sources

- https://github.com/m1guelpf/swift-realtime-openai (Package.swift; Sources/WebRTC/WebRTCConnector.swift; issues #24, #33, #52, #55, #64)
- https://github.com/stasel/WebRTC (releases M135–M150; issues #81, #103, #110, #119, #127, #130, #138)
- https://github.com/livekit/webrtc-xcframework (Package.swift @ 144.7559.11; README; headers grepped from LiveKitWebRTC.xcframework 144.7559.11)
- https://github.com/livekit/client-sdk-swift (Sources/LiveKit/Audio/Manager/AudioManager.swift; Protocols/AudioCustomProcessingDelegate.swift)
- https://developers.openai.com/api/docs/guides/realtime-webrtc
- https://developer.apple.com/forums/thread/110816 · https://developer.apple.com/forums/thread/751100 · https://developer.apple.com/videos/play/wwdc2019/510/
- https://github.com/twilio/voice-quickstart-ios/issues/483
- https://github.com/kmazanec/jarvis (ADR-018; ios/Jarvis/Audio/AudioSessionManager+WakeWord.swift; WakeWord/WakeWordAudio.swift)
- https://github.com/livekit-examples/swift-example-collection (krisp-minimal) · https://github.com/smplrtc/smpl-webrtc-afe-spm
