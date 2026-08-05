# CLAUDE.md

Operating contract for Claude Code in this repo. Keep this file short — deep procedures live in skills or `.claude/rules/`.

## What this is

**Glutt** — native iOS cooking assistant (SwiftUI + SwiftData, iOS 17+). Local-first; AI/import/media go through a Vercel proxy + optional Supabase media pipeline.

Repo folder is still `Cook4Me`. Product name is **Glutt**. GitHub: `Malik1234567891011/Glutt`.

## Layout

| Path | Role |
|------|------|
| `Glutt/` | iOS app (`App`, `Features`, `Models`, `Services`, `DesignSystem`) |
| `GluttShare/` | Share extension |
| `GluttTests/` | Unit tests (run via `Glutt` scheme) |
| `project.yml` | XcodeGen source of truth → `Glutt.xcodeproj` |
| `vercel-ai-proxy/` | AI proxy, import scrape, media signed URLs |
| `media-worker/` | yt-dlp / FFmpeg / pilot clip materialization |
| `supabase/migrations/` | Media schema (apply in Supabase SQL editor) |
| `docs/` | Product, plans, research notes, go-live scripts |
| `.agents/skills/` | Skill sources, symlinked into `.claude/skills/` |
| `build/` | Generated. Vendored SPM checkouts, ignore when searching |

Tabs (implemented order): Today → Recipes → **Polly** → Plan → Kitchen → Progress.

## Commands

```bash
xcodegen generate                    # after editing project.yml
# Prefer XcodeBuildMCP over raw xcodebuild (see Tooling).
# Fallback when MCP unavailable (omit OS= so it picks the installed runtime):
xcodebuild test -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:GluttTests/<Suite>

cd media-worker && npm run serve-local   # local pilot clip server
cd vercel-ai-proxy && vercel dev          # local proxy when needed
```

Secrets: gitignored `Glutt/Services/AI/Secrets.local.plist` (copy from `Secrets.local.example.plist`). Never commit real keys, `.env`, or signed URL dumps.

## Tooling

1. **XcodeBuildMCP** for build / run / test / sim / screenshots. Call `session_show_defaults` first; set project `Glutt.xcodeproj`, scheme `Glutt` (or `Glutt Beta` for seeded demo), a phone simulator.
2. Fall back to shell `xcodebuild` only if MCP can't do the job.
3. For higher-level sim UI flows: `ios-simulator-skill@conorluddy`.
4. Supabase MCP is configured in `.mcp.json` when DB/storage work is needed.

## Hard rules

- **Do not commit or push unless Malik explicitly asks.** Never `--no-verify`, force-push `main`, or amend others' commits.
- **Do not invent product behavior.** Prefer `docs/product.md`, `docs/structure.md`, and existing code over improvising UX.
- **Match surrounding code.** Small diffs. No drive-by refactors, no unsolicited markdown docs.
- **UI copy:** never use dashes as punctuation (no em/en dashes, no spaced hyphens). Commas/periods/reword. Hyphenated compounds (`gluten-free`) are fine. See `design-doc/glutt-design-context/design_handoff_glutt_app/PROJECT-RULES.md`.
- **Never hand-edit `Glutt.xcodeproj`.** It's tracked but generated. Edit `project.yml`, then `xcodegen generate`.

## Autonomy

Once the task is clear, run it to completion without checking in. Don't ask to read a file, grep, build, run tests, drive the simulator, or write scratchpad files. Don't narrate tool calls or list what you're about to do. Come back when it's done or when genuinely blocked.

Stop and ask only for these:

- **Design and product decisions.** UX, copy, naming, data shape, architecture, anything with more than one defensible answer. Never pick one silently, even if the choice looks obvious. Use `/grilling`: one question at a time, recommend an answer, wait.
- **Commits, pushes, and anything touching `main`.** Every time, even mid-task.
- **Destructive or irreversible actions.** Deleting files, rewriting history, DB migrations, anything outward-facing.

