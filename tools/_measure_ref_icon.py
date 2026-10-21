"""Measure the original Android launcher mark so a redesign can start from its
real geometry instead of an eyeballed copy."""
from PIL import Image
import numpy as np

im = Image.open(r'_ref_android/app/src/main/ic_launcher-playstore.png').convert('RGBA')
a = np.array(im)
m = (a[..., 0] > 150) & (a[..., 1] > 150) & (a[..., 2] > 150) & (a[..., 3] > 150)


def runs(y):
    xs = np.nonzero(m[y])[0]
    out = []
    if len(xs) == 0:
        return out
    s = p = xs[0]
    for x in xs[1:]:
        if x != p + 1:
            out.append((int(s), int(p)))
            s = x
        p = x
    out.append((int(s), int(p)))
    return out


for y in range(120, 400, 20):
    print(y, runs(y))

print('plate colour', im.getpixel((3, 3)), im.getpixel((256, 40)))
print('mark colour', im.getpixel((140, 300)))
