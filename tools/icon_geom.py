"""Centre-line stroke geometry: turn a polyline plus a weight into one filled
outline, with round caps and mitred joints.

Drawing a stroke as a quad per segment plus a disc per vertex (what the first
attempts did) leaves a bulge on the outside of every joint and a notch on the
inside of a sharp one, which is exactly where a W's apex lives.  Building the
outline once and filling it gives the crisp apex a letter needs.
"""
import math

TAU = 2 * math.pi


def _unit(dx, dy):
    length = math.hypot(dx, dy) or 1.0
    return dx / length, dy / length


def _line_meet(p, d, q, e):
    """Intersection of line p + t*d with q + s*e, or None when parallel."""
    den = d[0] * e[1] - d[1] * e[0]
    if abs(den) < 1e-9:
        return None
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
    return p[0] + d[0] * t, p[1] + d[1] * t


def _arc(cx, cy, r, a0, a1, steps=14):
    """Arc from a0 to a1 (radians), inclusive."""
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / steps),
             cy + r * math.sin(a0 + (a1 - a0) * i / steps))
            for i in range(steps + 1)]


def _shortest(a0, a1):
    delta = (a1 - a0) % TAU
    if delta > math.pi:
        delta -= TAU
    return delta


def rounded_polygon(points, radius, samples=10):
    """A polygon whose corners are replaced by arcs of `radius`.

    Every vertex is trimmed back along both of its edges and bridged with a
    circular arc, so the result is a simple polygon that fills cleanly -- the
    alternative, filling the shape and stroking its own outline, leaves a bite
    where the stroke closes on itself.
    """
    pts = [tuple(p) for p in points]
    count = len(pts)
    out = []
    for i in range(count):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % count]
        u = _unit(a[0] - b[0], a[1] - b[1])
        v = _unit(c[0] - b[0], c[1] - b[1])
        cosang = max(-1.0, min(1.0, u[0] * v[0] + u[1] * v[1]))
        angle = math.acos(cosang)
        if angle < 1e-3 or abs(angle - math.pi) < 1e-3:
            out.append(b)
            continue
        half = angle / 2
        trim = radius / math.tan(half)
        trim = min(trim, math.hypot(a[0] - b[0], a[1] - b[1]) / 2,
                   math.hypot(c[0] - b[0], c[1] - b[1]) / 2)
        p1 = (b[0] + u[0] * trim, b[1] + u[1] * trim)
        p2 = (b[0] + v[0] * trim, b[1] + v[1] * trim)
        bisector = _unit(u[0] + v[0], u[1] + v[1])
        reach = trim / math.cos(half)
        centre = (b[0] + bisector[0] * reach, b[1] + bisector[1] * reach)
        start = math.atan2(p1[1] - centre[1], p1[0] - centre[0])
        end = math.atan2(p2[1] - centre[1], p2[0] - centre[0])
        out.extend(_arc(centre[0], centre[1], radius, start,
                        start + _shortest(start, end), samples))
    return out


def outline(points, width, cap='round', join='miter', miter_limit=3.0):
    """The closed outline of a stroked polyline, as a list of points."""
    r = width / 2.0
    pts = [tuple(p) for p in points]
    if len(pts) == 1:
        return _arc(pts[0][0], pts[0][1], r, 0, TAU, 28)
    dirs = [_unit(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
    angles = [math.atan2(d[1], d[0]) for d in dirs]

    def normal(d, side):
        return (-d[1] * side, d[0] * side)

    def side_path(side):
        path = []
        for i, p in enumerate(pts):
            if i == 0:
                n = normal(dirs[0], side)
                path.append((p[0] + n[0] * r, p[1] + n[1] * r))
            elif i == len(pts) - 1:
                n = normal(dirs[-1], side)
                path.append((p[0] + n[0] * r, p[1] + n[1] * r))
            else:
                d0, d1 = dirs[i - 1], dirs[i]
                n0, n1 = normal(d0, side), normal(d1, side)
                a = (p[0] + n0[0] * r, p[1] + n0[1] * r)
                b = (p[0] + n1[0] * r, p[1] + n1[1] * r)
                cross = d0[0] * d1[1] - d0[1] * d1[0]
                convex = side * cross < 0
                if join == 'round' and convex:
                    base = math.atan2(n0[1], n0[0])
                    path.extend(_arc(p[0], p[1], r, base,
                                     base + _shortest(base, math.atan2(n1[1], n1[0])), 10))
                else:
                    # the concave side folds back on itself: use the corner the
                    # two offset edges actually share, never a swept arc
                    hit = _line_meet(a, d0, b, d1)
                    if hit is None or math.hypot(hit[0] - p[0], hit[1] - p[1]) > miter_limit * r:
                        path.extend([a, b])
                    else:
                        path.append(hit)
        return path

    left = side_path(1)
    right = side_path(-1)
    if cap == 'butt':
        return left + right[::-1]

    # A round cap is a half circle from the left offset point, through the
    # direction of travel, to the right offset point.
    tail = _arc(pts[-1][0], pts[-1][1], r, angles[-1] + math.pi / 2,
                angles[-1] - math.pi / 2, 14)
    head = _arc(pts[0][0], pts[0][1], r, angles[0] - math.pi / 2,
                angles[0] - 3 * math.pi / 2, 14)
    return left + tail + right[::-1] + head
