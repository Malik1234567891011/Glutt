# Glutt → App Store: what's left to get approved

Last updated: Jun 16, 2026. Repo is synced with `origin/main` (no changes from Omar).
App builds, runs, and passes its 87 unit tests.

This doc is: (1) how App Store review actually works in 2026, (2) where Glutt already
complies, (3) the concrete gaps left — split into **in-app/code** (we control in this repo)
and **App Store Connect / account** (Omar, on the paid account).

> TL;DR critical path: **Accounts/backend scope lock → privacy/legal + in-app disclosures
> → App Store Connect metadata + 6.9" screenshots + App Privacy answers → build with Xcode
> 26, archive, submit with reviewer notes.** Accounts are now in scope, which adds hard
> review requirements (account deletion + auth compliance) and backend reliability risk.

---

## 1. How review works in 2026 (the bar)

Apple rejects ~40% of first-time submissions, and ~95% of rejections are predictable.
The big buckets, in order of how often they fire:

1. **Guideline 2.1 — App Completeness.** #1 cause. A crash, a dead button, or a core
   feature the reviewer can't reach in the first ~5 minutes = instant reject. They test on
   real devices and spend minutes, not hours. A screen recording in Reviewer Notes helps.
2. **Guideline 5.1.1 — Privacy / data.** Apple's single most-cited rule. Needs: a valid
   **Privacy Policy URL** (in App Store Connect AND in-app), accurate **App Privacy
   labels** that match real behavior, a `PrivacyInfo.xcprivacy` manifest declaring
   Required-Reason APIs, and disclosure of any data shared with third parties.
3. **Guideline 2.3 — Accurate metadata.** Screenshots/description must match the shipped
   build. No "coming soon", no features not in the binary, no placeholder text.
4. **Guideline 4.x — Design / minimum functionality.** No web-wrapper, must be a real
   native app, not a copycat. (Glutt is fine here.)
5. **Account rules (5.1.1(v) / 4.8).** If you have accounts: in-app account deletion is
   required; if you offer other social logins, Sign in with Apple is required.
6. **AI disclosure (2025–26 update).** Apps that generate or display AI content must give a
   clear, user-facing disclosure of the AI provider and the nature of the content.
7. **Platform/binary.** As of **Apr 28, 2026, apps must be built with the iOS 26 SDK
   (Xcode 26)**. No "Test/Beta/Debug" strings in the name, screenshots, or app copy.
8. **Permissions.** Every `NS*UsageDescription` must clearly say what and why.

Sources: Apple Developer (Submitting, App Privacy Details, App Store Connect Help),
plus 2026 rejection-reason roundups (qawerk, launchshots, pushmyapp, appstorereview).

---

## 2. Where Glutt already complies ✅ (current codebase)

- **No IAP configured yet** → currently skips the whole 3.x payments bucket.
- **Privacy manifests present** — `Glutt/PrivacyInfo.xcprivacy` and
  `GluttShare/PrivacyInfo.xcprivacy` declare the only Required-Reason API we touch
  (`UserDefaults`, reasons CA92.1 + 1C8F.1) and state no tracking / no collected data.
- **Encryption** — `ITSAppUsesNonExemptEncryption = false` set in Info.plist; no export
  compliance prompt, no annual questionnaire.
- **Camera permission string** present and honest (`NSCameraUsageDescription`). Photo
  picking uses `PhotosPicker` (PHPicker, out-of-process) so it needs no library
  permission string.
- **Native, distinctive app** — Cook Mode, pantry-aware AI, import pipeline, planner. Not
  a web wrapper, not a copycat (clears 4.2/4.3).
- **Local-first data** — SwiftData on-device; nothing we store leaves the phone except the
  optional AI calls (see §4).
- **Light-mode locked, stable** — no obvious crash paths; empty states handled; 87 tests
  green.

### Scope change note (NEW)

Product decision changed: **accounts are now required** (no longer local-only forever).
That means we lose the previous compliance advantage around account rules and must add:
- auth + session flows that work during review;
- in-app account deletion;
- data export/delete behavior and support copy;
- revised App Privacy answers (potentially linked identity data).

---

## 3. What's LEFT — in-app / code (we control this repo)

These are things I can implement here. None are huge.

- [ ] **Privacy Policy + Support links in-app.** Apple wants legal links reachable
      from inside the app (Settings is the standard spot). Today `SettingsView` has none.
      → Add a "Privacy Policy", "Support / Contact", and "Terms" row that open the hosted
      URLs (URLs come from Omar/Malik once hosted).
