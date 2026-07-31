The final product should feel video-first without feeling like a social feed.

The core design principle

During a cooking session, the screen should communicate:

One immediate action, one visual answer, and one effortless way to reach Polly.

Not the whole recipe.
Not the whole conversation.
Not every possible control.

The screen should answer four questions almost instantly:

What am I doing?
What should it look like?
Can Polly hear me?
What happens next?

Apple’s current design guidance emphasizes establishing hierarchy between content and controls, with navigation and interface elements elevated above the content rather than every section competing equally. Materials such as Liquid Glass are useful for lightweight floating controls, while important reading surfaces need enough opacity and contrast to remain legible.

The final design direction
“Adaptive Video Canvas”

The screen has three permanent layers:

A full-screen vertical visual canvas
A floating step sheet
A compact Polly dock

Everything else appears temporarily or lives behind a gesture/menu.

1. Full-screen video canvas

The recipe video fills the entire screen behind the interface.

For an iPhone-width canvas, use a true 9:16 derivative rather than placing a landscape rectangle inside the page. The video should extend:

behind the status bar;
behind the navigation controls;
behind the step sheet;
almost to the bottom edge.

The footage becomes the visual identity of the screen.

Default state

The video does not need to autoplay immediately.

It begins as a high-quality poster frame showing the most useful visible moment:

the pan;
the hands;
the relevant ingredient;
the final texture;
the specific technique.

In the center:

▶  Watch example
   14 sec

Not:

Watch the Parma ham crisp · 2:25–3:21

The user does not care where the moment occurred in the original video. They care about what it will teach them.

Better clip labels:

See how crisp the edges should get
Watch how tightly to wrap it
See the correct sauce thickness
Watch the folding technique
See what “golden brown” looks like
Video overlays

Keep overlays minimal:

Top-right

A 44-point circular audio control:

muted by default;
tap to hear original audio;
visually distinguishes muted versus playing.
Bottom-left, above the sheet

A restrained attribution:

From Gordon Ramsay

or:

Original recipe video

Tapping it can reveal:

creator;
full-video title;
open original source;
attribution details.

Do not display:

likes;
comments;
view counts;
save counts;
a fake TikTok sidebar;
the creator’s social bio.

Those make the user feel like they entered a feed instead of a cooking tool.

Playback progress

Use a thin two- or three-point line at the bottom of the visible video.

No large scrubber unless the user expands the video. These are short instructional clips, usually 8–20 seconds.

2. Top navigation

The top controls float above the video using a dark material or restrained Liquid Glass treatment.

Left

A circular chevron.down, not a red end-call button.

Tapping it minimizes or exits the full cooking screen without immediately destroying the session.

Actual End cooking session belongs inside the overflow menu and requires confirmation.

Center
Eggs Benedict
Step 2 of 8

Recipe name:

16–17-point semibold;
one line;
truncate only for very long titles.

Progress:

13–14-point secondary text.

Do not make elapsed call time the subtitle. 0:18 currently reinforces the FaceTime metaphor.

Elapsed cook time can exist:

in the overflow menu;
in the complete recipe sheet;
or beside an active recipe-level timer when useful.
Right

A circular ellipsis menu containing:

View full recipe
Ingredients
Adjust servings
Cooking settings
Transcript
Report incorrect video
End cooking session
Recipe progress

Place a thin progress line below the navigation:

━━━━━━━━━━━━────────────

Use one continuous indicator rather than eight thick individual bars.

The text already says Step 2 of 8; the line exists only for fast peripheral understanding.

3. The floating step sheet

This is the most important UI element after the video.

It sits over the lower part of the canvas with a warm, nearly opaque charcoal surface.

Do not make this sheet highly transparent. It contains the instruction the user needs to read from several feet away. Apple notes that thicker materials provide better contrast for text and fine details, while thinner ones retain more background context.

Default dimensions

Using approximately 390 × 844 logical points as the baseline:

left/right margin: 14–16 points;
corner radius: 28–30 points;
default height: approximately 215–245 points;
bottom position: approximately 78–92 points above the screen bottom;
internal padding: 20–22 points.

It should overlap the video rather than push the video upward.

Sheet content
Eyebrow
STEP 2  ·  ACTION 1 OF 4
12–13 points;
semibold;
green;
slightly increased letter spacing.

Only say Action 1 of 4 when there genuinely are four checkable actions.

Your current screen says 0/4 done but displays only one task, which makes the interface feel internally inconsistent.

