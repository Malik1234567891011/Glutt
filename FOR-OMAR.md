# Glutt — TestFlight handoff (for Omar)

Hey Omar — this is everything you need to take Glutt from this repo to TestFlight.
It already builds, runs, and passes its tests. Your job is signing + App Store Connect,
and (optionally) dropping in the AI key.

The app is **local-first** (SwiftData on-device, no backend, no accounts). The only
network calls are optional AI features hitting OpenAI. If the AI key is empty, the whole
app still works — those features just fall back to on-device logic.

---

## 0. Prerequisites

- **Xcode 26.x** (project is set to `xcodeVersion: 26.2`, deployment target iOS 17).
- **XcodeGen** — the `.xcodeproj` is generated from `project.yml`, so install this:
  ```sh
  brew install xcodegen
  ```
- Your **paid Apple Developer account** added to Xcode (Settings → Accounts).

---

## 1. Get it building

```sh
git clone https://github.com/Malik1234567891011/Glutt.git
cd Glutt
xcodegen generate        # regenerates Glutt.xcodeproj from project.yml
open Glutt.xcodeproj
```

Two schemes exist:
- **Glutt** — normal Debug run (seeds demo data, skips onboarding). Use for dev.
- **Glutt Beta** — Release build, no demo data, onboarding from zero. **This is what
  testers get — use it to sanity-check before archiving.**

Run the tests anytime with ⌘U on the **Glutt** scheme (84+ unit tests).

---

## 2. Signing — make it yours (required)

`project.yml` currently pins Malik's team ID. Change it to yours:

1. Open `project.yml`, line ~12, under `settings.base`:
   ```yaml
   DEVELOPMENT_TEAM: K8MRHHZ85N   # <- replace with YOUR team ID
   ```
   (Find your team ID at developer.apple.com → Membership, or let Xcode auto-fill it.)
2. Regenerate: `xcodegen generate`
3. In Xcode, both targets (**Glutt** and **GluttShare**) should show "Automatically
   manage signing" with your team. Signing style is already Automatic.

> Tip: edit `project.yml`, **not** the Xcode project directly — `xcodegen generate`
> overwrites `Glutt.xcodeproj` every time.

---

## 3. Bundle ID + App Group — rename to your namespace (recommended)

Right now everything is under `com.malik.glutt`. To ship under your own account you'll
likely want your own identifiers. The share extension talks to the app through an
**App Group**, so the app + extension + group must all stay in sync. Change these:

| Where | Current value | What it is |
|---|---|---|
| `project.yml` → `options.bundleIdPrefix` | `com.malik` | prefix |
| `project.yml` → Glutt target `PRODUCT_BUNDLE_IDENTIFIER` | `com.malik.glutt` | app ID |
| `project.yml` → GluttShare target `PRODUCT_BUNDLE_IDENTIFIER` | `com.malik.glutt.share` | extension ID |
| `Glutt/Glutt.entitlements` | `group.com.malik.glutt` | app group |
| `GluttShare/GluttShare.entitlements` | `group.com.malik.glutt` | app group |
| `GluttShare/ShareViewController.swift` | `group.com.malik.glutt` | `appGroupID` constant |
| `Glutt/Services/Import/PendingImportStore.swift` | `group.com.malik.glutt` | app group constant |

After editing, run `xcodegen generate` again. In the Apple Developer portal, register
the App Group and make sure both App IDs have the **App Groups** capability enabled.

If you'd rather not rename, you can keep `com.malik.glutt` as long as the identifiers
aren't already registered to another team — but renaming to your own is cleaner.

The custom URL scheme is `glutt://` (deep links / share extension). No need to change it.

---

## 4. AI key (optional, but it's a big part of the magic)

The AI key is **not** in the repo on purpose. `Glutt/Services/AI/Secrets.swift` ships as
an empty placeholder:

```swift
static let embeddedAIKey = ""   // empty = AI falls back to on-device heuristics
```

Without a key the app fully works; these features just won't use GPT:
import cleanup, **invent-a-dish-from-your-pantry**, **photo pantry scan**, **photo meal
logging**, recipe adjust ("make it higher-protein"), leftover remix, and "Ask Glutt".

To turn AI on for the beta:

1. Get the key from Malik (he'll send it privately — **never** paste it into a commit,
   PR, or Slack channel that's logged).
2. Put it in `Glutt/Services/AI/Secrets.swift`:
   ```swift
   static let embeddedAIKey = "sk-...the key..."
   ```
3. **Set a monthly spend limit** on that key first:
   platform.openai.com → Settings → Limits. This key is baked into beta builds, so the
   cap is your safety net.

> Note: `Secrets.swift` is tracked but `git update-index --skip-worktree`'d, so your local
> key won't accidentally get committed. If you ever need git to see changes to it again:
> `git update-index --no-skip-worktree Glutt/Services/AI/Secrets.swift`.

---

## 5. Archive + upload to TestFlight

1. Bump the build number if you're re-uploading: `project.yml` →
   `CURRENT_PROJECT_VERSION` (both targets), then `xcodegen generate`.
   (`MARKETING_VERSION` is `1.0`.)
2. In Xcode: select the **Glutt** scheme, destination **Any iOS Device (arm64)**.
3. **Product → Archive** → Distribute App → App Store Connect → Upload.

---

## 6. App Store Connect checklist

- Create the app record (matching your bundle ID).
- **App Privacy**: the app does **not** collect or track data. Required-reason API
  manifests (`PrivacyInfo.xcprivacy`) are already in the app and the share extension,
  declaring only `UserDefaults` usage (app settings + app group). Answer the privacy
  questionnaire as "Data Not Collected".
- **Encryption**: `ITSAppUsesNonExemptEncryption` is already set to `false`, so you
  shouldn't get the export-compliance prompt.
- **Beta App Review notes** (for external testing): mention that the app is local-only,
  needs no login, and that recipe import works by sharing a link from TikTok/Instagram/
  Safari or pasting a URL. If AI is enabled, note it calls OpenAI for optional features.
- Add testers (internal first; external groups need a quick Beta App Review).

---

## Quick reference

- Repo: https://github.com/Malik1234567891011/Glutt.git
- App bundle ID: `com.malik.glutt` · Extension: `com.malik.glutt.share` · Group: `group.com.malik.glutt`
- URL scheme: `glutt://`
- Schemes: `Glutt` (dev) · `Glutt Beta` (Release/TestFlight-identical)
- AI key file: `Glutt/Services/AI/Secrets.swift`
- Regenerate project after any `project.yml` / identifier change: `xcodegen generate`

The full feature/decision log lives in `plan.md` if you want context on anything.
