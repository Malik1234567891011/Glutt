# Chef feature: photography

Status 2026-07-30. Omar supplied eighteen images by hand. Twelve of the fifteen
dishes and all three portraits are now real photos, installed in
`Assets.xcassets` as `chef*` imagesets and wired through
`Glutt/Models/Chefs.swift`.

## What landed

Portraits, all three, square and cropped to the head:

| Chef | Asset | Size |
|---|---|---|
| Gordon Ramsay | `chefGordonRamsay` | 447 x 447 |
| Nick DiGiovanni | `chefNickDiGiovanni` | 500 x 500 |
| Joshua Weissman | `chefJoshuaWeissman` | 183 x 183, soft at 66pt |

Dishes. Nine of these came from YouTube thumbnails, so each was cropped down to
the food and away from the presenter's face and the title text. Crop boxes live
in the install script noted at the bottom.

| Dish | Asset | Size | Note |
|---|---|---|---|
| Beef Wellington | `chefBeefWellington` | 640 x 480 | soft |
| Pan Seared Salmon | `chefPanSearedSalmon` | 780 x 438 | soft |
| Shepherd's Pie | `chefShepherdsPie` | 1200 x 1200 | sharp |
| Spiced Lamb Flatbread | `chefSpicedLambFlatbread` | 447 x 447 | soft |
| Scrambled Eggs | `chefScrambledEggs` | 452 x 678 | soft |
| Truffle Mac and Cheese | `chefTruffleMac` | 460 x 224 | cropped off the face, soft |
| Crispy Chicken Fried Rice | `chefFriedRice` | 346 x 396 | softest of the set |
| Birria Tacos | `chefBirriaTacos` | 1140 x 389 | cropped off the title text, sharp |
| Smash Burgers | `chefSmashBurgers` | 717 x 562 | cropped off the face |
| Crispy Orange Chicken | `chefOrangeChicken` | 717 x 533 | cropped off the title text |
| Chicken Shawarma | `chefChickenShawarma` | 692 x 663 | cropped off the face |
| Burrito Bowl | `chefBurritoBowl` | 858 x 562 | cropped off the face |

## Still on stand-in art

Three supplied photos could not be used. Those dishes keep the app's existing
stock food art, which is higher resolution and reads as the right dish.

| Dish | Current asset | Why the supplied photo was skipped |
|---|---|---|
| Garlic Butter Steak Bites | `greenGoddessSteakPlate` | The photo is raw steak held up to camera, not the cooked dish |
| Chicken Katsu Sandwich | `beefWrapWithWedges` | 320 x 180, far too small for a card |
| Hot Honey Chicken | `hotHoneyChickenRice` | Blurry close up of one piece in a hand; the stand-in is a better and sharper match |

## If you want to sharpen it later

A card is about 370pt wide and renders at 3x, so anything under roughly 1100
pixels wide is visibly soft. Ten of the twelve are under that. They are legible
and on brand, just not crisp. Replacing any of them is a drop-in: same filename,
`design_handoff_top_chefs/dish-photos/`, and re-run the install script.

Portrait spec is square, face centred, 512 x 512 or larger. Joshua's is the one
worth redoing first, at 183 pixels it is the softest thing on the rail.

## Reproducing the processing

The install script lives in the session scratchpad
(`install_supplied.py`): it reads the raw files, applies the per photo crop
boxes, downscales without ever upscaling, and writes the imagesets. Worth
copying into the repo if this becomes a recurring job.

## Note on likeness

The three portraits are real photographs of real people, shown next to an
"Official" badge on recipes written for this app. That reads as an endorsement.
It is a right of publicity question rather than a copyright one, and no photo
licence settles it. Getting written permission from each chef's team is what
would make the badge true. Flagged, not blocking.
