from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
BACKGROUNDS = ROOT / "backgrounds"
FINAL = ROOT / "final"
PREVIEW = ROOT / "preview"

W, H = 1440, 900

FONT_UI = "/System/Library/Fonts/SFNS.ttf"
FONT_UI_BOLD = "/System/Library/Fonts/SFNS.ttf"
FONT_DISPLAY = "/System/Library/Fonts/NewYork.ttf"
FONT_DISPLAY_ITALIC = "/System/Library/Fonts/NewYorkItalic.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


UI_11 = font(FONT_UI, 11)
UI_12 = font(FONT_UI, 12)
UI_13 = font(FONT_UI, 13)
UI_14 = font(FONT_UI, 14)
UI_16 = font(FONT_UI, 16)
UI_18 = font(FONT_UI, 18)
UI_22 = font(FONT_UI_BOLD, 22)
UI_28 = font(FONT_UI_BOLD, 28)
DISPLAY_58 = font(FONT_DISPLAY, 58)
DISPLAY_66 = font(FONT_DISPLAY, 66)
DISPLAY_78 = font(FONT_DISPLAY, 78)
DISPLAY_ITALIC_34 = font(FONT_DISPLAY_ITALIC, 34)


def fit_bg(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGB")
    return ImageOps.fit(img, (W, H), method=Image.Resampling.LANCZOS, centering=(0.5, 0.5)).convert("RGBA")


def layer(size=(W, H)) -> Image.Image:
    return Image.new("RGBA", size, (0, 0, 0, 0))


def composite(base: Image.Image, overlay: Image.Image) -> Image.Image:
    return Image.alpha_composite(base, overlay)


def draw_linear_gradient(draw: ImageDraw.ImageDraw, box, top, bottom):
    x0, y0, x1, y1 = box
    height = max(1, y1 - y0)
    for i in range(height):
        t = i / height
        color = tuple(int(top[c] * (1 - t) + bottom[c] * t) for c in range(4))
        draw.line([(x0, y0 + i), (x1, y0 + i)], fill=color)


def draw_radial_glow(img: Image.Image, center, radius, color):
    glow = layer(img.size)
    d = ImageDraw.Draw(glow)
    cx, cy = center
    steps = 64
    for i in range(steps, 0, -1):
        t = i / steps
        alpha = int(color[3] * (t**2))
        r = int(radius * t)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color[:3] + (alpha,))
    img.alpha_composite(glow)


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def wrap_text(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if text_size(draw, candidate, fnt)[0] <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_text_block(draw: ImageDraw.ImageDraw, xy, title, subtitle, accent=None):
    x, y = xy
    shadow = (19, 9, 42, 190)
    draw.text((x + 2, y + 3), title, font=DISPLAY_78, fill=shadow)
    draw.text((x, y), title, font=DISPLAY_78, fill=(236, 225, 255, 255))

    subtitle_y = y + 98
    if accent and accent in subtitle:
        before, after = subtitle.split(accent, 1)
        draw.text((x, subtitle_y), before, font=UI_28, fill=(206, 192, 238, 230))
        bx = x + text_size(draw, before, UI_28)[0]
        draw.text((bx, subtitle_y), accent, font=UI_28, fill=(176, 122, 255, 255))
        ax = bx + text_size(draw, accent, UI_28)[0]
        draw.text((ax, subtitle_y), after, font=UI_28, fill=(206, 192, 238, 230))
    else:
        lines = wrap_text(draw, subtitle, UI_28, 480)
        for i, line in enumerate(lines[:3]):
            draw.text((x, subtitle_y + i * 36), line, font=UI_28, fill=(206, 192, 238, 230))


def draw_menu_bar(base: Image.Image, selected_x=1160):
    bar = layer()
    d = ImageDraw.Draw(bar)
    draw_linear_gradient(d, (0, 0, W, 48), (16, 14, 25, 245), (20, 15, 34, 210))
    d.line((0, 47, W, 47), fill=(255, 255, 255, 26), width=1)

    icon_path = Path("/Users/castao/Desktop/Tappy/docs/assets/tappy-icon.png")
    icon = Image.open(icon_path).convert("RGBA").resize((22, 22), Image.Resampling.LANCZOS)
    d.text((26, 14), "Finder", font=UI_13, fill=(247, 243, 255, 245))
    x = 86
    for label in ["File", "Edit", "View", "Go", "Window", "Help"]:
        d.text((x, 14), label, font=UI_12, fill=(226, 219, 244, 235))
        x += text_size(d, label, UI_12)[0] + 20

    # Right side status area.
    for i, item in enumerate(["Wi-Fi", "100%", "Thu 9:41 AM"]):
        tx = W - 286 + i * 78
        d.text((tx, 14), item, font=UI_12, fill=(226, 219, 244, 230))

    # Tappy status item highlighted in the menu bar.
    d.rounded_rectangle((selected_x - 13, 8, selected_x + 33, 40), radius=10, fill=(122, 80, 255, 86), outline=(198, 171, 255, 85), width=1)
    bar.alpha_composite(icon, (selected_x, 13))

    base.alpha_composite(bar)
    return selected_x + 11


def draw_check(draw: ImageDraw.ImageDraw, x: int, y: int, color):
    draw.line([(x, y + 6), (x + 5, y + 11), (x + 15, y)], fill=color, width=3, joint="curve")


def draw_pack_icon(draw: ImageDraw.ImageDraw, x: int, y: int, kind: str, color):
    if kind == "plastic":
        for dx, dy in [(0, 7), (8, 2), (16, 7), (8, 12), (0, 17), (16, 17)]:
            draw.ellipse((x + dx, y + dy, x + dx + 8, y + dy + 8), fill=color)
    elif kind == "organic":
        draw.ellipse((x + 2, y + 8, x + 24, y + 24), fill=color)
        draw.polygon([(x + 22, y + 7), (x + 32, y + 13), (x + 22, y + 17)], fill=color)
        draw.line((x + 9, y + 19, x + 27, y + 11), fill=(27, 40, 24, 170), width=2)
    elif kind == "pop":
        for dx, dy, r in [(0, 8, 8), (14, 0, 10), (22, 16, 7), (5, 23, 6)]:
            draw.ellipse((x + dx, y + dy, x + dx + r * 2, y + dy + r * 2), fill=color)
    elif kind == "ticks":
        draw.ellipse((x + 2, y + 5, x + 28, y + 31), outline=color, width=3)
        draw.line((x + 15, y + 18, x + 15, y + 9), fill=color, width=3)
        draw.line((x + 15, y + 18, x + 23, y + 22), fill=color, width=3)
        draw.rectangle((x + 11, y + 0, x + 19, y + 6), fill=color)
    elif kind == "bright":
        draw.polygon([(x + 16, y), (x + 20, y + 12), (x + 32, y + 16), (x + 20, y + 20), (x + 16, y + 32), (x + 12, y + 20), (x, y + 16), (x + 12, y + 12)], fill=color)
    elif kind == "wood":
        draw.rounded_rectangle((x + 3, y + 6, x + 28, y + 28), radius=5, fill=color)
        draw.line((x + 8, y + 13, x + 23, y + 13), fill=(73, 42, 29, 100), width=2)
        draw.line((x + 9, y + 20, x + 25, y + 20), fill=(73, 42, 29, 90), width=2)


PACKS = [
    ("Plastic Tapping", "Light feedback cues", "plastic", (125, 182, 255, 255)),
    ("Organic Taps", "Natural feedback cues", "organic", (98, 210, 116, 255)),
    ("Soft Pop", "Gentle feedback cues", "pop", (95, 224, 224, 255)),
    ("Mechanical Ticks", "Precise feedback cues", "ticks", (184, 199, 230, 255)),
    ("Bright Cues", "High-clarity feedback cues", "bright", (255, 213, 86, 255)),
    ("Wood Brush", "Dry tactile feedback cues", "wood", (218, 158, 98, 255)),
]


def draw_popover(base: Image.Image, anchor_x: int, active_pack: str, mode: str = "active"):
    w, h = 372, 612
    x = min(W - w - 54, max(720, anchor_x - w + 30))
    y = 64

    shadow = layer()
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x + 8, y + 12, x + w + 8, y + h + 12), radius=20, fill=(0, 0, 0, 125))
    shadow = shadow.filter(ImageFilter.GaussianBlur(20))
    base.alpha_composite(shadow)

    panel = layer()
    d = ImageDraw.Draw(panel)
    d.polygon([(anchor_x - 12, y + 2), (anchor_x + 12, y + 2), (anchor_x, y - 12)], fill=(19, 17, 31, 248))
    d.rounded_rectangle((x, y, x + w, y + h), radius=20, fill=(18, 16, 31, 248), outline=(89, 77, 124, 150), width=1)

    d.text((x + 18, y + 18), "Tappy", font=UI_22, fill=(250, 247, 255, 255))
    d.text((x + 18, y + 44), "Auditory typing feedback", font=UI_12, fill=(169, 158, 194, 255))
    dot = (103, 220, 124, 255) if mode == "active" else (244, 170, 64, 255)
    label = "Active" if mode == "active" else "Setup needed"
    d.ellipse((x + w - 88, y + 28, x + w - 78, y + 38), fill=dot)
    d.text((x + w - 70, y + 24), label, font=UI_12, fill=(187, 178, 205, 255))
    d.line((x, y + 72, x + w, y + 72), fill=(255, 255, 255, 20))

    status_text = "Listening across apps. Feedback cues play locally and never record typed text."
    d.rounded_rectangle((x + 14, y + 86, x + w - 14, y + 130), radius=10, fill=(255, 255, 255, 12))
    lines = wrap_text(d, status_text, UI_12, w - 48)
    for i, line in enumerate(lines[:2]):
        d.text((x + 24, y + 94 + i * 15), line, font=UI_12, fill=(178, 168, 198, 240))

    row_y = y + 144
    for name, tagline, kind, color in PACKS:
        active = name == active_pack
        if active:
            d.rounded_rectangle((x + 10, row_y - 2, x + w - 10, row_y + 48), radius=10, fill=(125, 85, 255, 36))
        draw_pack_icon(d, x + 24, row_y + 8, kind, color)
        d.text((x + 66, row_y + 7), name, font=UI_14, fill=(247, 243, 255, 255) if active else (221, 215, 235, 245))
        d.text((x + 66, row_y + 27), tagline, font=UI_11, fill=(153, 143, 174, 240))
        if active:
            draw_check(d, x + w - 38, row_y + 16, (125, 182, 255, 255))
        row_y += 54

    d.line((x, row_y + 4, x + w, row_y + 4), fill=(255, 255, 255, 20))
    vy = row_y + 19
    d.text((x + 18, vy), "Feedback Volume", font=UI_13, fill=(236, 230, 247, 255))
    d.text((x + w - 54, vy), "62%", font=UI_12, fill=(166, 155, 187, 245))
    d.rounded_rectangle((x + 18, vy + 30, x + w - 18, vy + 36), radius=3, fill=(255, 255, 255, 28))
    d.rounded_rectangle((x + 18, vy + 30, x + 218, vy + 36), radius=3, fill=(130, 91, 255, 230))
    d.ellipse((x + 208, vy + 24, x + 224, vy + 42), fill=(244, 239, 255, 255))

    fy = y + h - 60
    d.line((x, fy - 8, x + w, fy - 8), fill=(255, 255, 255, 20))
    d.text((x + 18, fy + 6), "Feedback", font=UI_16, fill=(245, 240, 252, 255))
    d.rounded_rectangle((x + 258, fy + 1, x + 318, fy + 31), radius=15, fill=(128, 88, 255, 255))
    d.ellipse((x + 290, fy + 4, x + 314, fy + 28), fill=(255, 255, 255, 255))
    d.text((x + 328, fy + 8), "Quit", font=UI_12, fill=(167, 157, 187, 230))

    base.alpha_composite(panel)


