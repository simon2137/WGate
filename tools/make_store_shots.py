"""Assemble the store screenshots for the three UI languages the app ships:
简体中文 (zh), 繁體中文 (zh-Hant) and English (en).

Each language gets, under signing/agc-assets/screenshots/<lang>/:
  phone/01–05.png    1080x1920, the 1280x2832 capture centred on its own background
  tablet/01–05.png   1920x1280, the 2880x1920 capture scaled down (3:2, no crop)
  pc/01–05.png       1920x1080, the app window cropped to 16:9

AppGallery asks for exactly those three shapes, so the assembler produces them
instead of leaving the devices' native sizes in the folder.

The captures themselves live in build/store/<device>-<frame>.jpeg (zh) and
<device>-{en,hant}-<nn>.jpeg (the other two languages).
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / 'build/store'
OUT = ROOT / 'signing/agc-assets/screenshots'

# the 16:9 region inside the 2in1 window (left, top, right, bottom), device pixels
PC_BOX = (523, 287, 2890, 1618)

PHONE = (1080, 1920)
TABLET = (1920, 1280)
PC = (1920, 1080)

# the five frames, in listing order
FRAMES = ['01-add', '02-auto', '03-settings', '04-appearance', '05-theme']

# language folder -> suffix the capture files carry
LANGS = {'zh': '', 'zh-Hant': '-hant', 'en': '-en'}

DEVICE_LABEL = {'phone': '手机', 'tablet': '平板', 'pc': '电脑'}
LANG_LABEL = {'zh': '简体中文', 'zh-Hant': '繁體中文', 'en': 'English'}


def font(size: int):
    for name in ('msyh.ttc', 'msyhbd.ttc'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def source(lang: str, device: str, frame: str) -> Path:
    suffix = LANGS[lang]
    if suffix:
        # english / traditional captures are numbered only: phone-en-01.jpeg
        return STORE / f'{device}{suffix}-{frame[:2]}.jpeg'
    return STORE / f'{device}-{frame}.jpeg'


def fill(image: Image.Image, size: tuple) -> Image.Image:
    """Fit the shot inside `size`, centred, on a canvas of its own background."""
    width, height = size
    canvas = Image.new('RGB', size, image.getpixel((4, 4))[:3])
    scale = min(width / image.size[0], height / image.size[1])
    small = image.convert('RGB').resize(
        (round(image.size[0] * scale), round(image.size[1] * scale)), Image.LANCZOS)
    canvas.paste(small, ((width - small.size[0]) // 2, (height - small.size[1]) // 2))
    return canvas


def main() -> None:
    for lang in LANGS:
        rows = []
        for device in ('phone', 'tablet', 'pc'):
            folder = OUT / lang / device
            folder.mkdir(parents=True, exist_ok=True)
            frames = []
            for index, frame in enumerate(FRAMES, start=1):
                path = source(lang, device, frame)
                if not path.exists():
                    raise SystemExit(f'missing capture: {path}')
                image = Image.open(path).convert('RGB')
                if device == 'pc':
                    out = image.crop(PC_BOX).resize(PC, Image.LANCZOS)
                elif device == 'tablet':
                    out = image.resize(TABLET, Image.LANCZOS)
                else:
                    out = fill(image, PHONE)
                out.save(folder / f'{index:02d}.png', 'PNG')
                frames.append(out)
                print(f'{lang}/{device}/{index:02d}.png  {out.size[0]}x{out.size[1]}')
            rows.append((device, frames))

        # contact sheet: one row per device, all thumbnails the same height
        height = 300
        pad, gap, label_w = 20, 14, 96
        width = label_w + len(FRAMES) * (int(height * 16 / 9) + gap) + gap + 200
        sheet = Image.new('RGB', (width, len(rows) * (height + 46) + pad * 2), (238, 240, 243))
        draw = ImageDraw.Draw(sheet)
        draw.text((pad, pad - 4), f'WGate · {LANG_LABEL[lang]}', fill=(40, 48, 56), font=font(20))
        for r, (device, frames) in enumerate(rows):
            top = pad + 28 + r * (height + 46)
            draw.text((pad, top + height // 2 - 8), DEVICE_LABEL[device],
                      fill=(40, 48, 56), font=font(22))
            x = label_w
            for frame in frames:
                w = int(height * frame.size[0] / frame.size[1])
                thumb = frame.resize((w, height), Image.LANCZOS)
                sheet.paste(thumb, (x, top))
                draw.rectangle([x, top, x + w, top + height], outline=(205, 210, 216))
                x += w + gap
        out = STORE / f'contact-sheet-{lang}.png'
        sheet.save(out)
        print(out)


if __name__ == '__main__':
    main()
