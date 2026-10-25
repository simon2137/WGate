"""The phone frames as 9:16, which is the ratio AppGallery asks for.

The capture is 1280x2832 (about 1:2.21). Rather than crop away the status bar or the
bottom bar, the frame is scaled to fit 1080x1920 and centred on a canvas filled with
the colour of its own top row, so nothing is lost and no letterbox band shows.
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'signing/agc-assets/screenshots/phone'
OUT = ROOT / 'signing/agc-assets/screenshots/phone-9x16'
W, H = 1080, 1920


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for shot in sorted(SRC.glob('*.png')):
        image = Image.open(shot).convert('RGB')
        scale = min(W / image.width, H / image.height)
        resized = image.resize((round(image.width * scale), round(image.height * scale)),
                               Image.LANCZOS)
        canvas = Image.new('RGB', (W, H), image.getpixel((4, 4)))
        canvas.paste(resized, ((W - resized.width) // 2, (H - resized.height) // 2))
        target = OUT / shot.name
        canvas.save(target, 'PNG')
        print(f'{target.relative_to(ROOT)}  {W}x{H}')


if __name__ == '__main__':
    main()
