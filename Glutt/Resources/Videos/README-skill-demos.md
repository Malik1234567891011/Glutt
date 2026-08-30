# Skill demonstration clips

The clips that play at the top of a lesson screen, in the slot `SkillLessonView`
reserved for them. A skill opts in by naming one in `animationAsset`, and the
name is the filename without the extension.

Today: **`knife-grip-pinch.mp4`** on `knife.grip`. 1280 × 720, 10s, no audio
track, 439KB.

## What makes a good one

These are demonstrations rather than wallpaper, which is the whole reason they
are treated differently from the onboarding videos in this same folder.

- **Show the thing the camera cannot.** The knife grip clip earns its place by
  showing the thumb side and the curled index finger SIDE BY SIDE. A cook
  wearing glasses can never see that on their own hand, because the two fingers
  are on opposite faces of the blade. The clip is not decoration, it fills a
  genuine hole in what Chef can show you about yourself.
- **Keep it short and let it loop.** Ten seconds, playing on repeat, no
  controls. Somebody learning a grip glances back at it repeatedly while their
  hands are busy, and a replay button is a button you cannot press with a knife
  in your hand.
- **Burned-in captions are fine, and they decide the framing.** Because the
  words sit at the edges of the frame, the player fits rather than fills
  (`LoopingVideoView(fills: false)`). Never crop one of these.
- **Mind the numbering.** The knife clip has its own step badges 1 to 4 and the
  lesson has its own numbered steps. They sit far enough apart on the screen to
  read as separate things, but a clip whose numbering contradicts the lesson
  would be worse than no clip.

## Encoding

```sh
ffmpeg -y -i <source>.mp4 \
  -an -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 27 -preset slow \
  -movflags +faststart -g 48 \
  Glutt/Resources/Videos/<name>.mp4
```

Why each part:

- **`-an`** strips the audio. The source for the knife grip had a track, and it
  measured a mean of −46.7 dB, which is silence with room tone. A demonstration
  has nothing to say out loud, and Chef is usually talking over it. With no
  track at all it can never duck the user's music or interrupt her.
- **`-crf 27`** took the knife clip from 5.0MB to 439KB with no visible loss on
  the captions, which are the part that has to survive. These ship inside the
  app, so every megabyte is paid for by every download whether the clip is
  watched or not. `SkillRubricIntegrityTests` fails the build above 2MB.
- **`+faststart`** puts the index at the front so playback starts immediately
  rather than after the file is walked.
- **`-g 48`** gives a keyframe every two seconds at 24fps, which keeps looping
  cheap.

## Checks

`SkillRubricIntegrityTests` covers both failure modes that are invisible in
source: a name that does not resolve to a bundled file, which renders as an
empty card, and a file that has grown past 2MB.
