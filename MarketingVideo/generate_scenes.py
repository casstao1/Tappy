#!/usr/bin/env python3

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 1080
HEIGHT = 1920
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(__file__).resolve().parent / "scenes"

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

WHITE = (245, 244, 250, 255)
MUTED = (184, 181, 198, 255)
PURPLE = (126, 92, 255, 255)
LAVENDER = (199, 186, 255, 255)
BLUE = (50, 156, 255, 255)
GREEN = (72, 216, 112, 255)
TEAL = (75, 205, 199, 255)
GOLD = (244, 193, 76, 255)
ORANGE = (226, 145, 76, 255)
PINK = (238, 105, 165, 255)


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    path = FONT_ROUNDED if weight in {"medium", "semibold", "bold"} else FONT_REGULAR
    return ImageFont.truetype(path, size)


def ease_out(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return 1.0 - (1.0 - value) ** 3


def background(seed: int, top=(16, 14, 31), bottom=(6, 7, 16), glow=(111, 66, 244)) -> Image.Image:
    rng = np.random.default_rng(seed)
    y = np.linspace(0.0, 1.0, HEIGHT, dtype=np.float32)[:, None, None]
    top_arr = np.array(top, dtype=np.float32)[None, None, :]
    bottom_arr = np.array(bottom, dtype=np.float32)[None, None, :]
    pixels = top_arr * (1.0 - y) + bottom_arr * y
    pixels = np.repeat(pixels, WIDTH, axis=1)

    yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH]
    cx, cy = WIDTH * 0.70, HEIGHT * 0.24
    radius = np.sqrt(((xx - cx) / 900.0) ** 2 + ((yy - cy) / 760.0) ** 2)
    strength = np.clip(1.0 - radius, 0.0, 1.0)[..., None] ** 2
    glow_arr = np.array(glow, dtype=np.float32)[None, None, :]
    pixels = pixels * (1.0 - strength * 0.34) + glow_arr * strength * 0.34

    grain = rng.normal(0.0, 1.4, (HEIGHT, WIDTH, 1)).astype(np.float32)
    pixels = np.clip(pixels + grain, 0, 255).astype(np.uint8)
    image = Image.fromarray(pixels, "RGB").convert("RGBA")

    grid = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(grid)
    for x_pos in range(-240, WIDTH + 240, 96):
        draw.line((x_pos, 0, x_pos + 360, HEIGHT), fill=(255, 255, 255, 8), width=1)
    for y_pos in range(100, HEIGHT, 128):
        draw.line((0, y_pos, WIDTH, y_pos), fill=(255, 255, 255, 7), width=1)
    return Image.alpha_composite(image, grid)


def text_box(
    image: Image.Image,
    text: str,
    xy: tuple[int, int],
    size: int,
    fill=WHITE,
    weight="regular",
    anchor="la",
    spacing=10,
    align="left",
    stroke_width=0,
    stroke_fill=None,
) -> None:
    ImageDraw.Draw(image).multiline_text(
        xy,
        text,
        font=font(size, weight),
        fill=fill,
        anchor=anchor,
        spacing=spacing,
        align=align,
        stroke_width=stroke_width,
        stroke_fill=stroke_fill,
    )


def panel(image: Image.Image, rect: tuple[int, int, int, int], radius=34, fill=(21, 21, 29, 238), shadow=28) -> None:
    x0, y0, x1, y1 = rect
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(layer)
    shadow_draw.rounded_rectangle((x0, y0 + 14, x1, y1 + 14), radius=radius, fill=(0, 0, 0, 175))
    layer = layer.filter(ImageFilter.GaussianBlur(shadow))
    image.alpha_composite(layer)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(rect, radius=radius, fill=fill, outline=(255, 255, 255, 35), width=2)


