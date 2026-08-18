# Meta glasses: what was removed, and how to put it back

The Ray-Ban Meta glasses work was taken out of the app on **2026-08-17**. This
file is the inventory, so it can be restored deliberately rather than
archaeologically.

## Why

1.2.2 (16) was rejected under guideline **2.5.4** for declaring
`bluetooth-central` and `bluetooth-peripheral` with no Core Bluetooth
functionality. That specific fix is a separate commit. This one goes further,
because the rest of the glasses surface invites the same argument: an MFi
accessory protocol, an `external-accessory` background mode, two Bluetooth
permission strings and a linked Meta SDK, none of which any shipping build could
reach. The spike screen was already `#if DEBUG`, so no customer ever saw a
glasses feature; what Apple sees is the capability declarations, and those were
real.

## Restoring it

Everything is in git. The last commit that still contains the glasses is the
parent of the removal commit.

```bash
# find the removal commit
git log --oneline --all --grep='remove the Meta glasses'
# put it all back, code and config together
git revert <removal-sha>
xcodegen generate
```

A revert is the intended path, not a courtesy. The removal was made as one
commit for exactly this reason, and nothing else was folded into it.

If the glasses come back for real rather than for a spike, the thing to change
is not this revert but the packaging: the SDK and its Info.plist keys should be
conditional on the build, so a Release archive can never carry them again. That
was the plan before this removal and it remains the right one.

## Deleted outright

| File | What it was |
| --- | --- |
| `Glutt/Features/Glasses/GlassesSpikeView.swift` | the diagnostics screen, reached from Settings in Debug |
| `Glutt/Services/Glasses/GlassesSupport.swift` | Device Access Toolkit bring-up, `isAvailable`, the Meta AI registration callback |
| `Glutt/Services/Glasses/GlassesRunLog.swift` | on-device run log and frame dumps |
| `Glutt/Services/Glasses/GlassesMockRig.swift` | `-mockGlasses`, a fake paired pair |
| `Glutt/Services/Glasses/NetworkProbe.swift` | which network the phone was on, for the Wi-Fi transport |
| `Glutt/Services/Polly/MetaGlassesVisualSource.swift` | the glasses camera as a `PollyVisualSource` |
| `Glutt/Services/Polly/VisualFrameGate.swift` | blur / brightness / duplicate frame measurement |
| `Glutt/Services/Polly/VisualFrameBuffer.swift` | the recent-frames ring the gate chose from |
| `Glutt/Services/Polly/FrameAdmission.swift` | frame admission policy |
| `Glutt/Services/Polly/FrameCounter.swift` | frame throughput counter |
| `Glutt/Services/Polly/MemoryProbe.swift` | footprint sampling during a stream |
| `GluttTests/Glasses/GlassesDAMConfigTests.swift` | 3 tests, asserted `DAMEnabled` against the real bundle |
| `GluttTests/Glasses/GlassesMemoryMatrixTests.swift` | 6 tests, the mock-device memory matrix (always skipped) |
| `GluttTests/VisualFrameGateTests.swift` | 17 tests across `VisualFrameGateTests` (9) and `VisualFrameBufferTests` (8) |

26 tests went with them. The suite is **605 passed, 0 failed, 0 skipped** after
the removal; the 6 skips that used to show up were the memory matrix.

`VisualFrameGate` and `VisualFrameBuffer` are the ones worth a second look if
the phone camera ever wants frame-quality checks. They were deleted because only
the glasses fed them, not because the idea was wrong.

## Changed, not deleted

