# Glutt Onboarding → Figma build notes

File: https://www.figma.com/design/qYCBodrPLql8CrSNaafE9H/Untitled
fileKey: qYCBodrPLql8CrSNaafE9H

## Pages
- "Onboarding Flow" = 0:1
- "Components" = 4:2

## Variable collections
- Glutt Colors: VariableCollectionId:3:2, mode 3:0
  - Background/cream 3:3 #FAF3E7 · Surface/card 3:4 #FFFDF7 · Surface/tile 3:5 #F4EDDC · Surface/alt 3:6 #F1E9D6
  - Green/primary 3:7 #2E5339 · Green/hover 3:8 · Green/tint 3:9 #EAF1E7 · Green/accent 3:10 · Green/activeTab 3:11
  - Tomato/primary 3:12 #D9483B · Tomato/bright 3:13 #E1523D · Tomato/tint 3:14
  - Amber/primary 3:15 · Amber/tint 3:16
  - Text/heading 3:17 #241E19 · Text/base 3:18 #2A2420 · Text/muted 3:19 #6E6456 · Text/faint 3:20 #9A9082
  - Text/onColor 3:21 #FBF5E9 · Text/onColorAlt 3:22 · Border/default 3:23 · Dark/bar 3:24 · Dark/inactive 3:25