def image_cover(source: Image.Image, size: tuple[int, int], focal=(0.5, 0.5), zoom=1.0) -> Image.Image:
    source = source.convert("RGB")
    target_w, target_h = size
    source_w, source_h = source.size
    target_ratio = target_w / target_h
    source_ratio = source_w / source_h
    if source_ratio > target_ratio:
        crop_h = source_h / zoom
        crop_w = crop_h * target_ratio
    else:
        crop_w = source_w / zoom
        crop_h = crop_w / target_ratio
    center_x = source_w * focal[0]
    center_y = source_h * focal[1]
    left = max(0, min(source_w - crop_w, center_x - crop_w / 2))
    top = max(0, min(source_h - crop_h, center_y - crop_h / 2))
    crop = source.crop((left, top, left + crop_w, top + crop_h))
    return crop.resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def paste_rounded(image: Image.Image, source: Image.Image, rect: tuple[int, int, int, int], radius=34) -> None:
    x0, y0, x1, y1 = rect
    source = source.resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    mask = Image.new("L", source.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, source.width, source.height), radius=radius, fill=255)
    image.paste(source, (x0, y0), mask)


def accent_pill(image: Image.Image, label: str, xy: tuple[int, int], color=PURPLE, width=None) -> None:
    draw = ImageDraw.Draw(image)
    fnt = font(30, "semibold")
    box = draw.textbbox((0, 0), label, font=fnt)
    measured = box[2] - box[0]
    pill_w = width or measured + 54
    x, y = xy
    base = np.array((16, 15, 25), dtype=np.float32)
    accent = np.array(color[:3], dtype=np.float32)
    background_color = tuple((base * 0.68 + accent * 0.32).astype(np.uint8)) + (255,)
    outline_color = tuple((base * 0.28 + accent * 0.72).astype(np.uint8)) + (255,)
    label_color = tuple((np.array((255, 255, 255)) * 0.18 + accent * 0.82).astype(np.uint8)) + (255,)
    draw.rounded_rectangle((x, y, x + pill_w, y + 58), radius=29, fill=background_color, outline=outline_color, width=2)
    draw.text((x + pill_w / 2, y + 29), label, font=fnt, fill=label_color, anchor="mm")


def menu_bar(image: Image.Image, active=True) -> None:
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WIDTH, 78), fill=(17, 17, 24, 235))
    draw.line((0, 78, WIDTH, 78), fill=(255, 255, 255, 30), width=2)
    text_box(image, "Tappy Demo", (48, 39), 28, fill=(232, 230, 240, 255), weight="semibold", anchor="lm")
    text_box(image, "File   Edit   View   Window   Help", (230, 39), 24, fill=(200, 198, 210, 255), anchor="lm")
    text_box(image, "Wi-Fi    100%    9:41", (1020, 39), 24, fill=(220, 218, 230, 255), anchor="rm")
    icon_x = 758
    draw.rounded_rectangle((icon_x, 13, icon_x + 54, 65), radius=15, fill=(108, 84, 220, 130) if active else (255, 255, 255, 20))
    draw.rounded_rectangle((icon_x + 15, 26, icon_x + 39, 51), radius=6, fill=(207, 198, 245, 255))


PACKS = [
    ("Tapping Nails on Plastic", BLUE, False),
    ("Wood and Sand Blocks", GREEN, False),
    ("Wet Squishy Pop", PURPLE, True),
    ("Wax Cracking", PINK, True),
    ("Bubbles", TEAL, True),
    ("Mechanical Ticks", (168, 181, 213, 255), True),
    ("Star Level Up", GOLD, True),
    ("Wood Brush", ORANGE, True),
]


