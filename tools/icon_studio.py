"""WGate icon studio: one plate, a few marks, judged in a launcher.

The original Android app draws one light shape, one weight, generous margins, on
a #21272A plate.  Every mark here keeps that language; only the idea changes.
Geometry is drawn at 4x and cut back with Lanczos so straight edges stay straight
and round caps stay round at 24 dp.

    python tools/icon_studio.py sheet          # build/icon-studio/sheet.png
    python tools/icon_studio.py launcher       # real-size context sheet
    python tools/icon_studio.py install <slug>
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import icon_geom  # noqa: E402  (the path has to be set first)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/icon-studio'
SIDE = 512
WORK = 4
PLATE = (0x21, 0x27, 0x2A, 255)      # Shark, the original launcher background
PLATE_RADIUS = 112
INK = (0xF2, 0xF2, 0xF4, 255)        # OffWhite, the original onSurface
AQUA = (0x76, 0xBE, 0xBD, 255)       # Aqua, the original primary


class Pen:
    """A white-on-black mask at WORK times the final size."""

    def __init__(self):
        self.image = Image.new('L', (SIDE * WORK, SIDE * WORK), 0)
        self.draw = ImageDraw.Draw(self.image)

    def dot(self, x, y, r, value=255):
        self.draw.ellipse([(x - r) * WORK, (y - r) * WORK,
                           (x + r) * WORK, (y + r) * WORK], fill=value)

    def quad(self, points, value=255):
        self.draw.polygon([(x * WORK, y * WORK) for x, y in points], fill=value)

    def stroke(self, points, width, value=255, join='round', cap='round'):
        """One filled outline: round caps, round joints, no bulges."""
        path = icon_geom.outline(points, width, cap=cap, join=join)
        self.quad(path, value)

    def block(self, x0, y0, x1, y1, radius=16, value=255):
        self.draw.rounded_rectangle([x0 * WORK, y0 * WORK, x1 * WORK, y1 * WORK],
                                    radius=radius * WORK, fill=value)

    def shape(self, points, radius=20, value=255):
        """A filled polygon with rounded corners."""
        self.quad(icon_geom.rounded_polygon(points, radius), value)

    def lean(self, k):
        """Shear the mask itself, so the leaned mark is the drawn letter."""
        width, height = self.image.size
        pivot = SIDE / 2 * WORK
        self.image = self.image.transform(
            (width, height), Image.AFFINE,
            (1, -k, k * pivot, 0, 1, 0), resample=Image.BICUBIC)
        self.draw = ImageDraw.Draw(self.image)
        return self

    def done(self):
        return self.image.resize((SIDE, SIDE), Image.LANCZOS)


def smooth(points, steps=12):
    """Catmull-Rom through the points, for marks that should not have corners."""
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append((
                0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
                0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)))
    out.append(points[-1])
    return out


def scaled(points, factor, centre=(256, 256)):
    return [(centre[0] + (x - centre[0]) * factor,
             centre[1] + (y - centre[1]) * factor) for x, y in points]


def w_signature():
    """The original's three elements, re-spaced so nothing collides."""
    pen = Pen()
    pen.stroke([(120, 150), (206, 366)], 54)
    pen.stroke([(214, 150), (300, 366)], 54)
    pen.stroke([(306, 146), (404, 146), (330, 352)], 54, join='round')
    return pen.done()


def w_letter():
    """A type designer's W: one weight, lifted apex, wide stance."""
    pen = Pen()
    pen.stroke([(120, 146), (188, 366), (256, 198), (324, 366), (392, 146)], 62)
    return pen.done()


def w_heavy():
    """The same W with the weight turned up: one solid mass at 24 dp."""
    pen = Pen()
    pen.stroke([(116, 142), (186, 372), (256, 192), (326, 372), (396, 142)], 74)
    return pen.done()


def w_slab():
    """A gate slab with the W carved through it: the boldest read of all."""
    pen = Pen()
    pen.block(104, 118, 408, 396, 78)
    pen.stroke([(158, 180), (208, 336), (256, 218), (304, 336), (354, 180)], 42, 0)
    return pen.done()


def w_archline():
    """An arch and a W sharing one line: the gate and the letter at once."""
    pen = Pen()
    arch = [(112, 356), (112, 214)]
    for step in range(41):
        a = math.pi - math.pi * step / 40
        arch.append((256 + 144 * math.cos(a), 214 - 144 * math.sin(a) * 0.86))
    arch.append((400, 214))
    arch.append((400, 356))
    pen.stroke(arch, 34)
    pen.stroke([(164, 214), (210, 336), (256, 250), (302, 336), (348, 214)], 46)
    return pen.done()