| File | Change |
| --- | --- |
| `Glutt/Services/Polly/PollyVisualSourceCoordinator.swift` | rewritten as a phone-only forwarder. It owned two sources and chose between them; `glasses`, `glassesPossible`, `lastGlassesDropReason`, `startGlassesIfAvailable()`, `switchToPhone()` and the drop-detection wrapper all went |
| `Glutt/Services/Polly/PollyVisualSource.swift` | `PollyVisualSourceKind.metaGlasses` removed, leaving `.phoneCamera` |
| `Glutt/Services/Polly/VisualFrameRejection.swift` | **new file.** The enum was defined inside the deleted `VisualFrameGate.swift`, but the phone path raises it too, so it was extracted rather than lost |
| `Glutt/Features/Polly/PollySessionController.swift` | dropped the startup `startGlassesIfAvailable()`, the `GlassesRunLog` frame dump, the glasses drop suggestion, and `rebuildInstructions` / `promptAssumesContinuousSight` / `refreshSeeingRulesIfNeeded()`, which existed only to re-send the prompt when glasses arrived or dropped mid-cook |
| `Glutt/Features/Polly/PollyAdaptiveCanvasView.swift` | dropped `usingGlasses`, `isConnectingGlasses`, the glasses status pill, and the glasses branches in the camera button; also the Debug audio toggle labelled "Audio: glasses" |
| `Glutt/Features/Polly/PreCookBriefingView.swift` | dropped `glassesConnected` and the "Chef's bar" watchfulness picker, which only appeared when glasses were connected |
| `Glutt/App/GluttApp.swift` | dropped `GlassesSupport.shared.configure()`, the `MWDATMockDevice` mock rig, and the `glutt-wearables://` callback in `onOpenURL` |
| `Glutt/App/RootView.swift` | dropped `-glassesSpike` and its cover |
| `Glutt/Features/Settings/SettingsView.swift` | dropped the Debug "Developer / Glasses spike" section and its cover |

## Removed from `project.yml`

- the `MetaWearablesDAT` package (pinned `0.8.0`) and both products on the app
  target, `MWDATCore` and `MWDATCamera`
- `MWDATMockDevice` on the `GluttTests` target
- Info.plist: the whole `MWDAT` dict (`AppLinkURLScheme`, `MetaAppID: "0"`,
  `DAMEnabled: false`), `UISupportedExternalAccessoryProtocols`
  (`com.meta.ar.wearable`), `NSBluetoothAlwaysUsageDescription`,
  `NSBluetoothPeripheralUsageDescription`, `LSApplicationQueriesSchemes`
  (`fb-viewapp`, which is how the SDK found Meta AI), the `glutt-wearables` URL
  type, and `external-accessory` from `UIBackgroundModes`

`bluetooth-central` and `bluetooth-peripheral` are **not** on that list: they
went in the separate 2.5.4 fix, and they must never come back regardless of the
glasses, because they are Core Bluetooth modes and this app has no Core
Bluetooth even with the glasses in.

## Deliberately kept

Because they are used by something other than the glasses, or cost nothing and
carry meaning:

- **`ChefWatchfulness`** drives Polly's interruption and seeing rules for the
  phone camera too, and has its own tests. Only its picker went.
- **`PollyAudioLab.micOnGlasses`** despite the name decides whether the audio
  session allows Bluetooth at all, which is what lets a cook wear AirPods.
  Removing it would have broken Bluetooth audio for everyone. Only the Debug
  toggle went. **Worth renaming.**
- **`VisualFramePipeline`** is used by `PollyCameraController` and
  `PollySessionController`.
- **`PollyPromptBuilder.seesContinuously`** stays with its prompt branch and
  tests. It is a pure parameter that already defaulted to false, and it is now
  always false: nothing sees continuously without a wearable. Kept rather than
  cut because editing the prompt builder is the riskiest change in the app and
  the branch costs nothing dormant.
- **`VisualFrameRejection.warmingUp` and `.feedStopped`** describe glasses
  behaviour and are currently unreachable. Kept as documentation of what the
  cases meant.

## Behaviour that changed

- Chef never sees continuously. `seesContinuously` is hard-false, so she always
  gets the phone-camera seeing rules: the camera is off until the cook asks.
- The cook canvas has no glasses pill and the camera button no longer shows an
  eyeglasses symbol.
- The pre-cook briefing no longer offers the watchfulness picker. The stored
  value still applies to the prompt via `ChefWatchfulness.selected`, so an
  existing choice is honoured, it just cannot be changed from that screen.