def pack_icon(image: Image.Image, x: int, y: int, color, style: int) -> None:
    draw = ImageDraw.Draw(image)
    color_rgb = tuple(color[:3])
    draw.rounded_rectangle((x, y, x + 68, y + 68), radius=18, fill=color_rgb + (45,))
    if style in {0, 4}:
        for row in range(3):
            for col in range(3):
                if (row, col) != (0, 0) or style == 0:
                    cx = x + 21 + col * 14
                    cy = y + 21 + row * 14
                    draw.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=color_rgb + (255,))
    elif style == 1:
        draw.ellipse((x + 19, y + 19, x + 52, y + 47), fill=color_rgb + (255,))
        draw.line((x + 25, y + 26, x + 50, y + 50), fill=color_rgb + (255,), width=5)
    elif style == 2:
        draw.ellipse((x + 23, y + 17, x + 48, y + 53), fill=color_rgb + (255,))
        draw.ellipse((x + 31, y + 26, x + 45, y + 45), fill=(255, 255, 255, 105))
    elif style == 3:
        points = [(x + 34, y + 14), (x + 51, y + 30), (x + 43, y + 53), (x + 23, y + 50), (x + 17, y + 29)]
        draw.polygon(points, fill=color_rgb + (255,))
        draw.line((x + 25, y + 24, x + 41, y + 45), fill=(255, 255, 255, 140), width=3)
    elif style == 5:
        draw.ellipse((x + 20, y + 18, x + 50, y + 48), outline=color_rgb + (255,), width=5)
        draw.line((x + 35, y + 18, x + 35, y + 10), fill=color_rgb + (255,), width=5)
        draw.line((x + 35, y + 33, x + 46, y + 25), fill=color_rgb + (255,), width=4)
    elif style == 6:
        draw.regular_polygon((x + 34, y + 34, 23), n_sides=4, rotation=45, fill=color_rgb + (255,))
        draw.ellipse((x + 20, y + 12, x + 28, y + 20), fill=color_rgb + (255,))
        draw.ellipse((x + 49, y + 46, x + 57, y + 54), fill=color_rgb + (255,))
    else:
        draw.line((x + 21, y + 49, x + 50, y + 20), fill=color_rgb + (255,), width=9)
        draw.ellipse((x + 16, y + 44, x + 30, y + 58), fill=color_rgb + (255,))


def lock_icon(image: Image.Image, x: int, y: int) -> None:
    draw = ImageDraw.Draw(image)
    draw.arc((x + 2, y, x + 22, y + 22), 190, 350, fill=(166, 164, 176, 255), width=4)
    draw.rounded_rectangle((x, y + 11, x + 24, y + 31), radius=5, fill=(117, 115, 126, 255))