def w_tunnel():
    """The W as a bore: outer strokes converge, the apex is the vanishing point."""
    pen = Pen()
    pen.stroke([(110, 150), (140, 230), (206, 366)], 58)
    pen.stroke([(206, 366), (256, 206)], 58)
    pen.stroke([(256, 206), (306, 366)], 58)
    pen.stroke([(306, 366), (372, 230), (402, 150)], 58)
    return pen.done()


LETTER = [(120, 146), (188, 366), (256, 198), (324, 366), (392, 146)]


def w_flat():
    """The letter cropped flat at the top and the feet: a stamped part."""
    pen = Pen()
    pen.stroke(LETTER, 62)
    pen.block(0, 0, SIDE, 150, 0, 0)
    pen.block(0, 380, SIDE, SIDE, 0, 0)
    return pen.done()


def w_stencil():
    """Two bridges cut straight across the outer strokes: steel plate, not ink."""
    pen = Pen()
    pen.stroke(LETTER, 62)
    pen.stroke([(40, 247), (232, 247)], 22, 0, cap='butt')
    pen.stroke([(280, 247), (472, 247)], 22, 0, cap='butt')
    return pen.done()


def w_italic():
    """The same letter, leaning: motion without adding a single element."""
    pen = Pen()
    pen.stroke(LETTER, 62)
    return pen.lean(0.16).done()


def w_stem():
    """Gate posts: the outer strokes start vertical, then take the W's angle."""
    pen = Pen()
    pen.stroke([(120, 146), (120, 186), (188, 366), (256, 198),
                (324, 366), (392, 186), (392, 146)], 62)
    return pen.done()


def w_hollow():
    """The letter drawn as a band: a frame that still spells W."""
    pen = Pen()
    pen.stroke(LETTER, 62)
    pen.stroke(LETTER, 18, 0)
    return pen.done()


def w_nest():
    """Three Ws receding into one another: the bore, seen straight on."""
    pen = Pen()
    base = [(140, 160), (196, 352), (256, 214), (316, 352), (372, 160)]
    for factor, width in ((1.0, 30), (1.17, 24), (1.34, 18)):
        pen.stroke(scaled(base, factor), width)
    return pen.done()


def w_wave():
    """A W without a single corner: the signal, not the letter."""
    pen = Pen()
    pen.stroke(smooth([(108, 160), (180, 344), (256, 212), (332, 344), (404, 160)]), 50)
    return pen.done()


def w_split():
    """The letter opened down the middle: the gate, drawn as the gap."""
    pen = Pen()
    pen.stroke(LETTER, 62)
    pen.block(239, 116, 273, 420, 17, 0)
    return pen.done()


def w_keel():
    """A short bar under the feet: the threshold the gate stands on."""
    pen = Pen()
    pen.stroke(LETTER, 58)
    pen.stroke([(206, 404), (306, 404)], 30)
    return pen.done()


def w_mega():
    """The loud one: weight and stance both at the limit of the margins."""
    pen = Pen()
    pen.stroke([(96, 138), (178, 378), (256, 186), (334, 378), (416, 138)], 88)
    return pen.done()


MARKS = [
    ('w-signature', '原味 W 精修', w_signature, INK),
    ('w-letter', '正体 W', w_letter, INK),
    ('w-heavy', '重体 W', w_heavy, INK),
    ('w-slab', 'W 反白门', w_slab, INK),
    ('w-archline', '拱线 W', w_archline, INK),
    ('w-tunnel', '隧道 W', w_tunnel, INK),
    ('w-letter-aqua', '正体 W · 青', w_letter, AQUA),
]

# The second round of ideas, drawn after the first seven were reviewed: each one
# changes a different thing -- the terminal, the surface, the whole, the depth,
# the corner, the gap, the base, the weight.
BATCH5 = [
    ('w-flat', '切端 W', w_flat, INK),
    ('w-hollow', '空心 W', w_hollow, INK),
    ('w-wave', '无角 W', w_wave, INK),
    ('w-split', '开门 W', w_split, INK),
    ('w-mega', '极限 W', w_mega, INK),
    ('w-italic', '斜体 W', w_italic, INK),
    ('w-stem', '竖柱 W', w_stem, INK),
    ('w-stencil', '漏桥 W', w_stencil, INK),
]

