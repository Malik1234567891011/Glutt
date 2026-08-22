# The glasses are back, on Bluetooth. Read this before you archive.

2026-08-20. The Ray-Ban Meta glasses were removed on 2026-08-17 and are now
restored on the branch `bring-meta-glasses-back`, configured for **Bluetooth
Classic**, deliberately, for **local development only**.

This file exists because the transport question was answered four times and
three of those answers were wrong. `glasses-transport-and-memory.md` records the
whole argument and is worth reading for the reasoning, but its retraction chain
is circular in places and it is easy to come away believing the opposite of the
truth. Everything settled is here.

---

## The one-paragraph version

Bluetooth Classic is the better transport by every measure we took, and it is
selected by two Info.plist keys, not by an API. It cannot ship, because those
keys name an MFi protocol and Meta declined to authorise it for this bundle id.
Wi-Fi needs nobody's permission and is slower. This branch runs Bluetooth
because it is faster and nothing here is going to the App Store.

---

## What actually selects the transport

There is no API for this. It is configuration, in the app's own bundle, and
the toolkit reads it at launch:

| Key | Where | Bluetooth | Wi-Fi (softAP) |
| --- | --- | --- | --- |
| `UISupportedExternalAccessoryProtocols: com.meta.ar.wearable` | `project.yml` | present | absent |
| `UIBackgroundModes: external-accessory` | `project.yml` | present | absent |
| `NSLocalNetworkUsageDescription` | `project.yml` | absent | present |
| `NSBonjourServices` | `project.yml` | absent | present |
| `com.apple.developer.networking.HotspotConfiguration` | `Glutt.entitlements` | absent | present |
| `com.apple.developer.networking.wifi-info` | `Glutt.entitlements` | present | present |

The two ExternalAccessory keys are the selector; the rest is making sure the
other transport has nothing to stand on. `wifi-info` stays in both columns: it
is read-only, cannot cause a join, and is how `NetworkProbe` reports which
network the phone actually ended up on.

The source is a **threaded reply** on discussion #226 that a top-level-only
search will never find. `vinidlidoo`, having got Wi-Fi working on 0.8:

> we also had to remove the ExternalAccessory wiring
> (`UISupportedExternalAccessoryProtocols` + the `external-accessory` background
> mode) before the transport would engage

So the keys hold the camera on Bluetooth, and removing them is what lets softAP
take over. They come from the 0.7-era integration guide. The 0.9 docs this app
was built against dropped them, which is why Glutt was on Wi-Fi from its first
line of glasses code and had never once asked for Bluetooth.

## Why it is worth wanting

Measured on real glasses, 2026-08-09 (`aeadecb`):

| | Bluetooth | Wi-Fi softAP |
| --- | --- | --- |
| Time to first frame | **1.8s** | 15 to 20s |
| Phone's own network | kept | dropped to cellular for the whole look |
| Extra prompts | none | "Join Wi-Fi network Meta Glasses", plus Local Network |

A cook asking "does this look done" and waiting twenty seconds is the single
worst thing about the Wi-Fi path, and Bluetooth removes it outright.

## Why it cannot ship

`com.meta.ar.wearable` is an MFi protocol string. Declaring one you are not
authorised for is an App Store rejection, and it is a rejection other people
have already collected: issues #114, #167 and #169 are all apps declaring
exactly this string.

Meta answered **issue #266** saying they will not authorise this bundle id.
That is the whole blocker. It is not technical and no amount of code moves it.
The decision to go back to Wi-Fi is `b41efdf`, 2026-08-16, one day before the
glasses came out entirely.

## Switching back to Wi-Fi

Reverse the table above. Concretely:

1. `project.yml`: delete `UISupportedExternalAccessoryProtocols`, delete
   `external-accessory` from `UIBackgroundModes` (which then has no entries left
   and should be deleted), and restore `NSLocalNetworkUsageDescription` and
   `NSBonjourServices`.
2. `Glutt/Glutt.entitlements`: restore
   `com.apple.developer.networking.HotspotConfiguration`.
3. `xcodegen generate`.
4. Put every "couple of seconds" in the copy and in `PollyPromptBuilder` back to
   the measured fifteen to twenty, and the status pill back to mobile data.

`b41efdf` is that change already made once; diff against it rather than doing it
from memory.