def draw_popover(image: Image.Image, selected: int, origin=(150, 250), scale=1.0) -> None:
    ox, oy = origin
    pop_w = int(780 * scale)
    row_h = int(102 * scale)
    header_h = int(122 * scale)
    controls_h = int(250 * scale)
    pop_h = header_h + row_h * len(PACKS) + controls_h
    panel(image, (ox, oy, ox + pop_w, oy + pop_h), radius=int(38 * scale), fill=(20, 20, 24, 247), shadow=int(30 * scale))
    draw = ImageDraw.Draw(image)

    pointer = [(ox + pop_w - 140, oy), (ox + pop_w - 104, oy - 30), (ox + pop_w - 68, oy)]
    draw.polygon(pointer, fill=(20, 20, 24, 247))
    text_box(image, "Tappy", (ox + 32, oy + 51), int(39 * scale), weight="bold", anchor="lm")
    draw.ellipse((ox + pop_w - 176, oy + 39, ox + pop_w - 158, oy + 57), fill=GREEN)
    text_box(image, "Active", (ox + pop_w - 140, oy + 51), int(29 * scale), fill=MUTED, weight="medium", anchor="lm")
    draw.line((ox, oy + header_h, ox + pop_w, oy + header_h), fill=(255, 255, 255, 38), width=2)

    for index, (name, color, premium) in enumerate(PACKS):
        top = oy + header_h + index * row_h
        if index == selected:
            draw.rounded_rectangle((ox + 16, top + 7, ox + pop_w - 16, top + row_h - 7), radius=int(20 * scale), fill=tuple(color[:3]) + (30,), outline=tuple(color[:3]) + (80,), width=2)
        pack_icon(image, ox + int(31 * scale), top + int(17 * scale), color, index)
        text_box(image, name, (ox + int(124 * scale), top + row_h / 2), int(31 * scale), fill=WHITE, weight="semibold", anchor="lm")
        if index == selected:
            x = ox + pop_w - int(63 * scale)
            y = top + row_h // 2
            draw.line((x - 16, y, x - 6, y + 12), fill=BLUE, width=max(4, int(6 * scale)))
            draw.line((x - 6, y + 12, x + 14, y - 18), fill=BLUE, width=max(4, int(6 * scale)))
        elif premium:
            lock_icon(image, ox + pop_w - int(72 * scale), top + int(35 * scale))

    controls_top = oy + header_h + row_h * len(PACKS)
    draw.line((ox, controls_top, ox + pop_w, controls_top), fill=(255, 255, 255, 38), width=2)
    text_box(image, "Feedback Volume", (ox + 34, controls_top + 48), int(29 * scale), weight="semibold", anchor="lm")
    text_box(image, "72%", (ox + pop_w - 34, controls_top + 48), int(28 * scale), fill=MUTED, anchor="rm")
    line_y = controls_top + int(104 * scale)
    draw.rounded_rectangle((ox + 62, line_y, ox + pop_w - 62, line_y + 10), radius=5, fill=(75, 75, 84, 255))
    draw.rounded_rectangle((ox + 62, line_y, ox + int(pop_w * 0.72), line_y + 10), radius=5, fill=BLUE)
    knob_x = ox + int(pop_w * 0.72)
    draw.ellipse((knob_x - 17, line_y - 12, knob_x + 17, line_y + 22), fill=(232, 232, 237, 255))
    footer_y = controls_top + int(150 * scale)
    draw.line((ox, footer_y, ox + pop_w, footer_y), fill=(255, 255, 255, 38), width=2)
    text_box(image, "Feedback", (ox + 74, footer_y + 52), int(29 * scale), weight="semibold", anchor="lm")
    toggle_x = ox + int(236 * scale)
    draw.rounded_rectangle((toggle_x, footer_y + 28, toggle_x + 104, footer_y + 76), radius=24, fill=BLUE)
    draw.ellipse((toggle_x + 57, footer_y + 32, toggle_x + 100, footer_y + 74), fill=(236, 240, 255, 255))
    text_box(image, "Quit", (ox + pop_w - 34, footer_y + 52), int(27 * scale), fill=MUTED, anchor="rm")


