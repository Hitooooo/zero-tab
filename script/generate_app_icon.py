#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ZeroTab 应用图标渲染器。

设计规格（几何、配色、隐喻）见 Design.md「应用图标」。所有几何常量以 1024pt
画布为基准，实际渲染时按倍数超采样后降采样，保证 16pt 下仍然可辨。

依赖：Python 3 + Pillow + numpy。这只在设计期与资产再生成时需要，App 运行时不依赖。

用法：
    python3 script/generate_app_icon.py --concepts          # 生成候选方案与预览图
    python3 script/generate_app_icon.py --final cards       # 产出 PNG、ICNS 和 SVG
    python3 script/generate_app_icon.py --final cards --no-icns # 只出 PNG/SVG
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
WORK = ROOT / "dist" / "icon-build"
PREVIEW_DIR = ROOT / "dist" / "icon-preview"

CANVAS = 1024           # 设计基准画布
SUPERSAMPLE = 3         # 超采样倍数（3072 渲染后降采样）
BODY_INSET = 100        # 本项目 ICNS 的视觉留白；不是系统蒙版的精确规格
SQUIRCLE_N = 5.0        # 静态 ICNS 的连续圆角近似

RECOMMENDED = "cards"
CONCEPTS = ("bars", "cards", "window-arrow")
CONCEPT_TITLES = {
    "bars": "双线错位",
    "cards": "玻璃卡片",
    "window-arrow": "窗格箭头",
}

# 深蓝底 + 克制的极光；高光压在低强度，保证白色符号在任何位置都有对比。
PALETTE = {
    "angle": 45.0,
    "stops": [(0.0, "#4B65CF"), (0.46, "#293676"), (1.0, "#17203E")],
    "glows": [
        (0.16, 0.10, 0.55, 0.42, "#79E6FF", 0.20, 2.0),
        (0.92, 0.96, 0.55, 0.50, "#8A6BFF", 0.14, 2.0),
    ],
}
ACCENT = "#7FE3FF"
CARD_BACK = (232, 224, 622, 614)
CARD_FRONT = (402, 398, 792, 788)
CARD_RADIUS = 86
CARD_STROKE = 18

ICNS_ENTRIES = (
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
)


# --------------------------------------------------------------------------- 基础工具