## Two things that are NOT the Bluetooth switch

**`bluetooth-central` and `bluetooth-peripheral` must never come back.** They are
Core Bluetooth (BLE) background modes. Glutt has no Core Bluetooth at all: no
`import CoreBluetooth`, no `CBCentralManager`, no `CBPeripheral`. Bluetooth
Classic through ExternalAccessory is a different transport and needs neither.
They were added with the first BTC spike on the assumption that anything
Bluetooth wanted them, bought nothing, and cost 1.2.2 (16) a rejection under
guideline 2.5.4 on 2026-08-17: *"we are unable to locate any Bluetooth Low
Energy functionality"*, which was exactly correct.

**`NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription`
are also not needed** and are not restored. They are Core Bluetooth permission
strings. The pre-removal tree carried them for the same wrong reason as the
background modes.

## Why the SDK is pinned to 0.8.0

Not for the transport. For `MWDAT.DAMEnabled = false`.

With the Device Access Toolkit App Model on, frames stop dead 5 to 9 seconds in
and never return, with nothing on any error channel. Our cooks froze at 12 to 19
seconds, which is the same failure. 0.9.0 removed the opt-out and shipped no
decoder fix, so moving to 0.9 means decoding `.hvc1` ourselves first, which is
Meta's actual recommendation and is not done.

`GluttTests/Glasses/GlassesDAMConfigTests` asserts what the shipping bundle
resolves to, by calling the same `MWDATCore.Configuration(infoDictionary:)` parse
the SDK performs at launch. Key absent means DAM **on**; `false` means **off**.
An earlier comment claimed 0.8 does not read the key at all, on the strength of
`strings` output. `strings` does not enumerate Swift string literals, so that
observation could not tell "not read" from "not visible to grep".

## Seeing the three "how Chef treats seeing" modes without glasses

Perfectionist / Watchful / Hands off (`ChefWatchfulness`) are drawn in the
pre-cook briefing, and **only when a real pair is connected**:
`PreCookBriefingView` renders the picker `if glassesConnected == true`, which
comes from `GlassesSupport.hasConnectedGlasses()`.

That gate is deliberate. Offering "Chef watches everything" to someone with no
camera is a promise about a cook that cannot happen. It also means that on a
phone with nothing paired the setting is completely invisible, which reads
exactly like the feature having been lost, and `MWDATMockDevice` cannot stand in
because it is linked to the test target only.

So, Debug builds only:

```bash
# simulator
-fakeGlasses
# device (launch arguments containing an "l" are shredded by devicectl)
GLUTT_FAKE_GLASSES=1
```

`DevBuild.fakeGlasses` makes `hasConnectedGlasses()` answer yes. It fakes the
ANSWER, not a camera: `MetaGlassesVisualSource.start` still waits on a real
device selector and will time out, so use it to see and choose a mode, not to
test vision.

## Running it

The spike screen is Debug-only, in Settings under Developer. `-mockGlasses`
pretends a pair is paired and worn so a cook session can be driven with no
hardware, and is a no-op without the argument.

On a real pair, if the camera never delivers a frame:

- Reset the glasses first: in the case, lid shut, a full minute. An OS
  memory-kill leaves them in the stuck-broadcast state of issue #231 and every
  measurement taken after it is suspect.
- `NetworkProbe` lines in the log say which network the phone is on. On
  Bluetooth it should stay on yours.
- On device, use environment variables rather than launch arguments. `devicectl`
  splits a launch argument into single letters, so any flag containing an "l"
  fails.

## The two open product risks, neither fixed in 0.9.0

**#260, HFP audio breaks `capturePhoto`.** With the audio session in HFP mode on
the glasses, `capturePhoto()` reports success and the photo publisher never
fires, while video frames keep flowing. `captureHighDetailFrame()` therefore
degrades to a stream frame whenever Chef is talking through the glasses. It
falls back correctly, so this is a quality ceiling rather than a break, but "read
the thermometer" does not work while she is speaking.

**#256, the camera permanently stops A2DP playback.** Starting a stream pauses
whatever is playing and never resumes it for the rest of the app session, with no
route change and no interruption notification.

Both need verifying against our own audio setup before anyone promises "Chef
talks and watches through the glasses at the same time".