- Glutt Layout: VariableCollectionId:3:26, mode 3:1 (Space/xs..xl 3:27–3:31; Radius/* 3:32–3:41)

## Image hashes (uploaded; placement frames 5:2–5:16 to delete later)
- hotHoneyChickenRice 29b48024214562147b2b0bf9a340b617408e9abc (1122x1402)
- greenGoddessSteakPlate 03eaac336f33be83600a252428249dcddee5e7a3 (1537x1023)
- chickenRiceBowl 4f5b2c8541d63c6e33510dcfb029a972a5e0bec4 (3200x1800)
- greekYogurtBowl 34a5bca908b58dd5ac494e166336aa6eda471cc0 (667x1000)
- garlicButterSteakPotatoBowl 3f2942e1ab653df417db667df41b2c0535fb1858 (1254x1254)
- koftaFlatbreadWrap b8af004d6f6a3d2099ca68e508f4f417d8bf10ad (941x1672)
- lemonDillSalmonBowl 85adf637a9eaea99758834708f2252098d9ecd7b (1024x1536)
- beefWrapWithWedges d1b99641ecb126180adb7b7b0321c59858576c67 (1448x1086)
- koreanBeefMealPrep 3436aff3f44bf3047e37aa706d56034bc11ffa7c (1092x1440)
- pestoGnocchiMealPrep 10b70a8a9d6ed08f4786fd5a0f6216553cfb1c55 (1096x1436)
- steakFajitaSalad cf3ff24c4e44b84f9884833cf2f2c54dd47a1d6a (1097x1434)
- tutorialHotHoney f078960c57846bb1b17f127572caea66b0d58437 (1200x1500)
- glutt-intro poster 192fa7573100b53f3e78e3f7f9a157235fcf0e33 (720x1280)
- glutt-features poster cc11513e944dfcb9df7702a5abf9cc011d76e23c (720x1280)
- chef-cooking poster 30d0ecfb4559fad1fffaa27d01e4064d76c97592 (540x960)

## Canvas conventions
- Frame: 390×844, status zone 54px (design_top = code_top + 54); home indicator zone 34px (footer bottom = code_bottom + 34)
- Screens: 0 Welcome, 1 IntroVideo, 2 QuestionsIntro, 3 Goals, 4 Rules, 5 FourWeeks, 6 PollyHero, 7 AIFeatures, 8 NotifsSoftAsk, 9 Tutorial (phases 0–4) = 14 frames
- Progress bar screens 1–8: 8pt capsule, h-inset 24, top 6 below status zone; track #2A2420@9%, fill #3E7A50; progress = screen/9
- CTA: capsule 60pt tall, #2E5339, Bricolage 19/600 ls0.2 #FBF5E9, shadow rgba(42,36,32,0.14) r12 y10
- NO dashes in copy. Neutral warm shadows only. Solid pills.

## Text styles (created, names): Bricolage/Display 34, H1 29/28/27/26/25, H1 Polly 28, Wordmark 22, Title 25/22/18, Label 15/14.5, CTA 19, Badge 13.5/14; Nunito/Subhead 14.5, Row 15.5, Link 15, Body 13.5, Proof 13.5, Body 12.5, Eyebrow 11, Timestamp 11, Pill 12, Meta 13, Badge 12.5, Coach 13, Badge Sub 10.5

## Component IDs (Components page 4:2)
- CTA Button set 9:8 — Primary variant 9:6, Disabled 9:7, prop Label (TEXT)
- Text Link 9:10 — prop Label
- Goal Row set 9:21 — Selected=No 9:19, Selected=Yes 9:20, prop Label
- Rule Tile 10:10 — props Label, Icon (INSTANCE_SWAP); default gradient #7FB56A→#3F7A3A; override instance fills + shadow per tile
- Four Weeks Card 11:14 — props Title/Body/Icon; children "Icon Square" (gradient+shadow override), "Glow" (radial override)
- Notification Card 11:25 — props Title/Body/Time
- Status Bar 11:43 (390×54, dark #241E19)
- Icons: check 7:4, eco 7:7, spa 7:10, set-meal 7:13, grain 7:16, icecream 7:19, no-meals 7:22, mosque 7:25, synagogue 7:28, egg 7:31, fire-fill 7:34, kitchen 7:37, skillet 7:40, favorite 7:43, mode-comment 7:46, send 7:49, bookmark 7:52, search 7:55, add-circle 8:4, ios-share 8:7, link 8:10, chat-fill 8:13, wifi-tethering 8:16, chat-bubble 8:19, mail 8:22, content-copy 8:25, chrome-reader 8:28, check-circle 8:31, schedule 8:34, fire-outline 8:37, restaurant 8:40, laurel 8:50

## Screens built (Onboarding Flow page 0:1, x = index*470)
- 00 Welcome = 13:2 ✓ (masonry, scrim, wordmark/H1/social pill/Start)
- 01 Intro Video = 12:6 ✓ (H1 fixed h68, video y194 h524)
- 02 Questions Intro = 12:31 ✓ (H1 3 lines h105, centered)

## BLOCKED 2026-07-26: Figma MCP rate limit (Starter plan, ~6 tool calls/month; use_figma NOT exempt)
Remaining when access returns:
1. Run scripts screen-03-goals.js, screen-05-fourweeks.js, screen-08-notifications.js (saved in this dir, ready verbatim)
2. Build 04 Food Rules (x1880, progress 152; 3×3 Rule Tile grid y≈261, x from 26, tiles 105×115.5 gap 12; instances w/ gradient+shadow+icon+label overrides per README table; show Gluten-free selected: badge+double ring siblings, tile offset y-3)
3. Build 06 Polly Hero (x2820: chef-cooking poster 30d0ecfb full-bleed, scrim stops 0/0.16/0.44/0.60/0.70/1 cream, progress 228, rating badge w/ laurel 8:50 + flipped copy, H1 Polly 28 maxW330, mic pill green, CTA x28 w334 y742)
4. Build 07 AI Features (x3290: like 01, H1 27 "AI shows up right where you cook" + subhead, glutt-features poster cc11513e, fade 22%, progress 266)
5. Build 09-13 Tutorial phases (x4230..6110): shell = H1 25 + subhead y80/x22, MiniPhone 240×510 r46 #0D0D0F centered y≈156, notch 82×23; phase content per exploration map scaled 0.6154; footers: dots+Skip (0-2), none (3), CTA (4)
6. Validate: screenshot each frame, check fonts/clipping/overlap
7. Annotate: label text above each frame; section wrapper "Glutt Onboarding v1 (shipped)"
8. Cleanup: DELETE parked image frames 5:2–5:16 (at y=3000) only after all image fills applied

## Gotchas learned
- TEXT: resize(w,h) FIRST, then textAutoResize="HEIGHT" (reverse order collapses box)
- Variants overlap inside combineAsVariants sets — spread children manually
- Instance property keys: Object.keys(inst.componentProperties).find(k=>k.startsWith("Label"))