def _arch(scale=1.0, feet=369, cy=326, half=145):
    """A tunnel mouth: legs, then a semicircle; scaled about its own feet."""
    cy = feet - (feet - cy) * scale
    r = half * scale
    pts = [(256 - r, feet), (256 - r, cy)]
    for step in range(31):
        a = math.pi - math.pi * step / 30
        pts.append((256 + r * math.cos(a), cy - r * math.sin(a)))
    pts += [(256 + r, cy), (256 + r, feet)]
    return pts


def n_arch():
    """The opening itself: one stroke, no letter, no lock."""
    pen = Pen()
    pen.stroke(_arch(), 62)
    return pen.done()


def n_doorway():
    """A wall with a doorway cut through it: the negative carries the idea."""
    pen = Pen()
    pen.block(104, 104, 408, 396, 80)
    pen.stroke([(256, 250), (256, 430)], 156, 0)
    return pen.done()


def n_arch_light():
    """The opening with a bar of light lying in it: someone is home."""
    pen = Pen()
    pen.stroke(_arch(), 62)
    pen.stroke([(188, 352), (324, 352)], 26)
    return pen.done()


def n_beam():
    """Light through a slot: a cone, the only diagonal in the family."""
    pen = Pen()
    pen.stroke([(150, 148), (362, 148)], 30)
    pen.quad([(236, 148), (276, 148), (370, 400), (142, 400)])
    return pen.done()


def n_nested():
    """Three arches receding: you are looking down the bore."""
    pen = Pen()
    for scale, width in ((1.0, 28), (0.70, 22), (0.42, 16)):
        pen.stroke(_arch(scale), width)
    return pen.done()


def n_corridor():
    """A light slit that narrows: the vanishing point, drawn as a gap."""
    pen = Pen()
    pen.block(84, 150, 428, 404, 40)
    pen.quad([(196, 470), (316, 470), (274, 140), (238, 140)], 0)
    return pen.done()


def n_keyhole():
    """The oldest lock in the world, at one weight: circle and shank."""
    pen = Pen()
    pen.dot(256, 208, 68)
    pen.stroke([(256, 236), (256, 392)], 80)
    return pen.done()


def n_frame():
    """Posts and a lintel: a gate seen from the front, nothing else."""
    pen = Pen()
    pen.block(120, 148, 392, 210, 22)
    pen.block(120, 148, 182, 404, 22)
    pen.block(330, 148, 392, 404, 22)
    return pen.done()


def n_potral():
    """A ring opened at the bottom: the mouth of the tunnel in plan view."""
    pen = Pen()
    pen.dot(256, 246, 150)
    pen.dot(256, 246, 86, 0)
    pen.block(60, 330, 452, 512, 0, 0)
    return pen.done()


def n_shield():
    """The oldest promise in the category, drawn as one mass and nothing else."""
    pen = Pen()
    pen.shape([(142, 152), (370, 152), (370, 262), (338, 330),
               (256, 404), (174, 330), (142, 262)], 18)
    return pen.done()


def n_route():
    """The line the tunnel takes: in, turn, out -- not a letter, a path."""
    pen = Pen()
    pen.stroke([(146, 400), (146, 300), (300, 300), (300, 198), (372, 198)], 74)
    return pen.done()


def n_door_tall():
    """The same doorway in a tall wall: architectural rather than graphic."""
    pen = Pen()
    pen.block(138, 88, 374, 424, 46)
    pen.stroke([(256, 232), (256, 460)], 122, 0)
    return pen.done()


def n_door_light():
    """The doorway with a bar of light lying on its sill: a way in, and someone home."""
    pen = Pen()
    pen.block(104, 104, 408, 396, 80)
    pen.stroke([(256, 250), (256, 430)], 156, 0)
    pen.block(212, 330, 300, 354, 12)
    return pen.done()


BATCH6 = [
    ('n-arch', '门拱', n_arch, INK),
    ('n-arch-light', '拱与光', n_arch_light, INK),
    ('n-doorway', '门洞', n_doorway, INK),
    ('n-beam', '光锥', n_beam, INK),
    ('n-keyhole', '锁孔', n_keyhole, INK),
    ('n-frame', '门框', n_frame, INK),
    ('n-corridor', '光缝', n_corridor, INK),
    ('n-portal', '环门', n_potral, INK),
    ('n-shield', '盾', n_shield, INK),
    ('n-route', '路径', n_route, INK),
    ('n-door-light', '门洞·光', n_door_light, INK),
    ('n-door-tall', '高门', n_door_tall, INK),
]

