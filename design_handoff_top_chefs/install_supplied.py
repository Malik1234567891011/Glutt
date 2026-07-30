#!/usr/bin/env python3
"""Install Omar's supplied chef photos into the Glutt asset catalog.

Dish shots from YouTube thumbnails get cropped down to the food, away from the
presenter's face and the title text. Crop boxes are fractions of (w, h).
"""
import os
from PIL import Image

SRC = "/Users/omarlahmimi/Downloads/glutt-images"
CATALOG = "/Users/omarlahmimi/Documents/Glutt/Glutt/Resources/Assets.xcassets"
MAX_DISH_W = 1200
MAX_PORTRAIT = 512

CONTENTS = """{
  "images" : [
    {
      "filename" : "%s.jpg",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

# asset -> (source file, crop box as fractions or None)
DISHES = {
    "chefBeefWellington":      ("beef-wellingston.jpeg", None),
    "chefPanSearedSalmon":     ("pan-seared-salmon.jpg", None),
    "chefShepherdsPie":        ("shepherds-pie.webp", None),
    "chefSpicedLambFlatbread": ("spiced-lamb-flatbread.jpeg", None),
    "chefScrambledEggs":       ("scrambled-eggs.jpeg", None),
    # Thumbnails: crop to the dish, away from face and title text.
    "chefTruffleMac":          ("truffle-mac.jpg", (0.33, 0.42, 1.0, 1.0)),
    "chefFriedRice":           ("fried-rice.jpg", (0.385, 0.45, 0.655, 1.0)),
    "chefBirriaTacos":         ("birria-tacos.jpg", (0.06, 0.46, 0.95, 1.0)),
    "chefSmashBurgers":        ("smash-burgers.jpg", (0.44, 0.22, 1.0, 1.0)),
    "chefOrangeChicken":       ("orange-chicken.jpg", (0.34, 0.26, 0.90, 1.0)),
    "chefChickenShawarma":     ("chicken-shawarma.jpg", (0.46, 0.08, 1.0, 1.0)),
    "chefBurritoBowl":         ("burrito-bowl.jpg", (0.33, 0.22, 1.0, 1.0)),
}

PORTRAITS = {
    "chefGordonRamsay":  ("gordon-ramsay-portrait.jpeg", None),
    "chefNickDiGiovanni": ("nickdigiovanni.png", None),
    # 183x275, face sits high: square off the top so it isn't a chest crop.
    "chefJoshuaWeissman": ("Joshua Weissman.jpeg", (0.0, 0.0, 1.0, 0.666)),
}


def load(name, box):
    im = Image.open(os.path.join(SRC, name)).convert("RGB")
    if box:
        w, h = im.size
        im = im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))
    return im


def write(asset, im, quality):
    folder = os.path.join(CATALOG, f"{asset}.imageset")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{asset}.jpg")
    im.save(path, "JPEG", quality=quality, optimize=True, progressive=True)
    open(os.path.join(folder, "Contents.json"), "w").write(CONTENTS % asset)
    return im.size, os.path.getsize(path) // 1024


def main():
    print("DISHES")
    for asset, (name, box) in DISHES.items():
        im = load(name, box)
        # Never upscale: iOS can stretch a small photo just as well, and the
        # bytes would be invented detail.
        if im.width > MAX_DISH_W:
            im = im.resize((MAX_DISH_W, round(im.height * MAX_DISH_W / im.width)), Image.LANCZOS)
        (w, h), kb = write(asset, im, 82)
        soft = "  << soft, wants a 1200px+ source" if w < 1000 else ""
        print(f"  {asset:26s} {w:4d}x{h:<4d} {kb:4d}KB{soft}")

    print("PORTRAITS")
    for asset, (name, box) in PORTRAITS.items():
        im = load(name, box)
        side = min(im.size)                      # square, centred on the head
        left = (im.width - side) // 2
        top = min((im.height - side) // 2, int(im.height * 0.12))
        im = im.crop((left, top, left + side, top + side))
        if im.width > MAX_PORTRAIT:
            im = im.resize((MAX_PORTRAIT, MAX_PORTRAIT), Image.LANCZOS)
        (w, h), kb = write(asset, im, 85)
        soft = "  << soft for a 66pt circle" if w < 200 else ""
        print(f"  {asset:26s} {w:4d}x{h:<4d} {kb:4d}KB{soft}")


if __name__ == "__main__":
    main()