def hex_rgb(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def rgb255(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    r, g, b = (hex_rgb(value) * 255).round().astype(int)
    return int(r), int(g), int(b), alpha


def squircle_mask(size: int, inset: float, n: float = SQUIRCLE_N) -> np.ndarray:
    """Apple 风格超椭圆蒙版，返回 float32 (size, size) 硬边覆盖率。"""
    a = (size - 2.0 * inset) / 2.0
    c = size / 2.0
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    v = (np.abs(x - c) / a) ** n + (np.abs(y - c) / a) ** n
    return (v <= 1.0).astype(np.float32)


def vertical_gradient(size: int, top: tuple[int, int, int, int], bottom: tuple[int, int, int, int],
                      start: float = 0.0, end: float = 1.0) -> Image.Image:
    h = size
    ramp = np.clip((np.linspace(0.0, 1.0, h, dtype=np.float32) - start)
                   / (end - start), 0.0, 1.0)[:, None]
    cols = np.zeros((h, 4), dtype=np.float32)
    for i in range(4):
        cols[:, i] = top[i] * (1.0 - ramp[:, 0]) + bottom[i] * ramp[:, 0]
    row = np.repeat(cols[:, None, :], size, axis=1)
    return Image.fromarray(row.round().astype(np.uint8), "RGBA")


def paste_shape(base: Image.Image, mask: Image.Image, fill: Image.Image | None = None,
                color: tuple[int, int, int, int] | None = None) -> Image.Image:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    if fill is None:
        fill = Image.new("RGBA", base.size, color)
    layer = fill.copy()
    layer.putalpha(ImageChops.multiply(fill.getchannel("A"), mask))
    return Image.alpha_composite(base, layer)


def soft_shadow(base: Image.Image, mask: Image.Image, offset: tuple[int, int],
                blur: float, alpha: int) -> Image.Image:
    shadow = Image.new("L", base.size, 0)
    shadow.paste(mask, offset)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    shadow = shadow.point(lambda v: int(v * alpha / 255))
    return paste_shape(base, shadow, color=(0, 0, 0, 255))


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in ("/System/Library/Fonts/Helvetica.ttc",
                 "/System/Library/Fonts/Supplemental/Arial.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


# --------------------------------------------------------------------------- 背景


def background(size: int, palette: dict) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = math.cos(math.radians(palette["angle"]))
    cy = math.sin(math.radians(palette["angle"]))
    t = (x * cx + y * cy) / (size * (abs(cx) + abs(cy)))

    stops = palette["stops"]
    ts = np.array([s[0] for s in stops], dtype=np.float32)
    cols = np.stack([hex_rgb(s[1]) for s in stops])
    field = np.zeros((size, size, 3), dtype=np.float32)
    for i in range(len(stops) - 1):
        lo, hi = float(ts[i]), float(ts[i + 1])
        band = (t >= lo) & (t <= hi)
        w = np.clip((t - lo) / max(hi - lo, 1e-6), 0.0, 1.0)[..., None]
        seg = cols[i] * (1.0 - w) + cols[i + 1] * w
        field[band] = seg[band]

    nx = x / size
    ny = y / size
    for gx, gy, rx, ry, hex_color, alpha, power in palette["glows"]:
        d = np.sqrt(((nx - gx) / rx) ** 2 + ((ny - gy) / ry) ** 2)
        w = (np.clip(1.0 - d, 0.0, 1.0) ** power * alpha)[..., None]
        field = field * (1.0 - w) + hex_rgb(hex_color) * w

    field = np.clip(field, 0.0, 1.0)
    return Image.fromarray((np.dstack([field, np.ones((size, size), np.float32)]) * 255)
                           .round().astype(np.uint8), "RGBA")


def body_layer(size: int, inset: float) -> tuple[Image.Image, Image.Image]:
    """返回（超椭圆主体，内圈蒙版，主题外阴影）。"""
    body = squircle_mask(size, inset)
    inner = squircle_mask(size, inset + 6.0 * size / CANVAS)
    body_img = Image.fromarray((body * 255).astype(np.uint8), "L")
    # 静态 ICNS 烘焙一层轻投影；Icon Composer 图层不应包含这层效果。
    shadow = Image.new("L", (size, size), 0)
    shadow.paste(body_img, (0, round(9 * size / CANVAS)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * size / CANVAS))
    shadow = shadow.point(lambda v: int(v * 0.42))
    return body_img, Image.fromarray((inner * 255).astype(np.uint8), "L"), shadow


# --------------------------------------------------------------------------- 符号


def symbol_bars(size: int) -> Image.Image:
    """错位双线：后线青色、前线白色，对应当前项与下一个候选项。

    笔画 140、间距 104，在 16pt 下仍分别约有 2.2px 与 1.6px。
    """
    k = size / CANVAS
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    back_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(back_mask).rounded_rectangle(
        [250 * k, 320 * k, 600 * k, 460 * k], radius=70 * k, fill=255)
    back_mask = back_mask.filter(ImageFilter.GaussianBlur(2.0 * k))
    back_fill = vertical_gradient(size, rgb255("#BDF2FF"), rgb255("#4CC4EE"))
    layer = paste_shape(layer, back_mask, fill=back_fill)

    front_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(front_mask).rounded_rectangle(
        [424 * k, 564 * k, 774 * k, 704 * k], radius=70 * k, fill=255)
    layer = soft_shadow(layer, front_mask, (0, round(18 * k)), 26 * k, 130)
    front_fill = vertical_gradient(size, rgb255("#FFFFFF"), rgb255("#D3E0FF"))
    layer = paste_shape(layer, front_mask, fill=front_fill)
    return layer


def symbol_cards(size: int) -> Image.Image:
    """两张等大卡片：加厚后卡片轮廓，保证小尺寸仍能辨识窗口栈。"""
    k = size / CANVAS
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    back_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(back_mask).rounded_rectangle(
        [v * k for v in CARD_BACK], radius=CARD_RADIUS * k, fill=255)
    layer = paste_shape(layer, back_mask, color=rgb255("#BDCEFF", 140))

    ring = Image.new("L", (size, size), 0)
    ImageDraw.Draw(ring).rounded_rectangle(
        [v * k for v in CARD_BACK], radius=CARD_RADIUS * k, outline=255,
        width=max(1, round(CARD_STROKE * k)))
    layer = paste_shape(layer, ring, color=rgb255("#EAF1FF", 220))

    front_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(front_mask).rounded_rectangle(
        [v * k for v in CARD_FRONT], radius=CARD_RADIUS * k, fill=255)
    layer = soft_shadow(layer, front_mask, (0, round(12 * k)), 16 * k, 78)
    gradient = vertical_gradient(size, rgb255("#F9FCFF"), rgb255("#DCE7FF"),
                                 CARD_FRONT[1] / CANVAS, CARD_FRONT[3] / CANVAS)
    layer = paste_shape(layer, front_mask, fill=gradient)
    return layer


def symbol_window_arrow(size: int) -> Image.Image:
    """窗格 + 前进箭头：一个窗口轮廓，内部一个指向右侧的箭头。"""
    k = size / CANVAS
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    frame = Image.new("L", (size, size), 0)
    ImageDraw.Draw(frame).rounded_rectangle(
        [216 * k, 250 * k, 808 * k, 774 * k], radius=124 * k, outline=255,
        width=round(64 * k))
    layer = paste_shape(layer, frame, color=rgb255("#FFFFFF", 220))

    arrow = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(arrow)
    width = round(78 * k)
    points = [(452 * k, 424 * k), (556 * k, 512 * k), (452 * k, 600 * k)]
    draw.line(points, fill=255, width=width, joint="curve")
    for px, py in points:
        r = width / 2.0
        draw.ellipse([px - r, py - r, px + r, py + r], fill=255)
    layer = paste_shape(layer, arrow, color=rgb255(ACCENT, 255))
    return layer


SYMBOLS = {
    "bars": symbol_bars,
    "cards": symbol_cards,
    "window-arrow": symbol_window_arrow,
}


# --------------------------------------------------------------------------- 主渲染


def render_master(concept: str, size: int = CANVAS, supersample: int = SUPERSAMPLE) -> Image.Image:
    render_size = size * supersample
    k = render_size / CANVAS

    body, inner, shadow = body_layer(render_size, BODY_INSET * k)
    image = background(render_size, PALETTE)
    image.putalpha(body)

    y = np.mgrid[0:render_size, 0:render_size][0].astype(np.float32) / render_size
    field = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0

    # 仅在内圈与外圈之间的 6pt 描边上做亮度调制，主体内部保持平坦。
    band = np.clip((np.asarray(body, np.float32) - np.asarray(inner, np.float32)) / 255.0, 0.0, 1.0)

    top = (np.clip(1.0 - y * 1.9, 0.0, 1.0) ** 2 * 0.34)[..., None]
    field = field * (1.0 - band[..., None] * top) + band[..., None] * top

    bottom = (np.clip((y - 0.62) / 0.38, 0.0, 1.0) ** 2 * 0.30)[..., None]
    field = field * (1.0 - band[..., None] * bottom)

    # 左上斜向玻璃反光，压在主体内部且强度很低，避免吃掉白色符号的对比。
    sheen = Image.new("L", (render_size, render_size), 0)
    ImageDraw.Draw(sheen).ellipse(
        [140 * k, -520 * k, 900 * k, 430 * k], fill=34)
    sheen = sheen.filter(ImageFilter.GaussianBlur(130 * k))
    sheen = Image.composite(sheen, Image.new("L", sheen.size, 0), body)
    sm = (np.asarray(sheen, np.float32) / 255.0)[..., None]
    field = field * (1.0 - sm) + sm

    image = Image.fromarray(
        (np.dstack([np.clip(field, 0.0, 1.0), np.asarray(body, np.float32) / 255.0]) * 255)
        .round().astype(np.uint8), "RGBA")

    symbol = SYMBOLS[concept](render_size)
    symbol = Image.composite(symbol, Image.new("RGBA", symbol.size, (0, 0, 0, 0)), body)
    image = Image.alpha_composite(image, symbol)

    # 投影在最底层，与主体一起保证不越出画布。
    canvas = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    canvas = paste_shape(canvas, shadow, color=(0, 0, 0, 255))
    canvas = Image.alpha_composite(canvas, image)

    out = canvas.resize((size, size), Image.LANCZOS)
    # Pillow RGBA 已是 straight alpha，不能再次反预乘，否则边缘会变亮。
    return out


# --------------------------------------------------------------------------- 资产导出


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def write_icns(master: Image.Image, path: Path) -> None:
    iconset = WORK / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    for px, name in ICNS_ENTRIES:
        master.resize((px, px), Image.LANCZOS).save(iconset / name, "PNG")
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(path)], check=True)


def _squircle_path(cx: float, cy: float, a: float, n: float, samples: int = 128) -> str:
    points: list[tuple[float, float]] = []
    for quadrant in range(4):
        for i in range(samples):
            t = (i / samples) * (math.pi / 2)
            ct, st = math.cos(t), math.sin(t)
            x = a * math.copysign(abs(ct) ** (2.0 / n), ct)
            y = a * math.copysign(abs(st) ** (2.0 / n), st)
            if quadrant == 0:
                px, py = x, y
            elif quadrant == 1:
                px, py = -y, x
            elif quadrant == 2:
                px, py = -x, -y
            else:
                px, py = y, -x
            points.append((cx + px, cy + py))
    head = f"M {points[0][0]:.2f} {points[0][1]:.2f}"
    tail = " ".join(f"L {px:.2f} {py:.2f}" for px, py in points[1:])
    return f"{head} {tail} Z"


def write_svg(concept: str, path: Path) -> None:
    """可编辑的矢量伴生稿：共用几何；静态背景光效与 PNG 不完全相同。"""
    a = (CANVAS - 2 * BODY_INSET) / 2.0
    stops = "\n".join(
        f'      <stop offset="{t:.2f}" stop-color="{c}"/>' for t, c in PALETTE["stops"])
    body_path = _squircle_path(CANVAS / 2, CANVAS / 2, a, SQUIRCLE_N)
    if concept == "bars":
        symbol = (
            '    <rect x="250" y="320" width="350" height="140" rx="70" fill="url(#backFill)"/>\n'
            '    <rect x="424" y="564" width="350" height="140" rx="70" fill="url(#frontFill)"/>')
        defs = ('    <linearGradient id="backFill" x1="0" y1="320" x2="0" y2="460" '
                'gradientUnits="userSpaceOnUse">\n'
                '      <stop offset="0" stop-color="#bdf2ff"/>\n'
                '      <stop offset="1" stop-color="#4cc4ee"/>\n'
                '    </linearGradient>\n'
                '    <linearGradient id="frontFill" x1="0" y1="564" x2="0" y2="704" '
                'gradientUnits="userSpaceOnUse">\n'
                '      <stop offset="0" stop-color="#ffffff"/>\n'
                '      <stop offset="1" stop-color="#d3e0ff"/>\n'
                '    </linearGradient>')
    elif concept == "cards":
        bx, by, br, bb = CARD_BACK
        fx, fy, fr, fb = CARD_FRONT
        half = CARD_STROKE / 2
        symbol = (
            f'    <rect x="{bx}" y="{by}" width="{br-bx}" height="{bb-by}" '
            f'rx="{CARD_RADIUS}" fill="#BDCEFF" fill-opacity="{140/255:.5f}"/>\n'
            f'    <rect x="{bx+half}" y="{by+half}" width="{br-bx-CARD_STROKE}" '
            f'height="{bb-by-CARD_STROKE}" rx="{CARD_RADIUS-half}" fill="none" '
            f'stroke="#EAF1FF" stroke-opacity="{220/255:.5f}" stroke-width="{CARD_STROKE}"/>\n'
            f'    <rect x="{fx}" y="{fy}" width="{fr-fx}" height="{fb-fy}" '
            f'rx="{CARD_RADIUS}" fill="url(#cardFill)" filter="url(#cardShadow)"/>')
        defs = (f'    <linearGradient id="cardFill" x1="0" y1="{fy}" x2="0" y2="{fb}" '
                'gradientUnits="userSpaceOnUse">\n'
                '      <stop offset="0" stop-color="#F9FCFF"/>\n'
                '      <stop offset="1" stop-color="#DCE7FF"/>\n'
                '    </linearGradient>\n'
                '    <filter id="cardShadow" x="-30%" y="-30%" width="160%" height="170%">\n'
                '      <feDropShadow dx="0" dy="12" stdDeviation="16" flood-opacity="0.306"/>\n'
                '    </filter>')
    else:
        symbol = (
            '    <rect x="216" y="250" width="592" height="524" rx="124" fill="none" '
            'stroke="#ffffff" stroke-opacity="0.82" stroke-width="36"/>\n'
            '    <path d="M 452 424 L 556 512 L 452 600" fill="none" stroke="#7fe3ff" '
            'stroke-width="52" stroke-linecap="round" stroke-linejoin="round"/>')
        defs = ""

    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="body" x1="100" y1="100" x2="924" y2="924" gradientUnits="userSpaceOnUse">
{stops}
    </linearGradient>
    <clipPath id="clip">
      <path d="{body_path}"/>
    </clipPath>
{defs}
  </defs>
  <g clip-path="url(#clip)">
    <rect x="0" y="0" width="1024" height="1024" fill="url(#body)"/>
    <ellipse cx="205" cy="123" rx="530" ry="410" fill="#79e6ff" opacity="0.18"/>
{symbol}
  </g>
</svg>
'''
    path.write_text(svg, encoding="utf-8")


# --------------------------------------------------------------------------- 预览图

PANEL_BG = (18, 19, 24, 255)
LIGHT_BG = (242, 242, 247, 255)


def _system_icon(path: str, px: int) -> Image.Image | None:
    try:
        icon = Image.open(path)
        icon.load()
    except Exception:
        return None
    icon = icon.convert("RGBA")
    return icon.resize((px, px), Image.LANCZOS)


def _switcher_panel(px: int) -> Image.Image:
    panel = Image.new("RGBA", (px, 300), (0, 0, 0, 0))
    draw = ImageDraw.Draw(panel, "RGBA")
    draw.rounded_rectangle([0, 0, px - 1, 299], radius=54, fill=(38, 40, 52, 235))
    draw.rounded_rectangle([0, 0, px - 1, 299], radius=54, outline=(255, 255, 255, 34), width=2)

    sources = [
        ("/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns", False),
        ("/System/Applications/Safari.app/Contents/Resources/AppIcon.icns", False),
        (None, True),
        ("/Applications/Google Chrome.app/Contents/Resources/app.icns", False),
        ("/System/Applications/Music.app/Contents/Resources/AppIcon.icns", False),
    ]
    slot = px // 5
    for index, (path, is_ours) in enumerate(sources):
        icon = render_master(RECOMMENDED, size=112, supersample=2) if is_ours else (
            _system_icon(path, 112) if path else None)
        if icon is None:
            continue
        cx = slot * index + slot // 2
        if is_ours:
            draw.rounded_rectangle([cx - 66, 62, cx + 66, 194], radius=30,
                                   fill=(255, 255, 255, 38))
        panel.alpha_composite(icon, (cx - 56, 70))
    label = font(30)
    text = "ZeroTab"
    width = draw.textlength(text, font=label)
    draw.text(((px - width) / 2, 232), text, font=label, fill=(255, 255, 255, 235))
    return panel


def preview_sheet() -> Path:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (1860, 1560), PANEL_BG)
    draw = ImageDraw.Draw(sheet, "RGBA")
    title = font(38)
    small = font(26)

    for index, concept in enumerate(CONCEPTS):
        x = 60 + index * 590
        draw.text((x, 44), f"{concept}  ({CONCEPT_TITLES[concept]})", font=title,
                  fill=(255, 255, 255, 235))
        icon = render_master(concept, size=520, supersample=2)
        sheet.alpha_composite(icon, (x, 100))

    draw.rounded_rectangle([60, 680, 1800, 1010], radius=40, fill=LIGHT_BG)
    for index, concept in enumerate(CONCEPTS):
        x = 110 + index * 570
        icon = render_master(concept, size=280, supersample=2)
        sheet.alpha_composite(icon, (x, 705))

    draw.text((60, 1050), "尺寸可辨性 (推荐方案)", font=title, fill=(255, 255, 255, 235))
    x = 60
    for px in (128, 64, 32, 16):
        icon = render_master(RECOMMENDED, size=px, supersample=2)
        draw.text((x, 1108), f"{px}px", font=small, fill=(255, 255, 255, 160))
        sheet.alpha_composite(icon, (x, 1150))
        x += px + 70

    zoom = render_master(RECOMMENDED, size=32, supersample=2).resize((160, 160), Image.NEAREST)
    sheet.alpha_composite(zoom, (x + 40, 1150))
    draw.text((x + 40, 1108), "32px ×5 放大", font=small, fill=(255, 255, 255, 160))

    draw.text((700, 1050), "在切换面板中的实际观感", font=title, fill=(255, 255, 255, 235))
    sheet.alpha_composite(_switcher_panel(1040), (760, 1100))

    out = PREVIEW_DIR / "icon-concepts.png"
    sheet.convert("RGB").save(out, "PNG")
    for concept in CONCEPTS:
        render_master(concept, size=512, supersample=2).save(
            PREVIEW_DIR / f"concept-{concept}-refined.png", "PNG")
    return out


# --------------------------------------------------------------------------- 入口


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="ZeroTab 应用图标渲染器")
    parser.add_argument("--concepts", action="store_true", help="生成候选方案预览")
    parser.add_argument("--final", metavar="CONCEPT", nargs="?", const=RECOMMENDED,
                        help="产出 Resources/AppIcon.{icns,png,svg}")
    parser.add_argument("--preview", action="store_true", help="生成预览图")
    parser.add_argument("--no-icns", action="store_true", help="跳过 icns 生成")
    args = parser.parse_args(argv)

    did_something = False
    if args.final:
        concept = args.final
        if concept not in SYMBOLS:
            parser.error(f"未知方案 {concept}，可选：{', '.join(CONCEPTS)}")
        master = render_master(concept)
        write_png(master, RESOURCES / "AppIcon-1024.png")
        print(f"PNG  Resources/AppIcon-1024.png  (1024x1024)")
        if not args.no_icns:
            write_icns(master, RESOURCES / "AppIcon.icns")
            print(f"ICNS Resources/AppIcon.icns  ({len(ICNS_ENTRIES)} 个尺寸)")
        write_svg(concept, RESOURCES / "AppIcon.svg")
        print(f"SVG  Resources/AppIcon.svg  (方案 {concept})")
        did_something = True

    if args.concepts or args.preview:
        out = preview_sheet()
        print(f"预览 {out.relative_to(ROOT)}")
        did_something = True

    if not did_something:
        parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