Step title
Warm the ham
28–32 points;
semibold;
warm white;
maximum two lines.
Instruction
Place it in a dry pan over medium heat.
Turn it once the edges begin to crisp.
18–20 points;
regular;
25–28-point line height;
maximum three lines in the default sheet.

This needs to be written as an immediate instruction, not copied mechanically from the recipe.

Bad:

Warm the ham or Canadian bacon in a pan.

Better:

Warm it in a dry pan over medium heat. Turn it once the edges begin to crisp.

Completion action

Use one clear, inset button:

✓ Mark action done

The entire button should have at least a 44-point hit region, and surrounding controls need enough separation to reduce accidental taps while someone’s hands are wet or messy. Apple recommends at least 44 × 44 pt for standard iOS touch targets.

This button can also be voice-operated:

“Polly, done.”

Next step

At the bottom of the sheet:

UP NEXT
Make the hollandaise

Keep it quiet and secondary. It helps the user understand the flow without competing with the immediate action.

Step sheet interaction states
Default — instruction state

Shows:

action number;
title;
concise instruction;
complete button;
next step.
Expanded — checklist state

The user swipes the sheet upward or taps Action 1 of 4.

The sheet expands to show all subactions:

1  Warm the ham
2  Separate the eggs
3  Melt the butter
4  Prepare the blender

The current action receives the strongest emphasis.

Previous actions have checks. Future actions remain muted.

Do not permanently write:

Swipe for steps · tap to check off

That belongs in first-use onboarding and disappears afterward.

Video-playing state

When the clip begins, the sheet reduces to a shorter “mini” state:

STEP 2

Warm the ham

[ Pause video ]       0:08 / 0:14

This exposes more of the demonstration.

When playback finishes, the sheet returns to its normal height.

No-video state

Not every action needs footage.

When there is no useful video:

display a high-quality target-state image;
use a subtle ingredient/recipe background;
or allow the instruction sheet to become slightly taller.

Do not insert irrelevant footage merely to preserve visual symmetry.

4. Polly dock

The current three-button call interface should disappear.

The red telephone button is one of the biggest reasons the current screen feels like a call instead of a cooking product.

Replace it with one persistent dock:

[ waveform ]  Say “Polly” or tap     [ camera ]
Shape

A floating capsule:

height: 58–64 points;
left/right margin: 16 points;
warm-black material;
small shadow or border;
positioned just above the bottom safe area.
Left side

An animated Polly waveform/orb.

It should become Glutt’s recognizable visual language.

Possible states:

subtle green pulse: wake word available;
expanding waveform: listening;
soft rotating form: thinking;
moving waveform: Polly speaking;
pause symbol: video playing.
Center

State-dependent copy:

Dormant
Say “Polly” or tap to talk
Wake detected
Listening…
Processing
Thinking…
Speaking
Polly is helping
Video playing
Playing example
Right

A camera button.

Tapping it transforms the visual canvas from source video into camera-check mode.

Microphone mute can live:

in a small secondary button next to the dock;
inside the overflow menu;
or through a long-press on the Polly dock.

It should not be one of three equally large “call” controls.

5. Polly’s response text

Polly’s entire response should not permanently occupy the center of the screen.

The current paragraph is long and visually competes with the recipe.

While Polly is speaking

A temporary bubble appears immediately above the dock:

You’re missing a few ingredients.
Should I adapt this to what you have?

Rules:

maximum three visible lines;
left aligned;
not centered;
large enough to read;
slightly opaque dark material;
animates in as Polly begins;
collapses after Polly finishes.
After she finishes

The bubble becomes:

Polly suggested adapting the recipe  ›

Tapping opens the full transcript.

This keeps important information retrievable without letting previous conversation dominate the current action.

6. Camera-check state

Camera should use the exact same visual canvas as video.

Do not navigate to a completely different page.

When the user says:

“Polly, look at this.”

The transition is:

Recipe video
      ↓
Live camera preview
      ↓
Capture frame for Polly
      ↓
Processing state
      ↓
Polly result
      ↓
Return to recipe video/poster
Camera UI

Over the live camera:

top-left Back to step;
top-center Show Polly your pan;
framing guide;
large capture button;
optional flash;
concise privacy/status text.

The bottom sheet remains, but shortens:

Warm the ham

Show Polly the color and texture.

This preserves context—the user never forgets which step the camera check belongs to.

7. Active timer treatment

Timers should float over the video rather than appearing inside a giant card.

Example:

HOLLANDAISE
02:14

Use a small pill near the upper-right or immediately below the navigation.

