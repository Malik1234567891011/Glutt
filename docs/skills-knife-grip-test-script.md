# Hold a Chef's Knife: what to try, and what should happen

The logic is covered by `SkillVisualCoachingTests` and needs no hardware. This
file is for everything that needs a real hand, a real knife and the glasses,
which is the half that decides whether the feature is any good.

Run it wearing the glasses, in the kitchen, with the knives you actually own.
Skills → Knife Skills → Hold a Chef's Knife → **Learn it with Chef**.

There is no button and no countdown. Say "Chef" to wake her, then just ask:
"does this look right?", "like this?", "is that better?". She reads the last few
seconds of the stream, so she is looking before she finishes answering you.

The bar for every row: **a false correction is worse than a missed one.** If she
tells you something is wrong that is not wrong, that is a failure even if the
rest of the lesson was perfect.

## Grips that should pass

| Do this | Expected |
|---|---|
| Textbook pinch, thumb and curled index on the blade faces at the heel | Pass. She should name what she saw, not just say "correct" |
| Pinch a centimetre further onto the blade | Pass, no correction |
| Pinch right against the bolster | Pass, no correction |
| Same, left handed | Pass. She should never tell a left handed cook to swap hands |
| Santoku | Pass |
| Gyuto, no bolster | Pass, and she must not ask for a bolster that is not there |
| Chef's knife with a full bolster | Pass |
| Small hands on a 10 inch knife | Pass. Judged on relationships, not distances |

A pass on a grip that is not the reference should say so warmly and leave it
alone. If she tries to move you onto the textbook version, that is the pose
classifier failure mode and it is a bug.

## Grips that should be corrected, one thing at a time

| Do this | Expected correction |
|---|---|
| Whole hand on the handle, nothing on the blade | "You are holding it by the handle." Move forward to the pinch |
| Index finger extended along the spine | "Curl it down onto the side of the blade" |
| Thumb on the spine | Bring the thumb onto the flat face |
| Two fingers floating off the handle | Wrap the bottom three |
| Handle grip AND index on spine at once | **One** of them, not both. The handle grip is ranked higher, so expect that one |

After a correction, fix it and check again. The second result should refer back:
noticing that the thumb never moved and only the finger changed is the moment
this feels like a person.

## Views she should refuse to judge

| Do this | Expected |
|---|---|
| Hold the knife but look away | "I cannot see" and a reframing ask, never a criticism |
| Cover the thumb with the other hand | Names the thumb specifically |
| Hold it in shadow / low light | Cannot see, not a fault |
| Move the knife around while asking | Cannot see, or a safety stop if it is waved |
| Hold it below the frame | Cannot see |
| Fail twice in a row | Stops asking, offers the way out. **Never a third identical request** |

## Wrong equipment

| Do this | Expected |
|---|---|
| Paring knife | Named as a paring knife, lesson not attempted |
| Bread knife | Same |
| Cleaver | Same |
| Butter knife | Same, or cannot assess. Never a grip correction |
| No knife at all | Cannot see, or asks what you are holding. Never a grip verdict |
| Say "it is a chef's knife" after she doubts it | She takes your word and checks again |

## Safety

Do this one carefully and deliberately, once.

| Do this | Expected |
|---|---|
| Rest a finger against the edge, knife flat on the board | Immediate stop, put it down, one correction, no cheerful lesson narration over it |

If she does **not** catch a finger clearly on the edge, note it. If she claims a
safety problem that is not there, that is worse and should be reported first.

## Things she must never say

- That your technique is "safe" or "perfect". A photograph cannot certify that
- Anything about how hard you are squeezing. She has to ask
- A criticism of a finger she has just said she cannot see
- Two corrections in one breath

## Conversation, mid lesson

Interrupt her at any point. She should answer, briefly, and offer to carry on.

- "Why am I touching the blade?"
- "This feels weird."
- "Can I just hold the handle?"
- "Mine does not have that metal bump."
- "I am left handed."
- "This hurts." → she should ask whether it is unfamiliar or painful, and if
  painful, stop asking for it
- "Should I squeeze hard?"
- "Is this the same for a santoku?"
- "I saw a chef put their finger on top." → the index-on-spine grip is real, just
  not what we are teaching here. She should say that, not that they were wrong
- "Can we skip this?"

## Progress

After a pass:

- The lesson screen shows the attempt history, including the failed and unseen
  attempts, with the note for each
- Practice time is the sum of the holds
- The skill reads as mastered, and XP is paid exactly once no matter how many
  times you check afterwards
- An attempt she could not see must **not** promote anything

## Timing

Question to verdict should be about six seconds, and most of that should be
covered by her talking. The log lines that show it working:

    skill: looking already, before she answered
    skill: used the early look (5.5s old)

If the first line is missing, the phrasing did not match and she waited for the
tool call before starting, which costs three or four seconds. Worth reporting
with what you said.

## Known limits, do not report as bugs

- No glasses means no check. The lesson still teaches by voice and says plainly
  that it cannot look
- Frame choice is by encoded size, which is a proxy for sharpness, not a
  Laplacian. It only has to drop the worse of two near identical frames
- She looks at the last few seconds of the stream rather than taking a photo on
  demand, so a grip you changed in the last second may not be the one she saw.
  Ask again and she will read the newer frames
- Grip pressure, comfort and knife sharpness are not assessable and are asked
  about instead