def draw_key_chips(base: Image.Image, items: list[tuple[str, str]], x: int, y: int):
    d = ImageDraw.Draw(base)
    for i, (label, desc) in enumerate(items):
        yy = y + i * 64
        d.rounded_rectangle((x, yy, x + 300, yy + 48), radius=12, fill=(20, 16, 34, 150), outline=(162, 120, 255, 80), width=1)
        d.text((x + 18, yy + 9), label, font=UI_14, fill=(244, 238, 255, 245))
        d.text((x + 18, yy + 28), desc, font=UI_11, fill=(177, 162, 207, 230))


def add_vignette(img: Image.Image):
    vig = layer()
    d = ImageDraw.Draw(vig)
    for r in range(700, 80, -18):
        alpha = int((700 - r) / 620 * 9)
        d.ellipse((W / 2 - r * 1.25, H / 2 - r, W / 2 + r * 1.25, H / 2 + r), outline=(0, 0, 0, alpha), width=28)
    d.rectangle((0, 0, W, H), outline=(0, 0, 0, 120), width=42)
    img.alpha_composite(vig)


def make_shot(config):
    img = fit_bg(BACKGROUNDS / config["bg"])
    draw_radial_glow(img, (1100, 160), 380, (114, 65, 255, 54))
    add_vignette(img)
    d = ImageDraw.Draw(img)

    title_x, title_y = config.get("title_xy", (58, 134))
    draw_text_block(d, (title_x, title_y), config["title"], config["subtitle"], config.get("accent"))
    if config.get("quote"):
        qx, qy = title_x, title_y + 236
        d.text((qx, qy), config["quote"][0], font=DISPLAY_ITALIC_34, fill=(205, 185, 240, 220))
        d.text((qx + 30, qy + 40), config["quote"][1], font=UI_13, fill=(150, 132, 184, 220))

    anchor = draw_menu_bar(img, config.get("anchor_x", 1164))
    draw_popover(img, anchor, config["active_pack"], config.get("mode", "active"))

    if config.get("chips"):
        draw_key_chips(img, config["chips"], config.get("chips_x", 70), config.get("chips_y", 600))

    return img.convert("RGB")