When there are several timers, show:

2 active timers

Tapping opens the timer stack.

When a timer is within approximately 10 seconds of finishing, it can temporarily become more prominent.

8. Visual design system
Colors

Suggested starting palette:

Purpose	Value
Main warm black	#0C0B09
Elevated surface	#181612
Step sheet	#201D18
Primary text	#F6F2EA
Secondary text	#AAA39A
Muted text	#777169
Glutt green	#80E3A0
Green pressed	#62C982
Warning	#F0B85A
Destructive	#FF5B50

The source video should supply most of the visual color. The interface exists to frame it.

Typography

Use SF Pro and Dynamic Type rather than an unusual branded font.

Suggested baseline:

Element	Size
Step title	30 pt semibold
Main instruction	19 pt regular
Recipe title	17 pt semibold
Polly response	18 pt regular
Button	17 pt semibold
Eyebrow label	12–13 pt semibold
Secondary metadata	13–14 pt

Apple’s system font automatically fits the platform, and Dynamic Type allows users to scale text for readability. Apple recommends supporting enlarged type and keeping routine iOS text around the system’s readable defaults.

Spacing

Use an eight-point system:

8: tight internal relationship;
12: related icon/text;
16: standard screen margin;
20–24: card padding;
32: separation between major sections.
Corners
step sheet: 28–30 points;
floating circles: fully circular;
Polly dock: 30–32 points;
video itself: no visible corner radius because it fills the canvas;
expanded sheets: align curvature with the iPhone hardware.
Borders

Use very few.

The existing design has borders around almost everything, causing all components to feel equally important.

Prefer:

elevation;
opacity changes;
slight material separation;
one-pixel border only where contrast requires it.
9. What should be removed from the current design

Remove:

large red hang-up button;
call elapsed timer as primary metadata;
permanent book icon;
huge transcript paragraph;
landscape video box;
carousel dots;
“Swipe for steps” instructional text;
thick segmented progress bars;
0/4 done when only one checkbox is visible;
social engagement icons;
video source timestamp range;
multiple equally prominent cards.

Keep, but redesign:

recipe title;
step progress;
current action;
action completion;
clip mute control;
next step;
Polly wake status;
camera access;
complete recipe access.
Turning horizontal YouTube footage into vertical Glutt footage

Once the rights-cleared source video has been downloaded, Glutt should generate its own vertical derivative.

Do not rely on the iPhone simply zooming a horizontal video into a vertical player.

Apple’s resizeAspectFill preserves aspect ratio and fills the player, but it does so by cropping whichever dimension overflows. It does not understand that the pan and hands are more important than the chef’s face.

Every clip should receive one of four treatments
Mode 1 — Native vertical

Source is already 9:16 or close.

Examples:

TikTok;
Instagram Reel;
YouTube Short;
creator-shot portrait footage.

Treatment:

preserve the original composition;
crop only tiny edges when required;
render at 1080 × 1920;
ensure important content is outside the UI-covered bottom region.

This is the ideal case.

Mode 2 — Static smart crop

The original video is horizontal, but the entire action stays in one region.

Example:

the pan remains in the center-right;
the person stirs without moving;
the relevant workspace stays fixed.

For a 1920 × 1080 landscape source, a strict 9:16 crop uses approximately a 608 × 1080 vertical slice.

A centered FFmpeg example:

ffmpeg -i source.mp4 \
  -vf "crop=608:1080:656:0,scale=1080:1920:flags=lanczos" \
  -c:v libx264 \
  -crf 20 \
  -preset medium \
  -c:a aac \
  -b:a 128k \
  -movflags +faststart \
  vertical.mp4

But the crop usually should not be centered automatically.

For cooking footage, the crop should prioritize:

food;
hands;
pan/bowl/tool;
visible transformation;
face only when it contributes to understanding.

A chef’s face can be partially outside the frame while their hands and pan remain visible. That is acceptable. The product is teaching a cooking action, not creating a personality edit.

FFmpeg’s crop filter supports selecting a rectangular output area and allows crop position expressions to be evaluated frame by frame.

Mode 3 — Dynamic smart crop

Use this when the important action moves horizontally.

Example:

the chef begins at a cutting board;
moves to the stove;
returns to a bowl;
the camera cuts between wide and close shots.

Store crop keyframes:

