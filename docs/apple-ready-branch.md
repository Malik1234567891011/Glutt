# The `apple-ready` branch

Two branches, one app.

| Branch | What it is |
|---|---|
| `skills-knife-coaching` | Everything. Ray-Ban Meta glasses, live coaching, the lot. **Nothing has been deleted from it.** |
| `apple-ready` | The same app with every trace of Meta glasses removed. This is the one that goes to App Store review. |

`apple-ready` branches off `skills-knife-coaching` and is only ever behind it by
the removals. Nothing is developed here that is not developed there first.

## Why

Version 1.2.2 (16) was rejected under **guideline 2.5.4** on 2026-08-17: "we are
unable to locate any Bluetooth Low Energy functionality". The app was declaring
a Bluetooth background mode for a transport it reached over ExternalAccessory,
for hardware a reviewer could not obtain. The whole surface has to go, not just
the key that was named.

## What was removed

### The things Apple actually parses

These are the ones that matter. All were generated from `project.yml`.

| Removed | Why it would fail |
|---|---|
| `UISupportedExternalAccessoryProtocols: com.meta.ar.wearable` | An MFi accessory declaration for third-party hardware |
| `UIBackgroundModes: external-accessory` | The literal cause of the 2.5.4 rejection |
| `MWDAT` dict (`MetaAppID`, `AppLinkURLScheme`, `DAMEnabled`) | Third-party SDK configuration |
| `LSApplicationQueriesSchemes: fb-viewapp` | Probing for the Meta View companion app |
| URL scheme `glutt-wearables` | The Meta AI registration callback |
| Entitlement `com.apple.developer.networking.wifi-info` | Existed only to report which network the glasses were on |
| SPM package `MetaWearablesDAT` (3 products) | The toolkit itself |
| Scheme `Glutt Glasses Matrix` | A hardware measurement harness |

### Functional code

The one that would have caught us out again: **`PollyAudioSession` used to match
Bluetooth port names against `["ray-ban", "rayban", "meta", "oakley"]`** and call
`setPreferredInput` on the winner. That is functional Bluetooth targeting of
Meta hardware, sitting in the audio layer well away from anything named
"glasses". It is gone; the audio session now knows about no particular device
and leaves the system default alone.

Also removed: `PollyAudioLab.micOnGlasses` and the cook-session menu button that
toggled it, the watchfulness picker on the pre-cook briefing, the glasses status
pills on the cook canvas, the glasses spike screen and its Settings entry, and
the `-fakeGlasses` / `-glassesSpike` launch arguments.

### Files deleted

    Glutt/Services/Glasses/            GlassesSupport, GlassesMockRig, GlassesRunLog, NetworkProbe
    Glutt/Features/Glasses/            GlassesSpikeView
    Glutt/Services/Polly/MetaGlassesVisualSource.swift
    Glutt/Resources/GlassesMock/
    GluttTests/Glasses/

    Glutt/Features/Skills/SkillCoachSession.swift
    Glutt/Features/Skills/SkillCoachView.swift
    Glutt/Services/Polly/SkillCoachPrompt.swift
    Glutt/Services/Polly/SkillFrameRing.swift
    Glutt/Services/Polly/SkillLookRequest.swift
    GluttTests/SkillCoachSessionTests.swift

## What this costs

**Skills is photo mode only.** The live coaching session watched through the
glasses and its prompt said so in as many words, so it went with them. What
remains is a complete lesson: read it, watch the demonstration clip, try it,
send Chef two photos, get one correction back.

That path is not a consolation prize. It runs the same rubrics, the same
severity ladder, the same confidence floors and the same authored corrections,
because `SkillVisualAssessor.assess(check:frames:)` takes `[Data]` and never
cared where the bytes came from. For the knife grip it is arguably better:
nobody can see both faces of a blade from their own eyes, and a phone takes one
photo of each side.

**The cook session keeps its phone camera.** That was never glasses work and it
is legitimate, shipping functionality.

## What deliberately stayed

- **`SkillLearningMode`**, including the `.watching` case. `SkillAttempt`
  persists it, and the SwiftData schema has to stay identical to
  `skills-knife-coaching` or moving between builds becomes a migration. Only
  `.showing` is reachable here.
- **`PollyVisualSourceKind`**, now a one-case enum. The capture vocabulary is
  built around naming which source produced a frame.
- **The Facebook SDK** (`FBSDKCoreKit` and friends). That is Meta *advertising*,
  it has nothing to do with the glasses, and it already ships.

## How it was verified

Against a build in a pristine derived data path, because a stale artifact from a
previous workspace showed the MWDAT frameworks and briefly looked like a leak:

- `Frameworks/` contains no `MWDAT*`. Nothing named `mwdat` or `wearab`
  anywhere in the bundle.
- `strings` on the binary finds no `ray-ban`, `oakley`, `mwdat`, `com.meta.ar`,
  `glutt-wearables` or `fb-viewapp`.
- The generated `Info.plist` has none of the seven keys in the table above.
- The entitlements file has exactly two keys, app groups and Sign in with Apple.
- `Package.resolved` no longer lists `meta-wearables-dat-ios`.

## Working on both

Do the work on `skills-knife-coaching` and merge into `apple-ready`, resolving
in favour of removal. Never the other way round: a merge from `apple-ready` back
into the full branch would delete the glasses work, which is the one outcome
this arrangement exists to prevent.

Before any submission, re-run the audit above. A dependency update can put a
framework back without anybody writing a line of code.
