"""Labelled comparison sheet for the icon variants (128 px row, 48 px row)."""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

BUILD = pathlib.Path('build/icon_candidates')
LABELS = {'v1': 'A  青绿隧道', 'v2': 'B  暗色隧道', 'v3': 'C  同心拱',
          'v4': 'D  盾牌', 'v5': 'E  平涂隧道', 'v6': 'F  浅色',
          'd1': 'G  龙印（大）', 'd2': 'H  龙印（青拱）', 'd3': 'I  龙印（白拱）',
          'd5': 'J  龙印（宽洞）'}
FONT = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 15)
CELL, PAD, TOP = 168, 14, 40


def main(names):
    width = PAD + len(names) * (CELL + PAD)
    sheet = Image.new('RGB', (width, TOP + CELL + 118), (244, 246, 247))
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(names):
        x = PAD + index * (CELL + PAD)
        big = Image.open(BUILD / f'{name}-128.png').convert('RGBA')
        sheet.paste(big, (x + (CELL - 128) // 2, TOP), big)
        small = Image.open(BUILD / f'{name}-48.png').convert('RGBA')
        sheet.paste(small, (x + (CELL - 48) // 2, TOP + 128 + 14), small)
        draw.text((x + 4, TOP + 128 + 14 + 48 + 10), LABELS.get(name, name), font=FONT,
                  fill=(30, 40, 44))
    out = pathlib.Path('build/icon_candidates/variants.png')
    sheet.save(out)
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1:] or ['v1', 'v2', 'v3', 'v4', 'v5', 'v6'])
