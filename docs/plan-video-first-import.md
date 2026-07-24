# Video-first recipe import (in progress)

Branch: `feat/video-first-import`

## Goal

Move social import from **text-first** (caption → AI reconstruct) to **evidence-first**:

> Listen to everything said, read everything shown, inspect what physically happens, compare all three, then compile the recipe.

## Phase 1 — shipped on this branch (local)

```text
TikTok / YouTube URL
 ├── existing caption / description extraction
 ├── ElevenLabs Scribe v2 via proxy (source_url)
 └── compile caption + timestamped transcript → structured recipe
      └── light verifier (ingredient names must appear in evidence)
           └── existing reconstruct / inferSteps only as last resort
```

### New pieces
- `vercel-ai-proxy/api/import/transcribe.js` — needs `ELEVENLABS_API_KEY` on Vercel
- `SpeechTranscriptionClient` — app → proxy (never talks to ElevenLabs directly)
- `VideoTranscript` / wire decode for Scribe word timestamps
- `VideoRecipeCompiler` — LLM extract-from-evidence (not freestyle)
- `ImportPipeline` — listens before cleanup/reconstruct for tiktok/youtube

### Deploy note
Set `ELEVENLABS_API_KEY` on the Vercel project and redeploy before speech imports work in production. Without it, the pipeline soft-fails listening and falls back to the old caption path.

## Later phases (not yet)
2. Frame OCR (on-screen quantities)
3. Visual action understanding (Gemini / sampled frames)
4. Full temporal evidence fusion + conflict UI
5. Import ↔ Polly timestamp deep links
