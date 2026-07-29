# App Store screenshot pipeline

Regenerates the panels in `~/Desktop/glutt-appstore/panels/`. See
`docs/appstore-screenshots-prompts.md` for the design spec and the why.

    export GEMINI_KEY=...           # needs BILLING ENABLED; free tier is limit:0 for image models
    echo "$GEMINI_KEY" > .gemini_key   # gitignored — never commit this
    python3 gen.py --prompt-file prompts/scene-band-1.txt --refs out/bear-wave-v2.png \
        --out out/scene-band-1.png --ar 16:9 --size 2K
    python3 compose.py p1 out/panel-1.png

`panels.py` holds one dict per panel. Paths in it point at a scratchpad; repoint `S`
at this directory and drop `shots/`, `props/`, `out/` and `refs/` alongside it.