{
  "aspectRatio": "9:16",
  "keyframes": [
    {
      "time": 0.0,
      "centerX": 0.34,
      "centerY": 0.55,
      "zoom": 1.0
    },
    {
      "time": 4.2,
      "centerX": 0.58,
      "centerY": 0.53,
      "zoom": 1.05
    },
    {
      "time": 9.6,
      "centerX": 0.71,
      "centerY": 0.50,
      "zoom": 1.0
    }
  ]
}

Coordinates are normalized from 0 to 1.

The crop smoothly pans between those positions.

Movement rules

The crop should:

move slowly and deliberately;
never oscillate between face and hands;
avoid sudden pans unless the source itself cuts;
snap only at a genuine scene change;
keep the action safely above the step sheet;
maintain some context around the hands.

An automated crop that constantly chases the hands will look nauseating and amateur.

Initial production workflow

For the first few hundred clips:

AI proposes the focal area.
A reviewer adjusts the crop.
Reviewer adds two or three crop keyframes.
Glutt renders the vertical derivative.
Reviewer watches the completed 9:16 clip once.
Approve or fix.

Because clips are only around 8–20 seconds, this manual review is manageable and will produce much better results than attempting complete automation immediately.

Later, Apple Vision’s object tracking can follow an initially selected bounding region across video frames, but it still needs an initial object or region to track. It does not independently know that “the changing sauce texture” is the semantically important area.

Mode 4 — Contained fallback

Some footage cannot survive a 9:16 crop.

Examples:

two people standing far apart;
a wide counter with different actions on each side;
ingredients laid across the full frame;
the action repeatedly moves from extreme left to extreme right;
text overlays exist at both sides;
cropping would remove essential context.

Do not destroy the video to force it into 9:16.

Create a consistent 9:16 canvas containing:

a darkened or blurred version of the source filling the background;
the complete horizontal frame centered in front;
subtle separation between foreground and background;
no arbitrary stretching.

Visually:

┌───────────────────┐
│ blurred background │
│                   │
│ ┌───────────────┐ │
│ │ full 16:9 clip│ │
│ └───────────────┘ │
│                   │
└───────────────────┘

This is not as immersive as a smart crop, but it is better than removing critical food information.

Use it only when crop quality fails.

The correct vertical-processing pipeline
Downloaded rights-cleared source
        ↓
Identify useful 8–20 second segment
        ↓
Classify source aspect ratio
        ↓
Detect cooking focal region
        ↓
Choose verticalization mode
        ↓
Create crop track
        ↓
Human review
        ↓
Render 1080 × 1920 derivative
        ↓
Generate poster frame
        ↓
Upload HLS/MP4
        ↓
Display natively in Glutt
Clip-level metadata

Each clip should have:

interface CookingClipPresentation {
  clipId: string;

  sourceAspectRatio: number;
  outputAspectRatio: "9:16";

  presentationMode:
    | "nativeVertical"
    | "staticCrop"
    | "dynamicCrop"
    | "contained";

  cropTrack?: Array<{
    timeSeconds: number;
    centerX: number;
    centerY: number;
    zoom: number;
  }>;

  posterFrameSeconds: number;

  focusDescription: string;
  visualCue: string;

  defaultMuted: boolean;

  safeArea: {
    top: number;
    bottom: number;
  };

  reviewStatus:
    | "unreviewed"
    | "approved"
    | "rejected";
}
Important implementation detail

Render the vertical crop on the server.

Do not try to calculate a complicated dynamic crop every time the user plays an HLS clip.

Apple’s video-composition APIs can apply spatial transformations and cropping rectangles that vary over time for file-based media. However, assigning a video composition to AVPlayerItem is not supported for HTTP Live Streaming media.

Therefore:

Use AVPlayer to play an already-rendered 9:16 derivative.

That gives you:

predictable composition;
identical results on all devices;
easier preloading;
simpler playback;
no accidental crop changes;
consistent HLS delivery;
reliable poster frames.

Use .resizeAspectFill only after the source itself is already composed correctly for 9:16.

AI-assisted crop workflow

A practical crop system can work like this:

Step 1: Sample the clip

Extract approximately four frames per second.

Step 2: Ask the visual model

For every shot:

Identify the smallest region that contains the hands, food, active cookware, and visible result required to understand the cooking action. Ignore the presenter’s face unless it is essential.

Return:

{
  "time": 4.5,
  "importantRegion": {
    "x": 0.31,
    "y": 0.28,
    "width": 0.42,
    "height": 0.55
  }
}
Step 3: Convert regions into crop centers

Calculate a 9:16 window that contains as much of the important region as possible.

Step 4: Smooth the track

Remove tiny movements.

Only create a new crop keyframe when:

