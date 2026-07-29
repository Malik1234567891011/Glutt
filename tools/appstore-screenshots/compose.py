#!/usr/bin/env python3
"""Composite a Glutt App Store panel: real screenshot + locked mascot + real Bricolage type."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868  # iPhone 6.9" App Store size
FONTS = "/Users/omarlahmimi/Documents/Glutt/Glutt/Resources/Fonts"
BRICOLAGE = os.path.join(FONTS, "BricolageGrotesque-Variable.ttf")

C = {
    "cream":    (250, 243, 231),
    "white":    (255, 253, 247),
    "green":    (46, 83, 57),
    "mint":     (143, 227, 163),
    "honey":    (252, 240, 214),
    "amber":    (194, 140, 33),
    "tomato":   (217, 72, 59),
    "peach":    (247, 226, 212),
    "ink":      (36, 30, 25),
    "greentint":(234, 241, 231),
    "accentblob":(56, 100, 69),
}


def font(size, weight=800, width=100, opsz=None):
    f = ImageFont.truetype(BRICOLAGE, size)
    f.set_variation_by_axes([min(opsz or size, 96), weight, width])
    return f


# ---------- keying ----------

def key_magenta(im, tol=110):
    """Remove a flat magenta chroma background."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r > 120 and b > 120 and g < 110 and abs(r - b) < 90:
                mag = (r + b) / 2 - g
                if mag > tol:
                    px[x, y] = (r, g, b, 0)
                elif mag > tol * 0.45:
                    px[x, y] = (r, g, b, int(255 * (1 - (mag - tol * 0.45) / (tol * 0.55))))
    # de-fringe: pull remaining magenta cast toward neutral on semi-transparent edges
    px = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if 0 < a < 255 and (r + b) / 2 - g > 30:
                m = int(((r + b) / 2 - g) * 0.7)
                px[x, y] = (max(0, r - m), g, max(0, b - m), a)
    return im


def key_white(im):
    """Flood-fill a flat white background to transparent, preserving interior near-whites."""
    im = im.convert("RGBA")
    w, h = im.size
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        try:
            ImageDraw.floodfill(im, corner, (255, 255, 255, 0), thresh=42)
        except Exception:
            pass
    return im


def autocrop(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def fit(im, box_w=None, box_h=None):
    w, h = im.size
    s = min([v for v in [box_w / w if box_w else None, box_h / h if box_h else None] if v])
    return im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)


# ---------- drawing helpers ----------

def shadow(layer, size, offset=(0, 18), blur=26, opacity=70):
    """Soft drop shadow from an RGBA layer's alpha."""
    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    a = layer.split()[3].point(lambda v: int(v * opacity / 255))
    black = Image.new("RGBA", layer.size, (60, 45, 35, 255))
    black.putalpha(a)
    sh.paste(black, offset, black)
    return sh.filter(ImageFilter.GaussianBlur(blur))


def blob(size, color, seed=0.0):
    """Smooth organic amoeba silhouette."""
    bw, bh = size
    layer = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = bw / 2, bh / 2
    pts = []
    for i in range(240):
        t = i / 240 * 2 * math.pi
        r = 1 + 0.11 * math.sin(3 * t + seed) + 0.07 * math.sin(5 * t + 1.7 + seed) \
              + 0.045 * math.sin(7 * t + 3.1 + seed)
        pts.append((cx + math.cos(t) * cx * 0.94 * r, cy + math.sin(t) * cy * 0.94 * r))
    d.polygon(pts, fill=color + (255,))
    return layer.filter(ImageFilter.GaussianBlur(2))


def text_w(d, s, f, track=0):
    return sum(d.textlength(ch, font=f) for ch in s) + track * max(0, len(s) - 1)


def draw_tracked(d, xy, s, f, fill, track=0, anchor_center=False):
    x, y = xy
    if anchor_center:
        x -= text_w(d, s, f, track) / 2
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + track
    return x