def make_contact_sheet(paths: list[Path]):
    thumbs = []
    for path in paths:
        im = Image.open(path).convert("RGB")
        im.thumbnail((420, 262), Image.Resampling.LANCZOS)
        thumb = Image.new("RGB", (440, 306), (15, 12, 26))
        thumb.paste(im, (10, 10))
        d = ImageDraw.Draw(thumb)
        d.text((12, 278), path.name, font=UI_12, fill=(224, 216, 244))
        thumbs.append(thumb)
    sheet = Image.new("RGB", (900, 960), (10, 8, 18))
    for i, thumb in enumerate(thumbs):
        x = 10 + (i % 2) * 445
        y = 10 + (i // 2) * 316
        sheet.paste(thumb, (x, y))
    return sheet


def main():
    FINAL.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    configs = [
        {
            "bg": "05-system-feedback.png",
            "name": "01-menubar-feedback.png",
            "title": "Tappy",
            "subtitle": "Auditory typing feedback from the Mac menu bar.",
            "active_pack": "Plastic Tapping",
            "quote": ("Every key can have a voice.", "Local feedback. No typed text recorded."),
            "chips": [("Space", "soft cue"), ("Return", "clean tap"), ("Delete", "distinct hit")],
            "title_xy": (64, 132),
        },
        {
            "bg": "01-plastic-gloss.png",
            "name": "02-plastic-tapping.png",
            "title": "Plastic Tapping",
            "subtitle": "Light, glossy cues with crisp low-latency feedback.",
            "accent": "low-latency",
            "active_pack": "Plastic Tapping",
            "chips": [("Default keys", "glossy tap"), ("Space", "deeper tap"), ("Modifiers", "light click")],
        },
        {
            "bg": "02-soft-pop-bubbles.png",
            "name": "03-soft-pop.png",
            "title": "Soft Pop",
            "subtitle": "Gentle pops and airy blips for softer typing awareness.",
            "accent": "airy blips",
            "active_pack": "Soft Pop",
            "chips": [("Pop", "rounded cue"), ("Blip", "short accent"), ("Bubble", "soft finish")],
        },
        {
            "bg": "03-mechanical-ticks.png",
            "name": "04-mechanical-ticks.png",
            "title": "Mechanical Ticks",
            "subtitle": "Precise metallic ticks for clear feedback in every app.",
            "accent": "every app",
            "active_pack": "Mechanical Ticks",
            "chips": [("Tick", "compact cue"), ("Ratchet", "precise hit"), ("Return", "firm accent")],
        },
        {
            "bg": "04-organic-taps.png",
            "name": "05-organic-taps.png",
            "title": "Organic Taps",
            "subtitle": "Wood, stone, and soft textures shaped for typing awareness.",
            "accent": "typing awareness",
            "active_pack": "Organic Taps",
            "chips": [("Wood", "dry tactile cue"), ("Stone", "soft knock"), ("Sand", "muted tap")],
        },
    ]

    outputs: list[Path] = []
    for cfg in configs:
        shot = make_shot(cfg)
        out = FINAL / cfg["name"]
        shot.save(out, quality=96)
        outputs.append(out)

    make_contact_sheet(outputs).save(PREVIEW / "contact-sheet.png", quality=94)

    readme = ROOT / "README.md"
    readme.write_text(
        "# Purple Menu Bar App Store Set\\n\\n"
        "New 1440x900 App Store screenshot concepts for the menu-bar-only Tappy app.\\n\\n"
        "Final screenshots are in `final/`. The generated sound-art backgrounds are in `backgrounds/`.\\n"
        "The preview contact sheet is `preview/contact-sheet.png`.\\n\\n"
        "This set uses generated bitmap sound artwork plus deterministic rendered macOS menu-bar and Tappy popover overlays.\\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
