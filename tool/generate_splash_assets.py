from __future__ import annotations

from pathlib import Path

from PIL import Image


REPO = Path(__file__).resolve().parents[1]
ASSETS_DIR = REPO / "assets" / "images"
ANDROID_RES = REPO / "android" / "app" / "src" / "main" / "res"
IOS_ASSETS = REPO / "ios" / "Runner" / "Assets.xcassets"
IOS_LAUNCH_IMAGESET = IOS_ASSETS / "LaunchImage.imageset"
IOS_LAUNCH_BACKGROUND = IOS_ASSETS / "LaunchBackground.imageset" / "background.png"

SOURCE_SPLASH = ASSETS_DIR / "The Vault in metallic pink glow.png"
SOURCE_ANDROID12_ICON = ASSETS_DIR / "ic_launcher_vault_foreground.png"

ANDROID_SPLASH_SIZES = {
    "drawable-mdpi": (384, 256),
    "drawable-hdpi": (576, 384),
    "drawable-xhdpi": (768, 512),
    "drawable-xxhdpi": (1152, 768),
    "drawable-xxxhdpi": (1536, 1024),
}

IOS_SPLASH_SIZES = {
    "LaunchImage.png": (384, 256),
    "LaunchImage@2x.png": (768, 512),
    "LaunchImage@3x.png": (1152, 768),
}

BACKGROUND_COLOR = (0, 0, 0, 255)


def _require(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required splash asset not found: {path}")
    return path


def _resize_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    src_w, src_h = image.size
    dst_w, dst_h = size
    scale = max(dst_w / src_w, dst_h / src_h)
    scaled = image.resize(
        (max(1, round(src_w * scale)), max(1, round(src_h * scale))),
        Image.Resampling.LANCZOS,
    )
    left = max(0, (scaled.width - dst_w) // 2)
    top = max(0, (scaled.height - dst_h) // 2)
    return scaled.crop((left, top, left + dst_w, top + dst_h))


def _render_android12_icon(size: tuple[int, int], icon: Image.Image) -> Image.Image:
    width, height = size
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    inset = 0.58
    icon_size = max(1, round(min(width, height) * inset))
    rendered = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    x = (width - icon_size) // 2
    y = (height - icon_size) // 2
    canvas.alpha_composite(rendered, dest=(x, y))
    return canvas


def _save_png(target: Path, image: Image.Image) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, format="PNG")


def generate_android_splash() -> None:
    splash_source = Image.open(_require(SOURCE_SPLASH)).convert("RGBA")
    android12_icon = Image.open(_require(SOURCE_ANDROID12_ICON)).convert("RGBA")

    background = Image.new("RGBA", (1, 1), BACKGROUND_COLOR)
    _save_png(ANDROID_RES / "drawable" / "background.png", background)
    _save_png(ANDROID_RES / "drawable-v21" / "background.png", background)

    for folder, size in ANDROID_SPLASH_SIZES.items():
        splash_image = _resize_cover(splash_source, size)
        _save_png(ANDROID_RES / folder / "splash.png", splash_image)

        android12_image = _render_android12_icon(size, android12_icon)
        _save_png(ANDROID_RES / folder / "android12splash.png", android12_image)
        _save_png(ANDROID_RES / folder.replace("drawable", "drawable-night") / "android12splash.png", android12_image)


def generate_ios_splash() -> None:
    splash_source = Image.open(_require(SOURCE_SPLASH)).convert("RGBA")
    background = Image.new("RGBA", (1, 1), BACKGROUND_COLOR)
    _save_png(IOS_LAUNCH_BACKGROUND, background)

    for filename, size in IOS_SPLASH_SIZES.items():
        _save_png(IOS_LAUNCH_IMAGESET / filename, _resize_cover(splash_source, size))


def main() -> None:
    generate_android_splash()
    generate_ios_splash()
    print(f"Generated splash assets from {SOURCE_SPLASH}")


if __name__ == "__main__":
    main()