the important region moves significantly;
the source changes shot;
the current crop would lose the hands or food.
Step 5: Human correction

Show a vertical preview next to the original:

Original 16:9       Proposed 9:16

The reviewer drags the crop position directly over the source.

Step 6: Render

Generate the final output using the reviewed crop track.

Safe areas within vertical video

Although the derivative is 9:16, much of its bottom area is covered by the floating step sheet.

Tell the crop system:

Top interface safety zone: approximately 110 points
Bottom sheet coverage: approximately 250 points
Primary visible action zone: central 55–60% of the frame

The action should normally appear:

slightly above vertical center;
away from the Dynamic Island;
away from the step-sheet overlap;
with enough surrounding context to understand scale and movement.

When the action occurs behind the sheet, tapping the video should temporarily minimize the sheet and reveal the complete frame.

Screen-state matrix
State	Video	Step sheet	Polly dock	Transcript
Normal cooking	Poster/paused	Full	Say “Polly”	Hidden
Clip playing	Playing, prominent	Minimized	Playback status	Hidden
User speaking	Paused/dimmed	Full	Listening	User words optional
Polly thinking	Paused	Full	Thinking	Hidden
Polly speaking	Paused/dimmed	Full	Speaking	Temporary bubble
Camera check	Live camera	Shortened	Camera status	Hidden
Timer ending	Current visual	Full	Available	Timer alert
Checklist expanded	Video dimmed	Expanded	Available	Hidden

The central principle:

Video, Polly, camera, and checklist should take turns being dominant. They should not all demand attention simultaneously.

Designer acceptance criteria

The finished screen should pass these tests:

Two-second test

After looking at the screen for two seconds, someone should know:

what dish they are cooking;
which step they are on;
exactly what to do now;
how to speak to Polly.
Five-foot test

Place the phone on a counter and stand five feet away.

The user must still be able to read:

the action title;
the main instruction;
the active timer;
Polly’s current state.
Dirty-hands test

Every important action must be achievable through voice:

next;
repeat;
show me;
pause;
done;
start a timer;
look at this;
go back.
Video-value test

The clip must answer a visual question.

It should not exist merely because footage is available.

No-feed test

When viewed without context, the page must look like a cooking assistant—not TikTok, YouTube, FaceTime, or a livestream.

Ready-to-paste design prompt

Design a high-fidelity iOS cooking-session screen for an app called Glutt. The screen should feel like a premium, calm, video-first AI cooking assistant—not a social-media feed and not a phone call.

Use a full-screen 9:16 vertical cooking video as the visual canvas. The video should extend edge to edge behind the interface and show a chef warming ham in a pan. Add restrained dark gradients at the top and bottom for legibility.

At the top, place a minimal floating navigation layer: a circular down-chevron on the left, centered text reading “Eggs Benedict” with “Step 2 of 8” beneath it, and a circular ellipsis button on the right. Add a thin green overall-progress line below the navigation.

Over the lower third of the video, place a warm-charcoal floating step sheet with a 30-point corner radius and subtle visual separation. The sheet should display:

“STEP 2 · ACTION 1 OF 4” in small green uppercase text
“Warm the ham” in large warm-white type
“Place it in a dry pan over medium heat. Turn it once the edges begin to crisp.”
An inset green-accented “Mark action done” button
“UP NEXT · Make the hollandaise” in restrained secondary text

The video should contain only utility-focused controls: a small mute button, a centered play control when paused, a thin progress line, a label reading “See how crisp the edges should get · 14 sec,” and subtle source attribution. Do not include likes, comments, view counts, save icons, or a TikTok-style sidebar.

At the very bottom, create a floating Polly dock rather than phone-call controls. The dock should be a rounded dark capsule containing a small animated green waveform, the text “Say ‘Polly’ or tap to talk,” and a camera button. Do not include a red end-call button. “End cooking session” should live in the overflow menu.

Polly’s speech transcript should not be permanently visible. Show a temporary two- or three-line dark response bubble immediately above the Polly dock only while she is speaking.

Use a premium warm-dark palette: nearly black background, warm charcoal surfaces, soft ivory text, muted taupe secondary text, and one fresh herb-green accent. Use SF Pro-inspired typography, large readable instructions, minimal borders, 44-point minimum touch targets, subtle Liquid Glass only for floating controls, and an opaque readable step sheet.

The overall result should feel immersive, calm, modern, one-handed, and legible from across a kitchen counter. The current action must be obvious instantly. The video is the environment, the step sheet is the instruction, and Polly is the persistent assistant.