For anything else that comes up mid-task, assume the sensible default, say what you assumed, and keep going. A question that stops the work is only worth it when proceeding either way would be unsafe or would waste the work if wrong.

## Definition of done

Never report a change as working until:

1. Build is clean, 0 errors, via XcodeBuildMCP.
2. `GluttTests` is green. Baseline as of 2026-08-04: **475 passed, 0 failed, 0 skipped**. If the total drops, say why.
3. The change is **driven in the running app**, every time, not just when it's UI work. Follow `/verify-in-app`. Green tests are the floor, not the proof.
4. Failures are reported with the real output. Never round a red run up to "mostly passing", and say plainly what you did not verify.

Note: the simulator uses the Mac's network stack, TLS fingerprint, and egress IP. It cannot reproduce anything that depends on being a real phone on a real connection. Go to the device for that.

## Explaining bugs

Any time you report what went wrong, use `/explain-bug`: plain English, then technical facts, then fix, then difficulty. Four sentences maximum, cause first, no story of the investigation.

## How Malik works (match this)

- Demo-driven: bundled chef dishes, go-live checklists, voice scripts — prove it in the app.
- Plans live in `docs/` (`goLivePlan.md`, `goLiveTestScript.md`, `voiceTestScript.md`, `video.md`, Polly plans). Read the relevant doc before large work; don't rewrite the plan unless asked.
- Decisions: use `/grilling` (or the grilling skill) — one question at a time, recommend an answer, wait.
- Research: use the research skill → write a cited Markdown note under `docs/`.
- Tickets: `/to-tickets` for tracer-bullet vertical slices with blockers.
- Communication: concise, direct, minimal bold. Lead with the answer. Don't narrate tool use.

## Domain hotspots (read before editing)

- **Polly / cook session:** `Glutt/Features/Polly/`, `Glutt/Services/Polly/` — Realtime WebRTC, cook plans, tool registry, clip autopilot.
- **Native clips:** `Glutt/Services/CookClips/NativeClipService.swift` — `assignClips` must stay **1:1** (no reused segments). Clips are for bundled chef dishes; imports gate generation off (`MediaClipConfig`).
- **CookPlan:** cold technique steps must stay cookable (don't drop all `kind == .prep`). Setup = Tools/Prep by **id**, not kind. Cache epoch bumps when plan shape changes.
- **DietGuard:** `Glutt/Services/DietGuard.swift` — keyword diet rules; plant dairy / `vegan …` labels must not false-positive.
- **Media pilots:** `media-worker/fixtures/`, `finishPilot.js`, `npm run sync:supabase`. Progress notes in `media-worker/PROGRESS.md`.
- **Import:** link / screenshot / share sheet / Pinterest / Instagram paths via proxy + on-device parsers.

## Docs map

| Need | Open |
|------|------|
| Product / nav | `docs/product.md`, `docs/structure.md` |
| Proxy setup | `docs/AI-PROXY-SETUP.md` |
| Pre-push manual QA | `docs/goLiveTestScript.md` |
| Voice QA | `docs/voiceTestScript.md` |
| Clip pipeline | `docs/video.md`, `docs/donwloadplan.md`, `media-worker/PROGRESS.md` |
| Polly voice design | `docs/PollyNewGuide.md`, `docs/plan-polly-*` |
| Design handoff | `design-doc/glutt-design-context/` |

## Skills

Sources live in `.agents/skills/`, symlinked into `.claude/skills/` so `/verify-in-app`, `/explain-bug`, `/grilling`, `/research`, `/to-tickets`, `/improve-codebase-architecture`, `/writing-great-skills` resolve. Add a new skill in `.agents/skills/`, then symlink it.

Path-scoped rules load automatically by file glob: `.claude/rules/ui-copy.md`, `polly-clips.md`, `media-worker.md`.
