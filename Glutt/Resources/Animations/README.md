# cooking-loop.mp4

The import loading screen's animation (`CookingLoopView`). **940 × 940, 12s,
seamless, no audio track, 640KB.**

Do **not** replace this with `design-loading/animation/cooking-loop.mp4`. That
file is the raw 1080 × 1920 source: it carries a `hera.video` watermark across
the top, and a portrait clip dropped into the square frame letterboxes to roughly
half size. Regenerate with:

```sh
ffmpeg -y -i design-loading/animation/cooking-loop.mp4 \
  -vf "crop=940:940:69:422,format=rgb24,lutrgb=r='clip(val+1,0,255)':g='clip(val+3,0,255)':b='clip(val+3,0,255)',format=yuv420p" \
  -an -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 18 -preset slow -g 60 \
  -movflags +faststart Glutt/Resources/Animations/cooking-loop.mp4
```

Why each part:

- **`crop=940:940:69:422`** — the artwork occupies x 190–888, y 460–1324 of the
  source and the watermark ends at y≈200, so this square is centred on the pot
  and starts well clear of the mark. Keep all 12s: the loop is seamless and
  trimming it shows a jump.
- **`-an`** — there is no reason for a decorative loop to carry audio, and with
  no audio track it can never duck or interrupt the host app's audio session.
  That matters: this plays inside the share extension, over Instagram.
- **`lutrgb=+1/+3/+3`** — the source background is `#F9F0E5`, the sheet is
  `#FAF3E7`. Without the nudge the clip reads as a faint square panel on the
  sheet. The offsets are tuned against **what the simulator actually renders**,
  not against an `ffmpeg` frame dump — AVFoundation colour-manages playback, so
  a decoded PNG measures differently from the screen. Lands on `#FBF3E7`, one
  step of red off and invisible. The yuv channels are coupled, so nudging one
  offset moves the others; re-measure on screen after any change.
