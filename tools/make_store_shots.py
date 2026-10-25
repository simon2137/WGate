"""Assemble the store screenshots for the three UI languages the app ships:
简体中文 (zh), 繁體中文 (zh-Hant) and English (en).

Each language gets, under signing/agc-assets/screenshots/<lang>/:
  phone/01–05.png        1280x2832, as captured
  phone-9x16/01–05.png   1080x1920, centred on the app's own background colour
  tablet/01–05.png       2880x1920
  pc/01–05.png           cropped to the app window

and a contact sheet in build/store/contact-sheet-<lang>.png for review.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / 'build/store'
OUT = ROOT / 'signing/agc-assets/screenshots'
PC_BOX = (532, 287, 2594, 1694)

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


def nine_sixteen(image: Image.Image) -> Image.Image:
    """Centre a phone frame on a 9:16 canvas filled with its own background."""
    width, height = 1080, 1920
    canvas = Image.new('RGB', (width, height), image.getpixel((4, 4))[:3])
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
                    image = image.crop(PC_BOX)
                image.save(folder / f'{index:02d}.png', 'PNG')
                frames.append(image)
                print(f'{lang}/{device}/{index:02d}.png  {image.size[0]}x{image.size[1]}')
            rows.append((device, frames))
            if device == 'phone':
                nine = OUT / lang / 'phone-9x16'
                nine.mkdir(parents=True, exist_ok=True)
                for index, image in enumerate(frames, start=1):
                    nine_sixteen(image).save(nine / f'{index:02d}.png', 'PNG')

        # contact sheet: one row per device
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