def add_logo(image: Image.Image, size: int, center: tuple[int, int]) -> None:
    icon = Image.open(ROOT / "tappy-icon.png").convert("RGBA")
    icon.thumbnail((size, size), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    x = center[0] - icon.width // 2
    y = center[1] - icon.height // 2
    shadow.paste((98, 63, 255, 180), (x + 18, y + 28, x + icon.width - 18, y + icon.height - 10))
    shadow = shadow.filter(ImageFilter.GaussianBlur(48))
    image.alpha_composite(shadow)
    image.alpha_composite(icon, (x, y))


def scene_hero() -> Image.Image:
    image = background(11, top=(20, 16, 43), bottom=(7, 7, 17), glow=(112, 74, 255))
    draw = ImageDraw.Draw(image)
    for radius, alpha in [(350, 16), (270, 20), (190, 28)]:
        draw.ellipse((540 - radius, 445 - radius, 540 + radius, 445 + radius), outline=(185, 166, 255, alpha), width=3)
    add_logo(image, 320, (540, 465))
    text_box(image, "Tappy", (540, 790), 124, weight="bold", anchor="ma", align="center")
    text_box(image, "Your keyboard has\nbeen too quiet.", (540, 945), 62, fill=LAVENDER, weight="semibold", anchor="ma", spacing=12, align="center")
    accent_pill(image, "ASMR keyboard sounds for Mac", (278, 1215), color=PURPLE, width=524)
    text_box(image, "TURN SOUND ON", (540, 1680), 28, fill=(178, 174, 193, 255), weight="semibold", anchor="mm")
    for idx in range(7):
        bar_h = 22 + (idx % 4) * 18
        x = 486 + idx * 18
        draw.rounded_rectangle((x, 1570 - bar_h / 2, x + 8, 1570 + bar_h / 2), radius=4, fill=(188, 173, 255, 190))
    return image


def editor_scene(text: str, cursor=True) -> Image.Image:
    image = background(21, top=(24, 20, 43), bottom=(8, 8, 18), glow=(106, 62, 216))
    menu_bar(image)
    panel(image, (70, 205, 1010, 1520), radius=36, fill=(245, 243, 247, 252), shadow=38)
    draw = ImageDraw.Draw(image)
    draw.ellipse((110, 249, 132, 271), fill=(255, 95, 86, 255))
    draw.ellipse((145, 249, 167, 271), fill=(255, 189, 47, 255))
    draw.ellipse((180, 249, 202, 271), fill=(41, 202, 64, 255))
    text_box(image, "Notes", (540, 262), 28, fill=(94, 91, 102, 255), weight="semibold", anchor="mm")
    draw.line((70, 298, 1010, 298), fill=(20, 18, 30, 24), width=2)
    text_box(image, text, (140, 530), 78, fill=(32, 29, 42, 255), weight="semibold", spacing=22)
    if cursor:
        lines = text.split("\n")
        last_line = lines[-1]
        bbox = draw.textbbox((0, 0), last_line, font=font(78, "semibold"))
        cursor_x = 140 + bbox[2] - bbox[0] + 9
        cursor_y = 530 + (len(lines) - 1) * 117
        draw.rounded_rectangle((cursor_x, cursor_y + 5, cursor_x + 7, cursor_y + 92), radius=3, fill=PURPLE)
    text_box(image, "Every character gets its own tactile sound.", (540, 1620), 38, fill=MUTED, weight="medium", anchor="ma", align="center")
    return image


def scene_menu(selected: int, title: str, detail: str) -> Image.Image:
    image = background(30 + selected, top=(15, 17, 29), bottom=(6, 7, 13), glow=(61, 109, 112))
    menu_bar(image)
    text_box(image, title, (70, 142), 58, weight="bold")
    text_box(image, detail, (73, 216), 32, fill=MUTED, weight="medium")
    draw_popover(image, selected=selected, origin=(150, 315), scale=1.0)
    return image


def scene_everywhere() -> Image.Image:
    image = background(43, top=(18, 18, 34), bottom=(7, 8, 15), glow=(63, 102, 164))
    menu_bar(image)
    text_box(image, "Works wherever you type.", (70, 155), 60, weight="bold")
    text_box(image, "Messages. Notes. Browsers. Everywhere.", (73, 232), 32, fill=MUTED, weight="medium")

    panel(image, (58, 340, 1022, 1510), radius=38, fill=(239, 239, 244, 250), shadow=38)
    draw = ImageDraw.Draw(image)
    draw.ellipse((98, 383, 122, 407), fill=(255, 95, 86, 255))
    draw.ellipse((137, 383, 161, 407), fill=(255, 189, 47, 255))
    draw.ellipse((176, 383, 200, 407), fill=(41, 202, 64, 255))
    text_box(image, "Draft", (540, 397), 28, fill=(95, 93, 105, 255), weight="semibold", anchor="mm")
    draw.line((58, 435, 1022, 435), fill=(25, 22, 35, 26), width=2)
    text_box(image, "Typing should feel\nas good as it looks.", (120, 625), 74, fill=(29, 28, 39, 255), weight="semibold", spacing=18)
    draw.rounded_rectangle((120, 1035, 724, 1045), radius=5, fill=(200, 198, 208, 255))
    draw.rounded_rectangle((120, 1035, 546, 1045), radius=5, fill=PURPLE)
    text_box(image, "Tappy is active system-wide", (120, 1125), 34, fill=(81, 78, 91, 255), weight="medium")
    draw.ellipse((124, 1208, 146, 1230), fill=GREEN)
    text_box(image, "Low-latency playback", (166, 1219), 32, fill=(81, 78, 91, 255), weight="medium", anchor="lm")

    for index, key in enumerate(["T", "A", "P", "P", "Y"]):
        x = 157 + index * 154
        y = 1590 + int(math.sin(index * 1.7) * 16)
        draw.rounded_rectangle((x, y, x + 112, y + 112), radius=24, fill=(255, 255, 255, 22), outline=(255, 255, 255, 55), width=2)
        text_box(image, key, (x + 56, y + 56), 42, fill=LAVENDER, weight="semibold", anchor="mm")
    return image


def photo_card(image: Image.Image, source: Image.Image, rect, label: str, detail: str, color, focal, zoom) -> None:
    x0, y0, x1, y1 = rect
    panel(image, rect, radius=34, fill=(18, 18, 25, 248), shadow=24)
    photo_height = int((y1 - y0) * 0.66)
    crop = image_cover(source, (x1 - x0, photo_height), focal=focal, zoom=zoom)
    paste_rounded(image, crop, (x0, y0, x1, y0 + photo_height), radius=34)
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for step in range(170):
        alpha = int(step / 170 * 220)
        y = y0 + photo_height - 170 + step
        od.line((x0, y, x1, y), fill=(12, 11, 20, alpha), width=1)
    image.alpha_composite(overlay)
    accent_pill(image, detail, (x0 + 24, y0 + photo_height - 55), color=color)
    text_box(image, label, (x0 + 28, y0 + photo_height + 52), 36, weight="semibold")


def scene_sound_graphics() -> Image.Image:
    image = background(52, top=(20, 16, 42), bottom=(7, 7, 16), glow=(114, 66, 242))
    text_box(image, "Pick your sound.", (66, 136), 68, weight="bold")
    text_box(image, "From subtle taps to gloriously strange pops.", (70, 226), 33, fill=MUTED, weight="medium")
    finger = Image.open(ROOT / "AppStoreConnectMarketingPhotos/01-tappy-finger-2880x1800.jpg")
    bubbles = Image.open(ROOT / "AppStoreConnectMarketingPhotos/02-tappy-bubble-2880x1800.jpg")
    wood = Image.open(ROOT / "AppStoreConnectMarketingPhotos/03-tappy-wood-2880x1800.jpg")
    photo_card(image, finger, (58, 350, 518, 945), "Tapping Nails\non Plastic", "FREE", BLUE, (0.55, 0.56), 1.55)
    photo_card(image, wood, (562, 350, 1022, 945), "Wood and\nSand Blocks", "FREE", GREEN, (0.48, 0.53), 1.45)
    photo_card(image, bubbles, (58, 1010, 518, 1605), "Wet Squishy\nPop", "PREMIUM", PURPLE, (0.45, 0.54), 1.55)
    photo_card(image, bubbles, (562, 1010, 1022, 1605), "Bubbles", "PREMIUM", TEAL, (0.62, 0.52), 1.85)
    text_box(image, "Each pack is built from real tactile recordings.", (540, 1750), 33, fill=LAVENDER, weight="medium", anchor="ma", align="center")
    return image


def scene_all_sounds() -> Image.Image:
    image = background(65, top=(13, 16, 28), bottom=(7, 7, 14), glow=(50, 106, 118))
    text_box(image, "Eight ways to type.", (66, 132), 66, weight="bold")
    text_box(image, "Switch in seconds from the Mac menu bar.", (70, 220), 33, fill=MUTED, weight="medium")
    panel(image, (58, 330, 1022, 1575), radius=42, fill=(17, 18, 23, 244), shadow=36)
    draw = ImageDraw.Draw(image)
    for index, (name, color, premium) in enumerate(PACKS):
        column = index % 2
        row = index // 2
        x = 92 + column * 470
        y = 390 + row * 280
        draw.rounded_rectangle((x, y, x + 424, y + 222), radius=28, fill=tuple(color[:3]) + (22,), outline=tuple(color[:3]) + (70,), width=2)
        pack_icon(image, x + 25, y + 28, color, index)
        label = name.replace(" on ", " on\n").replace(" and ", " and\n") if len(name) > 18 else name
        text_box(image, label, (x + 118, y + 38), 31, weight="semibold", spacing=4)
        text_box(image, "Premium" if premium else "Included", (x + 118, y + 150), 25, fill=color, weight="medium")
    accent_pill(image, "2 free packs", (235, 1668), color=GREEN, width=258)
    accent_pill(image, "6 premium packs", (525, 1668), color=PURPLE, width=320)
    return image


def scene_privacy() -> Image.Image:
    image = background(77, top=(13, 18, 29), bottom=(6, 8, 15), glow=(48, 120, 103))
    add_logo(image, 210, (540, 310))
    text_box(image, "Your keys stay private.", (540, 540), 68, weight="bold", anchor="ma", align="center")
    text_box(image, "Tappy uses physical key codes only.\nIt never reads, stores, or sends what you type.", (540, 672), 40, fill=MUTED, weight="medium", anchor="ma", spacing=13, align="center")
    facts = [
        ("LOCAL", "Sound stays on your Mac", GREEN),
        ("FAST", "Feedback feels immediate", BLUE),
        ("SYSTEM-WIDE", "Works across Mac apps", PURPLE),
    ]
    for index, (eyebrow, label, color) in enumerate(facts):
        top = 920 + index * 210
        panel(image, (120, top, 960, top + 156), radius=28, fill=(23, 27, 36, 248), shadow=14)
        draw = ImageDraw.Draw(image)
        draw.ellipse((158, top + 54, 190, top + 86), fill=color)
        text_box(image, eyebrow, (224, top + 51), 24, fill=color, weight="bold")
        text_box(image, label, (224, top + 104), 35, weight="semibold", anchor="lm")
    return image


def scene_cta() -> Image.Image:
    image = background(91, top=(24, 17, 50), bottom=(6, 7, 17), glow=(126, 73, 255))
    add_logo(image, 310, (540, 470))
    text_box(image, "Tappy", (540, 760), 118, weight="bold", anchor="ma", align="center")
    text_box(image, "Make every key\nfeel better.", (540, 950), 64, fill=LAVENDER, weight="semibold", anchor="ma", spacing=10, align="center")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((196, 1235, 884, 1376), radius=34, fill=(245, 244, 249, 255))
    text_box(image, "Download on the", (540, 1275), 25, fill=(30, 27, 40, 255), weight="medium", anchor="mm")
    text_box(image, "Mac App Store", (540, 1333), 44, fill=(24, 21, 33, 255), weight="bold", anchor="mm")
    accent_pill(image, "Free to download", (350, 1465), color=GREEN, width=380)
    text_box(image, "Tappy: ASMR Keyboard Sounds", (540, 1705), 30, fill=MUTED, weight="medium", anchor="mm")
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    scenes = [
        ("01-hero.png", scene_hero()),
        ("02-question.png", editor_scene("What if every key")),
        ("03-question-complete.png", editor_scene("What if every key\nfelt this satisfying?")),
        ("04-menu-plastic.png", scene_menu(0, "Lives in your menu bar.", "Choose a sound and keep typing.")),
        ("05-menu-squishy.png", scene_menu(2, "Switch the whole texture.", "One click. A completely different feel.")),
        ("06-everywhere.png", scene_everywhere()),
        ("07-sound-graphics.png", scene_sound_graphics()),
        ("08-all-sounds.png", scene_all_sounds()),
        ("09-privacy.png", scene_privacy()),
        ("10-cta.png", scene_cta()),
    ]
    for filename, image in scenes:
        destination = OUTPUT / filename
        image.convert("RGB").save(destination, quality=96)
        print(destination)


if __name__ == "__main__":
    main()
