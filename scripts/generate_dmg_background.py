from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 660
HEIGHT = 420


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica.ttc",
            ]
        )
    else:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica.ttc",
            ]
        )

    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue

    return ImageFont.load_default()


def main() -> None:
    output = Path(__file__).resolve().parent.parent / "Support" / "dmg-background.png"
    output.parent.mkdir(parents=True, exist_ok=True)

    image = Image.new("RGBA", (WIDTH, HEIGHT), "#0f172a")
    draw = ImageDraw.Draw(image)

    for y in range(HEIGHT):
        ratio = y / max(HEIGHT - 1, 1)
        red = int(18 + 22 * ratio)
        green = int(33 + 70 * ratio)
        blue = int(76 + 92 * ratio)
        draw.line((0, y, WIDTH, y), fill=(red, green, blue, 255))

    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((40, 18, 310, 270), fill=(76, 148, 255, 165))
    glow_draw.ellipse((360, 165, 620, 405), fill=(124, 92, 255, 120))
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(34)))

    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.rounded_rectangle((30, 28, WIDTH - 30, HEIGHT - 28), radius=28, fill=(255, 255, 255, 34))
    overlay_draw.rounded_rectangle((30, 28, WIDTH - 30, HEIGHT - 28), radius=28, outline=(255, 255, 255, 54), width=1)
    image = Image.alpha_composite(image, overlay)
    draw = ImageDraw.Draw(image)

    title_font = load_font(40, bold=True)
    subtitle_font = load_font(19)
    callout_font = load_font(18, bold=True)
    hint_font = load_font(16)

    draw.text((48, 48), "PinShot", font=title_font, fill=(255, 255, 255, 255))
    draw.text((48, 98), "Drag the app into Applications to install", font=subtitle_font, fill=(226, 232, 240, 255))
    draw.text((48, 128), "Screenshot, pin, OCR, and translate — right from your menu bar.", font=hint_font, fill=(203, 213, 225, 255))

    draw.rounded_rectangle((48, 170, 270, 236), radius=18, fill=(255, 255, 255, 42), outline=(255, 255, 255, 66))
    draw.text((72, 190), "1. Drag PinShot.app", font=callout_font, fill=(255, 255, 255, 255))

    draw.rounded_rectangle((396, 170, 612, 236), radius=18, fill=(255, 255, 255, 42), outline=(255, 255, 255, 66))
    draw.text((430, 190), "2. Drop here", font=callout_font, fill=(255, 255, 255, 255))

    arrow_y = 204
    arrow_start = (282, arrow_y)
    arrow_end = (384, arrow_y)
    draw.rounded_rectangle((arrow_start[0], arrow_y - 7, arrow_end[0], arrow_y + 7), radius=7, fill=(255, 255, 255, 224))
    draw.polygon(
        [
            (arrow_end[0], arrow_y - 22),
            (arrow_end[0] + 34, arrow_y),
            (arrow_end[0], arrow_y + 22),
        ],
        fill=(255, 255, 255, 224),
    )

    draw.text((48, 322), "Tip: launch once to grant Screen Recording and Accessibility permissions.", font=hint_font, fill=(226, 232, 240, 238))

    image.save(output)
    print(output)


if __name__ == "__main__":
    main()
