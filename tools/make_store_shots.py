"""Assemble the store screenshots: crop the PC shots to the app window, copy every
device's five frames into signing/agc-assets/screenshots/<device>/, and build a
contact sheet for review and for the chat."""

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / 'build/store'
OUT = ROOT / 'signing/agc-assets/screenshots'
PC_BOX = (532, 287, 2594, 1672)

SETS = {
    'phone': ['phone-01-add', 'phone-02-auto', 'phone-03-settings',
              'phone-04-appearance', 'phone-05-theme'],
    'tablet': ['tablet-01-add', 'tablet-02-auto', 'tablet-03-settings',
               'tablet-04-appearance', 'tablet-05-theme'],
    'pc': ['pc-01-add', 'pc-02-auto', 'pc-04-appearance',
           'pc-05-theme', 'pc-06-notifications'],
}

LABELS = ['添加隧道', '自动隧道', '设置 / 外观', '外观 / 主题', '主题 / 通知']


def font(size: int):
    for name in ('msyh.ttc', 'msyhbd.ttc'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def crop_pc(name: str) -> Image.Image:
    return Image.open(STORE / f'{name}.jpeg').crop(PC_BOX)


def main() -> None:
    rows = []
    for device, names in SETS.items():
        folder = OUT / device
        folder.mkdir(parents=True, exist_ok=True)
        frames = []
        for index, name in enumerate(names, start=1):
            image = crop_pc(name) if device == 'pc' else Image.open(STORE / f'{name}.jpeg')
            target = folder / f'{index:02d}.png'
            image.convert('RGB').save(target, 'PNG')
            frames.append(image)
            print(f'{target.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}')
        rows.append((device, frames))

    # contact sheet: one row per device, every frame at the same height
    height = 300
    pad, gap, label_w = 20, 14, 96
    width = label_w + len(LABELS) * (int(height * 16 / 9) + gap) + gap + 260
    sheet = Image.new('RGB', (width, len(rows) * (height + 46) + pad * 2), (238, 240, 243))
    draw = ImageDraw.Draw(sheet)
    for r, (device, frames) in enumerate(rows):
        top = pad + r * (height + 46)
        draw.text((pad, top + height // 2 - 8), {'phone': '手机', 'tablet': '平板', 'pc': '电脑'}[device],
                  fill=(40, 48, 56), font=font(22))
        x = label_w
        for frame in frames:
            w = int(height * frame.size[0] / frame.size[1])
            thumb = frame.resize((w, height), Image.LANCZOS)
            sheet.paste(thumb, (x, top))
            draw.rectangle([x, top, x + w, top + height], outline=(205, 210, 216))
            x += w + gap
    out = ROOT / 'build/store/contact-sheet.png'
    sheet.save(out)
    print(out)


if __name__ == '__main__':
    main()