- [ ] **AI & data disclosure (Guideline 5.1.1 + AI rule).** Glutt sends user content —
      recipe text/captions, pantry photos, meal photos — to **OpenAI** (`api.openai.com`)
      to power import cleanup, invent-from-pantry, photo pantry scan, photo meal logging,
      recipe adjust, leftover remix, and "Ask". This must be disclosed plainly to the user.
      We already label *outputs* ("Glutt invented this", "drafted by AI"), but we should add
      a one-paragraph in-app disclosure (Settings → AI section) saying *what is sent, to
      whom, and why*, and that AI content can be wrong. → Small copy addition.
- [ ] **Drop user-facing "beta" wording.** `SettingsView` shows `"AI enabled (beta)"`.
      Guideline says no "Beta/Test/Debug" in app copy. Rename to e.g. "AI features on".
      (The internal **Glutt Beta** *scheme* name is fine — not user-facing.)
- [ ] **Draft the Privacy Policy text** (deliverable in repo: `PRIVACY-POLICY.md`) so it
      can be hosted as the required URL. Must state: local + cloud account data model, no
      tracking, no ads; and that content/photos are sent to OpenAI for processing when AI
      features are used (and that OpenAI's API does not train on this data by default).

### 3A. NEW required workstream — accounts + backend

This is now a launch blocker, not backlog.

- [ ] **Auth architecture decision (must lock first).**
      - Option A (recommended): **Sign in with Apple only** for v1 accounts (lowest review
        risk, best Apple alignment, no password reset burden).
      - Option B: email/password (+ optional SIWA) if you need cross-platform parity now.
      - Avoid shipping only Google/Facebook login without SIWA.
- [ ] **Backend ownership + schema.**
      - Choose backend stack (Supabase/Firebase/custom) and freeze data model:
        `users`, `recipes`, `pantry_items`, `grocery_items`, `plans`, `leftovers`,
        `food_logs`, plus sync metadata (`updated_at`, tombstones, device clocks).
      - Add deterministic per-user isolation (row-level security / auth checks).
- [ ] **Data migration from local-only to account cloud.**
      - First login should offer "merge this device data into my account" with conflict
        strategy (latest wins + manual merge for recipe title collisions).
      - Keep an offline cache (SwiftData) with background sync; never block UI on network.
- [ ] **Auth UI + session management.**
      - Welcome/auth screen, signed-out state, loading/skeletons, retry/offline states.
      - Token refresh, sign-out, session expiry recovery.
- [ ] **In-app account management (App Review critical).**
      - Profile/settings with email/identifier display.
      - **Delete account in-app** (self-serve, not email support only), with clear
        consequences and final confirmation.
      - If email/password exists: password reset/change flows.
- [ ] **Privacy/security hardening for accounts.**
      - Add transport and at-rest posture docs; secret handling for backend keys.
      - Review logs/analytics to ensure no sensitive payload leakage.
- [ ] **Reviewer access strategy.**
      - If login is required, provide a stable reviewer test account OR ensure SIWA works
        cleanly in review. Broken login = 2.1 rejection.

> None of these block a TestFlight *beta* build, but the Privacy Policy URL + privacy
> answers are required to **submit for App Store review** (and TestFlight external testing
> needs a Beta App Review that checks similar things).

---

## 4. The AI + privacy nuance (read this — easy to get wrong)

Our `PrivacyInfo.xcprivacy` correctly says *we* collect/track nothing. But the **App
Privacy questionnaire** in App Store Connect asks about data handled by the app **and its
third-party partners**. Because we send user content to OpenAI:

- Be honest in the questionnaire. The safest accurate framing: data is used **only for App
  Functionality**, **not linked to identity**, and **not used for tracking**. Depending on
  how strictly you read it, "User Content" (the recipe text/photos) may need to be declared
  as collected-for-functionality rather than "Data Not Collected".
- The Privacy Policy must name OpenAI as a processor and link its policy.
- We do **not** send name, email, location, or contacts (we don't have them). Photos are
  sent only when the user explicitly taps scan/log-by-photo.

If you'd rather answer a clean "Data Not Collected", the alternative is to gate AI behind an
explicit per-feature opt-in/consent the first time — but disclosure + functionality-only is
the simpler, defensible path for launch.

---

## 5. What's LEFT — App Store Connect / account (Omar)

Needs the paid account; can't be done from the repo.

**Identifiers & capabilities**
- [ ] Set his `DEVELOPMENT_TEAM` in `project.yml`, `xcodegen generate` (see `FOR-OMAR.md`).
- [ ] Register App ID + the App Group (`group.com.malik.glutt` or his renamed one) and
      enable the App Groups capability on both App IDs.

**Hosting (blocks submission)**
- [ ] **Privacy Policy URL** — host the `PRIVACY-POLICY.md` text somewhere public (GitHub
      Pages, Notion public page, a one-pager site). Required for all apps.
- [ ] **Support URL** — a page or even a mailto-style support page. Required.

**App Store Connect record**
- [ ] Create the app (bundle ID match), pick primary category (Food & Drink).
- [ ] **Metadata**: name (≤30 chars), subtitle (≤30), description (≤4000), keywords (≤100
      total), promotional text (≤170). No "beta/coming soon"; match the real app.
- [ ] **Screenshots**: required **6.9-inch** iPhone set (1–10 images), real in-app UI, no
      false device frames. Capture the loop: import → plan → cook → invent-from-pantry.
      Optional app preview video (≤3).
- [ ] **App Privacy** questionnaire (see §4) + enter Privacy Policy URL.
- [ ] **Age rating** questionnaire (Glutt → 4+).
- [ ] Accessibility nutrition label (optional, nice-to-have).
- [ ] **Pricing/availability**: choose free vs paid vs subscription (if paid/subscription,
      set territories, tax category, trial, and subscription group copy in App Store Connect).
- [ ] **Content rights declaration**: confirm rights for imported images/content and trademark
      usage in listing assets (app name, icon, screenshots).

**If accounts are enabled (NEW required path)**
- [ ] Ensure App Privacy answers reflect account identifiers/profile data and whether data is
      linked to users (likely yes once accounts exist).
- [ ] Add clear account language in description/reviewer notes ("account required for sync").
- [ ] Verify account deletion path in shipped build before submitting (Apple checks this).

**Submit**
- [ ] Build with **Xcode 26** (project already targets `xcodeVersion: 26.2`), archive the
      **Glutt** scheme, upload.
- [ ] **Reviewer Notes**: explain import works by sharing a link from TikTok/Instagram/Safari
      or pasting a URL; note AI features call OpenAI. If login exists, include exact reviewer
      test credentials + account-deletion test steps. Attach a **screen recording** of the
      core loop (strongly recommended for 2.1).
- [ ] Submit to **App Review** for full release (not beta-only).

---

## 6. Non-code launch work (required, not optional)

### 6A. Website/legal presence
- [ ] Launch a simple public site (can be one page) with:
      - product overview + App Store badge,
      - **Privacy Policy** page,
      - **Terms of Use** page,
      - **Support/Contact** page.
- [ ] Buy/point a clean domain (recommended for trust): e.g., `glutt.app` or similar.
- [ ] Add uptime monitoring for support/privacy pages (broken legal links can block review).

### 6B. Brand + creative assets
- [ ] Finalize icon and product-page screenshots (consistent visual language, no placeholder text).
- [ ] Capture an App Preview video (optional but strongly recommended for conversion).
- [ ] Create a tiny **press kit** folder: logo (SVG/PNG), app icon, 5 screenshots, 1 paragraph blurb.

### 6C. Go-to-market copy + ASO
- [ ] App name/subtitle/keywords finalized from ASO pass (rank + readability).
- [ ] Description emphasizes core loop in first 3 lines (import → plan → cook → pantry AI).
- [ ] Localize metadata for top markets (at minimum EN + one target locale if applicable).

### 6D. Support + operations readiness
- [ ] Decide support channel + SLA (support email, response target, ownership).
- [ ] Set up issue intake board (support bugs vs feature requests triage).
- [ ] Create canned responses for top likely tickets: login/sync conflicts, AI output quality,
      import failures, account deletion/data concerns.
- [ ] Define incident owner for launch week (who responds if login/sync or API outage happens).

### 6E. Analytics + growth baseline
- [ ] Pick analytics/events stack before launch and freeze event taxonomy.
- [ ] Track core funnel events: onboarding complete, first import, first plan, first cook,
      first pantry scan, first AI action, D1/D7 retention.
- [ ] Set up a lightweight release dashboard (daily installs, crashes, key conversion rates).

### 6F. Commercial model
- [ ] Decide monetization at launch:
      - fully free,
      - paid upfront,
      - freemium/subscription (recommended if AI cost is meaningful).
- [ ] If subscription: define paywall copy, free trial policy, and restore purchases flow.
- [ ] Validate margin assumptions with OpenAI usage cost and expected active users.

---

## 7. Ordered critical path for FULL launch (updated for accounts)

1. **(product/engineering)** Lock account scope + auth approach (SIWA-only vs email+SIWA).
2. **(code/backend)** Build auth, account model, cloud sync, merge migration, account settings,
   and in-app account deletion.
3. **(code)** Add in-app legal links + AI/data disclosure, drop "beta" wording, write
   `PRIVACY-POLICY.md`.
4. **(ops/marketing)** Launch public website pages (privacy, terms, support) + finalize
   brand assets/screenshots/metadata copy.
5. **(code)** Wire hosted URLs in Settings and confirm links resolve.
6. **(Omar)** Set team, register App ID + App Group (and SIWA capability if used).
7. **(Omar)** App Store Connect: metadata, screenshots, App Privacy answers (account-aware),
   age rating, pricing/availability.
8. **(ops)** Freeze support ownership + analytics dashboard + launch-day incident plan.
9. **(Omar)** Build with Xcode 26 → archive → upload → reviewer notes + screen recording →
   submit to App Review.

**Biggest risks for us specifically now:** (a) account flows failing in review (auth/session),
(b) missing or non-functional in-app account deletion, (c) App Privacy answers not matching
account + OpenAI data flows, (d) legal/support URLs missing or broken, (e) launch assets/copy
promising features not actually shipped, and (f) crash on a device Omar didn't test.

---

## 8. Task split — Malik vs Omar (no stepping on toes)

Use this split so work can run in parallel with minimal blockers.

### Malik owns (product + app behavior + content)

- [ ] Product scope lock: auth mode, sync behavior, monetization model.
- [ ] App code/features: auth UX, sync UX, account deletion UX, legal link screens, AI disclosures.
- [ ] QA pass on real user flows: first-run, import, cook, pantry scan, account delete, offline recovery.
- [ ] All listing/copy drafts: app description, subtitle/keywords proposals, reviewer-notes draft.
- [ ] Legal text drafts: `PRIVACY-POLICY.md`, Terms draft, support FAQ/canned responses.
- [ ] Screenshot shot-list + capture direction (what each screenshot should prove).
- [ ] Launch analytics spec: events list and success metrics.

### Omar owns (Apple account + distribution + release ops)

- [ ] Apple account setup work: team ID, certificates/profiles, bundle/App Group registration.
- [ ] App Store Connect configuration: app record, metadata entry, screenshots upload, age rating.
- [ ] App Privacy questionnaire submission (using agreed data map).
- [ ] Pricing/availability + territories + tax/commercial settings.
- [ ] Final archive/upload from his signing environment and App Review submission.
- [ ] Launch-day release controls: manual/automatic release timing, phased release if used.
- [ ] Production monitoring ownership during review/launch window.

### Joint (must be explicitly handed off)

1. **Data map sign-off (joint):** what is sent to OpenAI + what account data is stored.
   - Output: one approved privacy matrix used by both code + App Store Connect answers.
2. **Legal URL handoff (Omar -> Malik):** hosted Privacy/Terms/Support URLs.
   - Malik wires URLs in-app; Omar verifies links in App Store Connect.
3. **Metadata truth check (joint):** screenshots/copy vs actual shipped build.
   - No promised features that are not in the binary.
4. **Pre-submit dry run (joint):** one full install-to-core-loop run on fresh real devices.
   - Malik drives UX acceptance; Omar validates signing/submission plumbing.

### Anti-collision rules (practical)

- Single source of truth for launch tasks: this file (`toAppstore.md`).
- One owner per task; never dual-own execution.
- Handoffs require an artifact, not a message:
  - URL handoff = actual live links,
  - privacy handoff = written matrix,
  - metadata handoff = final screenshot/copy pack.
- Freeze window: no net-new feature merges once App Store binary is being prepared.
- Branch discipline: Malik ships feature branches; Omar ships release/config branches.

### Suggested parallel schedule (fastest path)

- **Track A (Malik, now):** account/sync UX + legal/AI disclosure + policy drafts + shot-list.
- **Track B (Omar, now):** Apple identifiers/capabilities + App Store Connect skeleton + domain hosting.
- **Convergence:** legal URLs + privacy matrix + screenshot pack.
- **Final:** Omar archive/upload, both run final smoke test and reviewer-note check.
