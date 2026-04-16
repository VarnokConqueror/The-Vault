from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageColor, ImageDraw


REPO = Path(__file__).resolve().parents[1]
ASSETS_DIR = REPO / "assets" / "images"
ANDROID_RES = REPO / "android" / "app" / "src" / "main" / "res"
IOS_ICONSET = REPO / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WEB_DIR = REPO / "web"
WINDOWS_ICON = REPO / "windows" / "runner" / "resources" / "app_icon.ico"
SOURCE_CROWN_PNG = ASSETS_DIR / "The Vault Crown.png"
SOURCE_WINDOWS_PNG = ASSETS_DIR / "The Vault Crown Windows.png"
SOURCE_WINDOWS_ICO = ASSETS_DIR / "vault_win_master.ico"
SOURCE_IOS_PNG = ASSETS_DIR / "The Vault Crown iOS.png"
SOURCE_CROWN_SVG = ASSETS_DIR / "The Vault Crown.svg"
SHIELD_SVG = REPO / "assets" / "brand" / "vault_shield.svg"
FALLBACK_SVG = (
    SOURCE_CROWN_SVG
    if SOURCE_CROWN_SVG.exists()
    else SHIELD_SVG
    if SHIELD_SVG.exists()
    else REPO / "assets" / "brand" / "vault_crown.svg"
)
SVG_NS = {"svg": "http://www.w3.org/2000/svg"}
INKSCAPE_NS = "http://www.inkscape.org/namespaces/inkscape"


def _best_raster_source() -> Path | None:
    candidates = [SOURCE_WINDOWS_PNG, SOURCE_IOS_PNG, SOURCE_CROWN_PNG]
    existing = [path for path in candidates if path.exists()]
    if not existing:
        return None

    def area(path: Path) -> int:
        with Image.open(path) as image:
            return image.width * image.height

    return max(existing, key=area)


def _parse_style(style: str | None) -> dict[str, str]:
    if not style:
        return {}
    entries: dict[str, str] = {}
    for part in style.split(";"):
        if ":" not in part:
            continue
        key, value = part.split(":", 1)
        entries[key.strip()] = value.strip()
    return entries