# Four things an icon for this product could be about, two drawings each.
FINAL = [
    ('n-door-light', '门洞 · 光', '墙里开一道拱门，门槛上一线光'),
    ('n-doorway', '门洞', '只有墙和开口，最简洁的一版'),
    ('n-door-tall', '高门', '竖长方墙、窄门洞，更像建筑而不是图形'),
    ('n-arch', '门拱', '只剩开口本身，一条线'),
    ('n-keyhole', '锁孔', '一眼就懂的安全，但最俗'),
    ('n-beam', '光锥', '一道光从门缝里洒下来'),
]
FAMILIES = [
    ('一 · 一个开口', [('n-doorway', '门洞'), ('n-arch', '门拱')]),
    ('二 · 一层守护', [('n-keyhole', '锁孔'), ('n-shield', '盾')]),
    ('三 · 一条通道', [('n-corridor', '光缝'), ('n-route', '路径')]),
    ('四 · 一束光', [('n-beam', '光锥'), ('n-arch-light', '拱与光')]),
]

def m_portal():
    """A hillside with a bore through it: the mass is the picture, not the line."""
    pen = Pen()
    pen.block(78, 232, 434, 404, 62)
    pen.stroke([(256, 340), (256, 452)], 142, 0)
    return pen.done()


def m_portal_ground():
    """The same bore with a ground line: a place, not a shape."""
    pen = Pen()
    pen.block(86, 150, 426, 372, 68)
    pen.stroke([(256, 268), (256, 420)], 138, 0)
    pen.block(60, 404, 452, 434, 15)
    return pen.done()


def m_dome():
    """A solid dome on a threshold bar: the gate in elevation."""
    pen = Pen()
    pen.dot(256, 300, 148)
    pen.block(96, 300, 416, 404, 0)
    pen.block(96, 300, 416, 404, 0)
    return pen.done()


def m_dome_nested():
    """A portal face with a second arch standing in its mouth: depth, one mass."""
    pen = Pen()
    pen.block(96, 116, 416, 404, 62)
    pen.stroke([(256, 258), (256, 470)], 172, 0)
    pen.stroke([(256, 300), (256, 470)], 94)
    pen.block(0, 404, SIDE, SIDE, 0, 0)
    return pen.done()


def m_double():
    """Two leaves and a lintel: a gate that is actually closed on one side."""
    pen = Pen()
    pen.block(92, 140, 416, 214, 26)
    pen.block(92, 140, 236, 404, 26)
    pen.block(272, 140, 416, 404, 26)
    return pen.done()


def m_transom():
    """A gate with a window over it: the opening and the light in one shape."""
    pen = Pen()
    pen.block(96, 112, 416, 404, 60)
    pen.stroke([(256, 268), (256, 448)], 148, 0)
    pen.block(168, 176, 344, 216, 20, 0)
    return pen.done()


def m_slash():
    """The wall cut on the diagonal: the one mark here with real speed."""
    pen = Pen()
    pen.block(100, 132, 412, 396, 66)
    pen.stroke([(120, 430), (392, 110)], 62, 0)
    return pen.done()


def m_horseshoe():
    """A ring opened at the foot: the mouth, seen head on, with two jambs."""
    pen = Pen()
    pen.dot(256, 258, 150)
    pen.dot(256, 258, 88, 0)
    pen.block(60, 344, 452, 520, 0, 0)
    return pen.done()


def m_dots():
    """Two ends of a tunnel with the bore between them: a link, not an object."""
    pen = Pen()
    pen.dot(148, 300, 46)
    pen.dot(364, 300, 46)
    pen.stroke([(148, 300), (364, 300)], 34)
    pen.block(238, 150, 274, 450, 0, 0)
    return pen.done()


BATCH7 = [
    ('m-portal', '隧道口', m_portal, INK),
    ('m-portal-ground', '隧道口 · 地', m_portal_ground, INK),
    ('m-dome-nested', '深拱', m_dome_nested, INK),
    ('m-slash', '斜切', m_slash, INK),
    ('n-doorway', '门洞', n_doorway, INK),
    ('n-arch', '门拱', n_arch, INK),
    ('n-keyhole', '锁孔', n_keyhole, INK),
    ('m-double', '对开门', m_double, INK),
]

def t_door():
    """门洞：墙是白的，门槛上那道光是青的。"""
    pen = Pen()
    pen.block(104, 104, 408, 396, 80)
    pen.stroke([(256, 250), (256, 430)], 156, 0)
    light = Pen()
    light.block(214, 330, 298, 356, 13)
    return pen.done(), light.done()


def t_arch():
    """门拱：拱是白的，拱洞里那一点光是青的。"""
    pen = Pen()
    pen.stroke(_arch(), 62)
    light = Pen()
    light.dot(256, 348, 30)
    return pen.done(), light.done()


