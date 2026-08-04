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
| `.agents/skills/` | Existing skills (migrate/symlink into `.claude/skills/` for Claude Code) |

Tabs (implemented order): Today → Recipes → **Polly** → Plan → Kitchen → Progress.

## Commands

```bash
xcodegen generate                    # after editing project.yml
# Prefer XcodeBuildMCP over raw xcodebuild (see Tooling).
# Fallback when MCP unavailable:
xcodebuild test -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
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
- **UI copy:** never use dashes as punctuation (no em/en dashes, no spaced hyphens). Commas/periods/reword. Hyphenated compounds (`gluten-free`) are fine. See design handoff `PROJECT-RULES.md`.
- After `project.yml` changes: `xcodegen generate` before building.
- Prefers **verify on simulator** for UI/Polly/clip work, not “compiles so ship it.”

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

Project skills today live under `.agents/skills/` (grilling, research, to-tickets, improve-codebase-architecture, writing-great-skills). For Claude Code, prefer `.claude/skills/` — symlink or copy those folders so `/grilling` etc. resolve.

Path-scoped rules: `.claude/rules/`.