def _resolve_fill(element: ET.Element, default: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    style = _parse_style(element.attrib.get("style"))
    fill = element.attrib.get("fill") or style.get("fill")
    if not fill or fill.lower() == "none":
        return default
    rgb = ImageColor.getrgb(fill)
    opacity = element.attrib.get("fill-opacity") or style.get("fill-opacity") or "1"
    alpha = round(float(opacity) * 255)
    return (*rgb, alpha)


def _transform(x: float, y: float, scale: float, offset_x: float, offset_y: float) -> tuple[float, float]:
    return (x * scale) + offset_x, (y * scale) + offset_y


def _parse_path_subpaths(path_data: str) -> list[list[tuple[float, float]]]:
    tokens = re.findall(r"[MLZmlz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?", path_data)
    subpaths: list[list[tuple[float, float]]] = []
    current: list[tuple[float, float]] = []
    cursor = (0.0, 0.0)
    command = ""
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if re.fullmatch(r"[MLZmlz]", token):
            command = token
            index += 1
            if command in {"Z", "z"}:
                if current:
                    subpaths.append(current)
                    current = []
                continue
        if command in {"M", "m"}:
            x = float(tokens[index])
            y = float(tokens[index + 1])
            index += 2
            if command == "m":
                cursor = (cursor[0] + x, cursor[1] + y)
            else:
                cursor = (x, y)
            if current:
                subpaths.append(current)
            current = [cursor]
            command = "l" if command == "m" else "L"
            continue
        if command in {"L", "l"}:
            x = float(tokens[index])
            y = float(tokens[index + 1])
            index += 2
            if command == "l":
                cursor = (cursor[0] + x, cursor[1] + y)
            else:
                cursor = (x, y)
            current.append(cursor)
            continue
        raise ValueError(f"Unsupported SVG path command in source icon: {command!r}")
    if current:
        subpaths.append(current)
    return subpaths


def _render_icon_from_svg(size: int) -> Image.Image:
    background = (15, 15, 21, 255)
    image = Image.new("RGBA", (size, size), background)
    draw = ImageDraw.Draw(image)
    svg_root = ET.fromstring(FALLBACK_SVG.read_text(encoding="utf-8"))
    _, _, svg_width, svg_height = map(float, svg_root.attrib["viewBox"].split())
    scale = size / max(svg_width, svg_height)
    offset_x = (size - (svg_width * scale)) / 2
    offset_y = (size - (svg_height * scale)) / 2

    vector_layer = None
    for group in svg_root.findall(".//svg:g", SVG_NS):
        if group.attrib.get(f"{{{INKSCAPE_NS}}}label") == "Vector Trace":
            vector_layer = group
            break
    if vector_layer is None:
        raise ValueError(f"Vector Trace layer not found in {FALLBACK_SVG}")

    for rect in vector_layer.findall("svg:rect", SVG_NS):
        fill = _resolve_fill(rect, (243, 160, 255, 255))
        x = float(rect.attrib["x"])
        y = float(rect.attrib["y"])
        width = float(rect.attrib["width"])
        height = float(rect.attrib["height"])
        ry = float(rect.attrib.get("ry", rect.attrib.get("rx", "0")))
        left, top = _transform(x, y, scale, offset_x, offset_y)
        right, bottom = _transform(x + width, y + height, scale, offset_x, offset_y)
        radius = ry * scale
        draw.rounded_rectangle((left, top, right, bottom), radius=radius, fill=fill)

    for path in vector_layer.findall("svg:path", SVG_NS):
        fill = _resolve_fill(path, (243, 160, 255, 255))
        subpaths = _parse_path_subpaths(path.attrib["d"])
        if not subpaths:
            continue
        first = [_transform(x, y, scale, offset_x, offset_y) for x, y in subpaths[0]]
        draw.polygon(first, fill=fill)
        for hole in subpaths[1:]:
            hole_points = [_transform(x, y, scale, offset_x, offset_y) for x, y in hole]
            draw.polygon(hole_points, fill=background)
    return image


def render_icon(size: int) -> Image.Image:
    raster_source = _best_raster_source()
    if raster_source is not None:
        return Image.open(raster_source).convert("RGBA").resize(
            (size, size),
            Image.Resampling.LANCZOS,
        )
    return _render_icon_from_svg(size)


def _save_png(target: Path, image: Image.Image, size: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    output = image.resize((size, size), Image.Resampling.LANCZOS)
    output.save(target, format="PNG")


def _make_adaptive_foreground(master: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset_scale = 0.68
    foreground_size = max(1, round(size * inset_scale))
    foreground = master.resize(
        (foreground_size, foreground_size),
        Image.Resampling.LANCZOS,
    )
    offset = ((size - foreground_size) // 2, (size - foreground_size) // 2)
    canvas.alpha_composite(foreground, dest=offset)
    return canvas


def generate_android_icons(master: Image.Image) -> None:
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in sizes.items():
        _save_png(ANDROID_RES / folder / "ic_launcher.png", master, size)
        _save_png(ANDROID_RES / folder / "ic_launcher_round.png", master, size)


def generate_ios_icons(master: Image.Image) -> None:
    contents = json.loads((IOS_ICONSET / "Contents.json").read_text(encoding="utf-8"))
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        size = float(image["size"].split("x")[0])
        scale = int(image["scale"].replace("x", ""))
        pixels = int(round(size * scale))
        _save_png(IOS_ICONSET / filename, master, pixels)


def generate_web_icons(master: Image.Image) -> None:
    _save_png(WEB_DIR / "favicon.png", master, 64)
    _save_png(WEB_DIR / "icons" / "Icon-192.png", master, 192)
    _save_png(WEB_DIR / "icons" / "Icon-512.png", master, 512)
    _save_png(WEB_DIR / "icons" / "Icon-maskable-192.png", master, 192)
    _save_png(WEB_DIR / "icons" / "Icon-maskable-512.png", master, 512)


def generate_windows_icons(master: Image.Image) -> None:
    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
    if SOURCE_WINDOWS_ICO.exists():
        shutil.copyfile(SOURCE_WINDOWS_ICO, WINDOWS_ICON)
        return
    master.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    master = render_icon(1024)
    brand_dir = REPO / "assets" / "brand"
    brand_dir.mkdir(parents=True, exist_ok=True)
    master_path = brand_dir / "vault_icon_master.png"
    reference_path = brand_dir / "vault_icon_reference.png"
    master.save(master_path, format="PNG")
    master.save(reference_path, format="PNG")
    generate_android_icons(master)
    _save_png(
        ANDROID_RES / "drawable-nodpi" / "ic_launcher_foreground_image.png",
        _make_adaptive_foreground(master, 432),
        432,
    )
    generate_ios_icons(master)
    generate_web_icons(master)
    generate_windows_icons(master)
    print(f"Generated app icons from {master_path}")


if __name__ == "__main__":
    main()