def t_nested():
    """深拱：外圈白，里圈青——隧道尽头的那一层。"""
    pen = Pen()
    pen.block(96, 116, 416, 404, 62)
    pen.stroke([(256, 258), (256, 470)], 172, 0)
    pen.block(0, 404, SIDE, SIDE, 0, 0)
    light = Pen()
    light.stroke([(256, 300), (256, 470)], 90)
    light.block(0, 404, SIDE, SIDE, 0, 0)
    return pen.done(), light.done()


def t_portal():
    """隧道口：山体白，洞里一线青光。"""
    pen = Pen()
    pen.block(78, 232, 434, 404, 62)
    pen.stroke([(256, 340), (256, 452)], 142, 0)
    light = Pen()
    light.block(200, 372, 312, 396, 12)
    return pen.done(), light.done()


BATCH8 = [
    ('t-door', '门洞 · 青门槛', t_door, INK),
    ('t-arch', '门拱 · 青光点', t_arch, INK),
    ('t-nested', '深拱 · 青内圈', t_nested, INK),
    ('t-portal', '隧道口 · 青地光', t_portal, INK),
    ('n-door-light', '门洞 · 白门槛', n_door_light, INK),
    ('n-doorway', '门洞 · 纯白', n_doorway, INK),
    ('n-arch', '门拱 · 纯白', n_arch, INK),
    ('n-keyhole', '锁孔 · 纯白', n_keyhole, INK),
]

def big_door():
    """The gate as a white slab: the wall becomes the plate, the doorway the hole."""
    pen = Pen()
    pen.block(58, 58, 454, 454, 92)
    pen.stroke([(256, 222), (256, 500)], 188, 0)
    return pen.done()


def big_arch():
    """The opening at plate scale: no wall, no keyhole, just the way through."""
    pen = Pen()
    pen.stroke(_arch(feet=470, cy=330, half=196), 96)
    return pen.done()


def big_keyhole():
    """The lock at plate scale: the whole icon is one hole."""
    pen = Pen()
    pen.dot(256, 206, 112)
    pen.stroke([(256, 258), (256, 470)], 138)
    return pen.done()


def big_portal():
    """The bore at plate scale with the light bar left in it."""
    pen = Pen()
    pen.block(46, 130, 466, 466, 98)
    pen.stroke([(256, 300), (256, 500)], 208, 0)
    light = Pen()
    light.block(176, 392, 336, 424, 16)
    return pen.done(), light.done()


BATCH9 = [
    ('big-door', '大门洞', big_door, INK),
]

ALL = MARKS + BATCH5 + BATCH6 + BATCH7 + BATCH8 + BATCH9
MARKS_BY_SLUG = {slug: (draw, ink) for slug, _, draw, ink in ALL}


def plate():
    image = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
    ImageDraw.Draw(image).rounded_rectangle(
        [0, 0, SIDE - 1, SIDE - 1], PLATE_RADIUS, fill=PLATE)
    return image


def tray_mark_door():
    """台面图标：主图标的门洞和门槛，合成一个字形。

    门槛跟着字形同色——浅色状态栏上它就是黑的，深色栏上是白的，那道线才不会在
    其中一种主题里消失。字形本身由 make_tray_icons.py 放大到接近占满画框。
    """
    pen = Pen()
    pen.block(104, 104, 408, 396, 80)
    pen.stroke([(256, 250), (256, 430)], 156, 0)
    door = pen.done()
    bar = Pen()
    bar.block(214, 330, 298, 356, 13)
    door.paste(255, (0, 0), bar.done())
    return door


def tray_mark_arch():
    """状态栏的轻量版：只有那道门洞，没有墙。"""
    pen = Pen()
    pen.stroke([(256, 296), (256, 430)], 212)
    pen.block(0, 396, SIDE, SIDE, 0, 0)
    return pen.done()


# Marks whose status-bar glyph is not what the brightness crop would find: the
# icon's own silhouette (a slab with a hole) makes a heavier glyph, so install()
# writes it to build/icon-studio/tray-mark.png instead, and deletes that file for
# marks that need nothing special.  tools/make_tray_icons.py follows whichever
# icon is installed.
TRAY_MARKS = {'t-door': tray_mark_door}


def compose(mask, ink=INK, accent=AQUA):
    """Paint a mark on the plate; a mark may come as (structure, light)."""
    main, light = mask if isinstance(mask, tuple) else (mask, None)
    image = plate()
    image.paste(Image.new('RGBA', (SIDE, SIDE), ink), (0, 0), main)
    if light is not None:
        image.paste(Image.new('RGBA', (SIDE, SIDE), accent), (0, 0), light)
    return image


