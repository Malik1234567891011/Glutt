---
paths:
  - Glutt/Features/Polly/**/*
  - Glutt/Services/Polly/**/*
  - Glutt/Services/CookClips/**/*
  - GluttTests/**/*Clip*
  - GluttTests/**/*CookPlan*
  - GluttTests/**/*Polly*
---

# Polly + native clips

- Prefer native Supabase / pilot clips over Gemini YouTube timestamps when ready for the media id.
- Assignment is **unique**: `NativeClipService.assignClips` — never reuse a `segmentID` across cook steps. Keyword overlap (vanilla/cream/sugar) is why duplicates used to happen.
- Skip setup steps (`CookPlan.isSetupStep` — Tools/Prep by **id**) when building the cook-step list for clips.
- Do not treat every `kind == .prep` as setup; cold technique (whisk yolks, strain custard) must keep clips and stay on the cook path.
- After plan-shape fixes, bump `CookPlanCompiler.cacheEpoch` so stale cached plans aren't reused.
- Clip generation is off for imports; bundled chef dishes keep clips (`MediaClipConfig`).
- When changing matching/assignment, add/extend unit tests (`NativeClipAssignTests`, CookPlan tests). Verify with a **fresh** cook session on device/sim, not a resumed one.