def pill(text, fsize=52, pad=(40, 22), bg="white", fg="ink", weight=700):
    f = font(fsize, weight=weight, width=100)
    tmp = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    tw = tmp.textlength(text, font=f)
    asc, desc = f.getmetrics()
    pw, ph = int(tw + pad[0] * 2), int(asc + desc + pad[1] * 2)
    layer = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([0, 0, pw - 1, ph - 1], radius=ph // 2, fill=C[bg] + (255,))
    d.text((pad[0], pad[1]), text, font=f, fill=C[fg] + (255,))
    return layer


def nutrition_card(pairs, width, num_size=118, lab_size=40, tilt=0.0):
    """Wide warm-white card: a row of big numbers over small amber caps labels."""
    fn, fl = font(num_size, weight=800, width=92), font(lab_size, weight=700, width=100)
    ph = int(num_size * 1.05 + lab_size * 1.5 + 96)
    layer = Image.new("RGBA", (width, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([0, 0, width - 1, ph - 1], radius=int(ph * 0.30), fill=C["white"] + (255,))
    col = width / len(pairs)
    for i, (num, lab) in enumerate(pairs):
        cx = col * (i + 0.5)
        draw_tracked(d, (cx, 44), num, fn, C["ink"] + (255,), track=-2, anchor_center=True)
        draw_tracked(d, (cx, 44 + int(num_size * 1.12)), lab, fl, C["amber"] + (255,),
                     track=3, anchor_center=True)
    if tilt:
        layer = layer.rotate(tilt, resample=Image.BICUBIC, expand=True)
    return layer


def phone(shot_path, target_w, crop_status=0.062, island=True):
    """Bezelled phone with the real screenshot inside."""
    shot = Image.open(shot_path).convert("RGB")
    if crop_status:
        shot = shot.crop((0, int(shot.height * crop_status), shot.width, shot.height))
    bezel = max(10, int(target_w * 0.017))
    screen_w = target_w - bezel * 2
    scale = screen_w / shot.width
    screen_h = int(shot.height * scale)
    screen = shot.resize((screen_w, screen_h), Image.LANCZOS)

    r_out = int(target_w * 0.115)
    r_in = r_out - int(bezel * 0.75)
    ph = screen_h + bezel * 2
    body = Image.new("RGBA", (target_w, ph), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([0, 0, target_w - 1, ph - 1], radius=r_out, fill=C["ink"] + (255,))

    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen_w - 1, screen_h - 1], radius=r_in, fill=255)
    body.paste(screen, (bezel, bezel), mask)

    if island:
        iw, ih = int(target_w * 0.30), int(target_w * 0.085)
        ix, iy = (target_w - iw) // 2, bezel + int(target_w * 0.018)
        ImageDraw.Draw(body).rounded_rectangle([ix, iy, ix + iw, iy + ih],
                                              radius=ih // 2, fill=C["ink"] + (255,))
    return body


# ---------- panel builder ----------

def build(cfg, out):
    canvas = Image.new("RGBA", (W, H), C[cfg["bg"]] + (255,))

    # blob
    if cfg.get("blob"):
        bcol, bsize, bpos, seed = cfg["blob"]
        b = blob((int(W * bsize[0]), int(H * bsize[1])), C[bcol], seed)
        canvas.alpha_composite(b, (int(W * bpos[0] - b.width / 2), int(H * bpos[1] - b.height / 2)))

    # phone
    ph = phone(cfg["shot"], int(W * cfg.get("phone_w", 0.62)),
               crop_status=cfg.get("crop_status", 0.062), island=cfg.get("island", True))
    px = int(W * cfg.get("phone_x", 0.5) - ph.width / 2)
    py = int(H * cfg["phone_y"])
    canvas.alpha_composite(shadow(ph, (W, H), offset=(px, py + 26), blur=40, opacity=60))
    canvas.alpha_composite(ph, (px, py))

    # AI-composed scene band (hill + mascot + props), drawn IN FRONT of the phone
    if cfg.get("scene"):
        sc = key_magenta(Image.open(cfg["scene"]["file"]))
        sc = sc.resize((W, int(sc.height * W / sc.width)), Image.LANCZOS)
        by = int(H * cfg["scene"]["bottom"])
        # continue the hill colour from the band's bottom edge down to the canvas edge
        if by < H:
            bottom_row = [sc.getpixel((x, sc.height - 2)) for x in range(0, W, 7)]
            opaque = [p[:3] for p in bottom_row if p[3] > 250]
            if opaque:
                med = tuple(sorted(c[i] for c in opaque)[len(opaque) // 2] for i in range(3))
                fill = Image.new("RGBA", (W, H - by + 4), med + (255,))
                canvas.alpha_composite(fill, (0, by - 2))
        canvas.alpha_composite(sc, (0, by - sc.height))

    # food props
    for prop in cfg.get("props", []):
        im = autocrop(key_magenta(Image.open(prop["file"])))
        im = fit(im, box_w=int(W * prop["w"]))
        x, y = int(W * prop["x"] - im.width / 2), int(H * prop["y"] - im.height / 2)
        canvas.alpha_composite(shadow(im, (W, H), offset=(x + 6, y + 22), blur=24, opacity=78))
        canvas.alpha_composite(im, (x, y))
        if prop.get("label"):
            lp = pill(prop["label"], fsize=prop.get("label_size", 52))
            lx = int(W * prop.get("label_x", prop["x"]) - lp.width / 2)
            ly = int(H * prop.get("label_y", prop["y"] - 0.035) - lp.height / 2)
            canvas.alpha_composite(shadow(lp, (W, H), offset=(lx, ly + 10), blur=16, opacity=55))
            canvas.alpha_composite(lp, (lx, ly))

    # mascot
    if cfg.get("mascot"):
        m = autocrop(key_white(Image.open(cfg["mascot"])))
        m = fit(m, box_h=int(H * cfg.get("mascot_h", 0.135)))
        mx = int(W * cfg["mascot_x"] - m.width / 2)
        my = int(H * cfg["mascot_y"] - m.height)
        canvas.alpha_composite(shadow(m, (W, H), offset=(mx, my + 14), blur=20, opacity=48))
        canvas.alpha_composite(m, (mx, my))

    # headline
    d = ImageDraw.Draw(canvas)
    y = int(H * cfg["head_y"])
    for line in cfg["head"]:
        txt, size, wt, wd, col, track = (line + (None,) * 6)[:6]
        f = font(size, weight=wt or 800, width=wd or 100)
        draw_tracked(d, (W * 0.5, y), txt, f, C[col or "ink"] + (255,),
                     track=track or 0, anchor_center=True)
        y += int(size * cfg.get("leading", 0.86))

    # magnified nutrition card
    if cfg.get("card"):
        cc = cfg["card"]
        nc = nutrition_card(cc["pairs"], int(W * cc.get("w", 0.80)), tilt=cc.get("tilt", 0.0))
        cx, cy = int(W * cc["x"] - nc.width / 2), int(H * cc["y"] - nc.height / 2)
        canvas.alpha_composite(shadow(nc, (W, H), offset=(cx, cy + 22), blur=30, opacity=80))
        canvas.alpha_composite(nc, (cx, cy))

    # extra pills / bubbles
    for b in cfg.get("bubbles", []):
        lp = pill(b["text"], fsize=b.get("size", 56), bg=b.get("bg", "white"), fg=b.get("fg", "ink"))
        lx, ly = int(W * b["x"] - lp.width / 2), int(H * b["y"] - lp.height / 2)
        canvas.alpha_composite(shadow(lp, (W, H), offset=(lx, ly + 12), blur=18, opacity=55))
        canvas.alpha_composite(lp, (lx, ly))

    canvas.convert("RGB").save(out, quality=97)
    print("OK", out, canvas.size)


if __name__ == "__main__":
    import panels
    name = sys.argv[1]
    build(panels.PANELS[name], sys.argv[2])