# The shortlist to choose from: everything that survived four rounds.
DECIDE = [
    ('n-doorway', '1 门洞'),
    ('t-door', '2 门洞·青门槛'),
    ('m-portal-ground', '3 隧道口·地'),
    ('n-arch', '4 门拱'),
    ('t-nested', '5 深拱·青内圈'),
    ('big-door', '6 大门洞'),
    ('n-keyhole', '7 锁孔'),
    ('m-slash', '8 斜切'),
]


def decide():
    marks = [(slug, label, MARKS_BY_SLUG[slug][0], MARKS_BY_SLUG[slug][1])
             for slug, label in DECIDE]
    sheet(marks, 'decide')
    launcher(marks, 'launcher-decide')


def font(size):
    for name in ('msyh.ttc', 'segoeui.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def sheet(marks=None, name='sheet'):
    marks = MARKS if marks is None else marks
    OUT.mkdir(parents=True, exist_ok=True)
    big, mid, small = 168, 48, 24
    pad, top = 22, 40
    width = pad + len(marks) * (big + pad)
    height = top + big + 34 + mid + 22 + small + 44
    canvas = Image.new('RGB', (width, height), (244, 246, 247))
    draw = ImageDraw.Draw(canvas)
    for i, (slug, label, fn, ink) in enumerate(marks):
        art = compose(fn(), ink)
        x = pad + i * (big + pad)
        large = art.resize((big, big), Image.LANCZOS)
        canvas.paste(large, (x, top), large)
        draw.text((x, top + big + 10), label, fill=(24, 24, 27, 255), font=font(15))
        medium = art.resize((mid, mid), Image.LANCZOS)
        canvas.paste(medium, (x, top + big + 40), medium)
        tiny = art.resize((small, small), Image.LANCZOS)
        canvas.paste(tiny, (x + mid + 16, top + big + 52), tiny)
        art.save(OUT / f'{slug}-512.png', 'PNG', optimize=True)
    path = OUT / f'{name}.png'
    canvas.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B  ({width}x{height})')


def launcher(marks=None, name='launcher'):
    """The marks at launcher size on a dark home screen, not on white paper."""
    marks = MARKS if marks is None else marks
    OUT.mkdir(parents=True, exist_ok=True)
    cell = 148
    width, height = cell * len(marks), 380
    screen = Image.new('RGB', (width, height))
    for y in range(height):
        t = y / height
        screen.paste(tuple(int(c * (0.55 + 0.45 * t)) for c in (34, 38, 46)),
                     [0, y, width, y + 1])
    draw = ImageDraw.Draw(screen)
    for i, (slug, label, fn, ink) in enumerate(marks):
        art = compose(fn(), ink)
        x = i * cell + (cell - 112) // 2
        big = art.resize((112, 112), Image.LANCZOS)
        screen.paste(big, (x, 48), big)
        draw.text((i * cell + 10, 176), label, fill=(226, 232, 238, 255), font=font(14))
        small = art.resize((48, 48), Image.LANCZOS)
        screen.paste(small, (i * cell + 12, 212), small)
        tiny = art.resize((24, 24), Image.LANCZOS)
        screen.paste(tiny, (i * cell + 74, 224), tiny)
    path = OUT / f'{name}.png'
    screen.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B')


def treatments(slug='w-letter'):
    """One mark, four surfaces: how much does the plate carry the brand?"""
    OUT.mkdir(parents=True, exist_ok=True)
    draw, _ = MARKS_BY_SLUG[slug]
    mask = draw()
    plates = [
        ('原盘 白标', PLATE, INK),
        ('原盘 青标', PLATE, AQUA),
        ('浅盘 深标', (0xF2, 0xF2, 0xF4, 255), (0x21, 0x27, 0x2A, 255)),
        ('深盘 青标', (0x1C, 0x1B, 0x1F, 255), AQUA),
    ]
    big, pad, top = 150, 20, 46
    canvas = Image.new('RGB', (pad + len(plates) * (big + pad), top + big + 60), (245, 246, 247))
    goto = ImageDraw.Draw(canvas)
    for i, (label, base, ink) in enumerate(plates):
        image = Image.new('RGBA', (SIDE, SIDE), (0, 0, 0, 0))
        ImageDraw.Draw(image).rounded_rectangle(
            [0, 0, SIDE - 1, SIDE - 1], PLATE_RADIUS, fill=base)
        image.paste(Image.new('RGBA', (SIDE, SIDE), ink), (0, 0), mask)
        art = image.resize((big, big), Image.LANCZOS)
        x = pad + i * (big + pad)
        canvas.paste(art, (x, top), art)
        goto.text((x, top + big + 12), label, fill=(24, 24, 27), font=font(14))
        image.save(OUT / f'{slug}-{i}.png', 'PNG', optimize=True)
    path = OUT / 'treatments.png'
    canvas.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B')


CHOICE = [
    ('A', 'w-letter', '正体 W', '一个笔宽、圆头、中峰抬起；最稳，什么尺寸都不失手'),
    ('B', 'w-wave', '无角 W', '连续曲线，没有一个尖角；柔和、有机，像信号波形'),
    ('C', 'w-stem', '竖柱 W', '外笔起头先竖一段再折；读作门柱，是这批里最"建筑"的'),
    ('D', 'w-mega', '极限 W', '笔宽 88 顶到留白上限；24px 最凶，几乎没有中宫'),
    ('E', 'w-italic', '斜体 W', '整体右倾 16%；不加任何元素就有动势，像穿过隧道'),
    ('F', 'w-slab', '反白门', '白碑上刻 W；明暗颠倒，货架上最抓眼'),
    ('G', 'w-hollow', '空心 W', '只画轮廓的带子；最轻，但 24px 会发虚'),
    ('H', 'w-flat', '切端 W', '方头端帽代替圆头；机械、克制，像冲压件'),
]


def families(name='families'):
    """The four readings of the product, two drawings each."""
    OUT.mkdir(parents=True, exist_ok=True)
    cell, big, gap, pad = 322, 128, 22, 24
    width = pad + len(FAMILIES) * cell
    height = pad + 30 + big + 26 + 26 + pad
    canvas = Image.new('RGB', (width, height), (245, 246, 247))
    goto = ImageDraw.Draw(canvas)
    for column, (title, marks) in enumerate(FAMILIES):
        x = pad + column * cell
        goto.text((x, pad), title, fill=(110, 118, 128), font=font(17))
        for row, (slug, label) in enumerate(marks):
            draw, ink = MARKS_BY_SLUG[slug]
            art = compose(draw(), ink)
            ictx = x + row * (big + gap)
            large = art.resize((big, big), Image.LANCZOS)
            canvas.paste(large, (ictx, pad + 30), large)
            goto.text((ictx, pad + 30 + big + 6), label, fill=(24, 24, 27), font=font(13))
            tiny = art.resize((24, 24), Image.LANCZOS)
            canvas.paste(tiny, (ictx + 88, pad + 30 + big + 2), tiny)
    path = OUT / f'{name}.png'
    canvas.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B  ({width}x{height})')


def choice(name='choice'):
    """A through H on one board, on paper and in a launcher."""
    OUT.mkdir(parents=True, exist_ok=True)
    cell, pad = 150, 0
    width = cell * len(CHOICE)
    top_h, dark_h = 250, 250
    canvas = Image.new('RGB', (width, top_h + dark_h), (244, 246, 247))
    goto = ImageDraw.Draw(canvas)
    for i, (letter, slug, label, _note) in enumerate(CHOICE):
        draw, ink = MARKS_BY_SLUG[slug]
        art = compose(draw(), ink)
        x = i * cell
        goto.text((x + 12, 14), letter, fill=(120, 128, 138), font=font(20))
        large = art.resize((128, 128), Image.LANCZOS)
        canvas.paste(large, (x + 11, 46), large)
        goto.text((x + 12, 188), label, fill=(24, 24, 27), font=font(16))
        medium = art.resize((48, 48), Image.LANCZOS)
        canvas.paste(medium, (x + 12, 214), medium)
        tiny = art.resize((24, 24), Image.LANCZOS)
        canvas.paste(tiny, (x + 68, 226), tiny)
    # the same eight where they will actually live
    for y in range(top_h, top_h + dark_h):
        t = (y - top_h) / dark_h
        goto.line([(0, y), (width, y)],
                  fill=tuple(int(c * (0.72 - 0.16 * t)) for c in (34, 38, 46)))
    for i, (letter, slug, _label, _note) in enumerate(CHOICE):
        draw, ink = MARKS_BY_SLUG[slug]
        art = compose(draw(), ink)
        x = i * cell
        goto.text((x + 12, top_h + 14), letter, fill=(120, 132, 146), font=font(20))
        big = art.resize((112, 112), Image.LANCZOS)
        canvas.paste(big, (x + 19, top_h + 46), big)
    path = OUT / f'{name}.png'
    canvas.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B  ({width}x{top_h + dark_h})')


def sizes(slug='t-door'):
    """The shipped mark at every size the system actually asks for."""
    OUT.mkdir(parents=True, exist_ok=True)
    draw, ink = MARKS_BY_SLUG[slug]
    art = compose(draw(), ink)
    ladder = [256, 128, 96, 64, 48, 32, 24]
    width, height = 1200, 360
    board = Image.new('RGB', (width, height), (28, 27, 31))
    goto = ImageDraw.Draw(board)
    x = 40
    for size in ladder:
        tile = art.resize((size, size), Image.LANCZOS)
        board.paste(tile, (x, 150 - size // 2), tile)
        goto.text((x, 236), f'{size}', fill=(150, 158, 172), font=font(14))
        x += size + 26
    # the tray glyphs beside the ladder, on the bar they live in
    goto.text((40, 24), 'WGate 图标 · 各尺寸实际大小', fill=(226, 232, 238), font=font(18))
    tray = ROOT / 'entry/src/main/resources/base/media/tray_idle_light.png'
    if tray.exists():
        for i, name in enumerate(('tray_idle_light.png', 'tray_up_light.png')):
            image = Image.open(tray.parent / name).convert('RGBA')
            glyph = image.resize((48, 48), Image.LANCZOS)
            board.paste(glyph, (1000 + i * 80, 126), glyph)
        goto.text((1000, 190), '状态栏 24 vp', fill=(150, 158, 172), font=font(13))
    path = OUT / 'sizes.png'
    board.save(path)
    print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B')


def install(slug):
    entry = MARKS_BY_SLUG.get(slug)
    if entry is None:
        print('pick one of: ' + ', '.join(MARKS_BY_SLUG))
        return
    draw, ink = entry
    image = compose(draw(), ink)
    outs = [ROOT / 'AppScope/resources/base/media/app_icon.png',
            ROOT / 'entry/src/main/resources/base/media/app_icon.png']
    for path in outs:
        image.save(path, 'PNG', optimize=True)
        print(f'{path.relative_to(ROOT)}: {path.stat().st_size} B')

    # tools/make_tray_icons.py crops the status-bar glyph out of the app icon by
    # brightness; a mark whose white part is a slab would make a heavy glyph, so
    # such a mark hands over its own hole as build/icon-studio/tray-mark.png.
    tray_path = OUT / 'tray-mark.png'
    tray = TRAY_MARKS.get(slug)
    if tray is None:
        if tray_path.exists():
            tray_path.unlink()
        return
    mask = tray()
    glyph = Image.new('RGBA', (SIDE, SIDE), (0xFF, 0xFF, 0xFF, 0))
    glyph.putalpha(mask)
    glyph.save(tray_path, 'PNG', optimize=True)
    print(f'{tray_path.relative_to(ROOT)}: {tray_path.stat().st_size} B')


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'sheet'
    if cmd == 'install':
        install(sys.argv[2] if len(sys.argv) > 2 else '')
    elif cmd == 'launcher':
        launcher(MARKS, 'launcher')
    elif cmd == 'sheet5':
        sheet(BATCH5, 'sheet5')
    elif cmd == 'sheet6':
        sheet(BATCH6, 'sheet6')
    elif cmd == 'sheet7':
        sheet(BATCH7, 'sheet7')
        launcher(BATCH7, 'launcher7')
    elif cmd == 'sheet8':
        sheet(BATCH8, 'sheet8')
        launcher(BATCH8, 'launcher8')
    elif cmd == 'sheet9':
        sheet(BATCH9, 'sheet9')
        launcher(BATCH9, 'launcher9')
    elif cmd == 'decide':
        decide()
    elif cmd == 'launcher6':
        launcher(BATCH6, 'launcher6')
    elif cmd == 'launcher5':
        launcher(BATCH5, 'launcher5')
    elif cmd == 'all':
        sheet(ALL, 'all')
    elif cmd == 'treatments':
        treatments(sys.argv[2] if len(sys.argv) > 2 else 'w-letter')
    elif cmd == 'choice':
        choice()
    elif cmd == 'families':
        families()
    elif cmd == 'final':
        marks = [(slug, label, MARKS_BY_SLUG[slug][0], MARKS_BY_SLUG[slug][1])
                 for slug, label, _note in FINAL]
        sheet(marks, 'final')
        launcher(marks, 'launcher-final')
    elif cmd == 'sizes':
        sizes(sys.argv[2] if len(sys.argv) > 2 else 't-door')
    else:
        sheet()


if __name__ == '__main__':
    main()
