# AGENTS.md

Guidance for Codex when working in this repository.

## Project

Glutt is a native iOS app (SwiftUI, iOS 17+) built with [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth, `Glutt.xcodeproj` is generated.

- **Project:** `Glutt.xcodeproj`
- **App scheme:** `Glutt` (`Glutt Beta` is a Release-config scheme that seeds demo data on Run)
- **Test scheme/target:** `GluttTests` (run via the `Glutt` scheme)
- **Bundle ID:** `com.omarlahmimi.glutt`
- **Share extension:** `GluttShare` target
- If you edit `project.yml`, regenerate with `xcodegen generate` before building.

## Tooling — use XcodeBuildMCP for everything Xcode

**Always use the XcodeBuildMCP server for building, running, testing, and simulator work — not raw `xcodebuild`/`xcrun` shell commands.** Prefer the MCP tools for any Apple-platform task (build, run, test, install, launch, log capture, UI automation, screenshots).

- Before your first build/run/test call in a session, call `session_show_defaults` to confirm the active project, scheme, and simulator. If they aren't set, use `discover_projs` / `list_schemes` / `list_sims` and `session_set_defaults`.
- Build & run on a simulator: `build_run_sim` (often with empty args once defaults are set).
- Run tests: `test_sim`.
- Capture screenshots / inspect UI: `screenshot`, `snapshot_ui`.
- Only fall back to shell `xcodebuild` if an XcodeBuildMCP tool genuinely can't do the job.

## Simulator skill

For simulator-driven testing and UI automation, also use the **`ios-simulator-skill@conorluddy`** plugin/skill (29 scripts for build automation, semantic UI navigation, accessibility testing, and simulator lifecycle management). Reach for it when XcodeBuildMCP's simulator tooling needs higher-level scripted flows.
