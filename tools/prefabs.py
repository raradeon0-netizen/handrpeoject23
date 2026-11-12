"""Masonry and lighting prefabs of BlockLibrary: stone table generator and a geometry check.

  python3 tools/prefabs.py gen     print the COBBLES / RUIN_STONES Luau tables (seeded, reproducible)
  python3 tools/prefabs.py check   validate the masonry and lighting prefabs against BlockLibrary.luau

The check reads the stone tables straight from the Luau source and mirrors the loop-built
prefabs (brick wall, mosaic road, torch, brazier, obelisk lamp). For every prefab it verifies that all pieces stay inside the
shape bounds, that the lower corner of the bounds is reached exactly (grid snapping of the Move
tool aligns that edge) and that no two faces lie on the same plane with overlapping area.
"""
import itertools
import math
import random
import re
import sys

LIBRARY = "src/ReplicatedStorage/Shared/BlockLibrary.luau"
EPS = 1e-6


def rotation(yaw=0.0, pitch=0.0, roll=0.0):
    """CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) as a 3x3 matrix (degrees in)."""
    y, p, r = (math.radians(a) for a in (yaw, pitch, roll))
    ry = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    rx = [[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]]
    rz = [[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(ry, mul(rx, rz))


def extents(size, angles):
    m = rotation(*angles)
    return [sum(abs(m[a][j]) * size[j] for j in range(3)) for a in range(3)]


class Piece:
    def __init__(self, size, center, angles=(0, 0, 0)):
        self.size, self.center, self.angles = size, center, angles
        ext = extents(size, angles)
        self.lo = [center[a] - ext[a] / 2 for a in range(3)]
        self.hi = [center[a] + ext[a] / 2 for a in range(3)]

    def flat(self, axis):
        """Are the faces across this axis parallel to the shape axes?"""
        yaw, pitch, roll = self.angles
        if pitch or roll:
            return False
        return axis == 1 or yaw == 0


# ----- generators -------------------------------------------------------------------------------


def gen_cobbles(rng):
    rows = []

    def stone(cx, cz, reach, size_range, height_range, top_range, tilt):
        while True:
            size = [round(rng.uniform(*size_range), 2), round(rng.uniform(*height_range), 2), round(rng.uniform(*size_range), 2)]
            angles = (
                round(rng.uniform(-35, 35), 1),
                round(rng.choice((-1, 1)) * rng.uniform(*tilt), 1),
                round(rng.choice((-1, 1)) * rng.uniform(*tilt), 1),
            )
            ext = extents(size, angles)
            if ext[0] > reach * 2 - 0.08 or ext[2] > reach * 2 - 0.08:
                continue
            x = round(cx + rng.uniform(-1, 1) * (reach - ext[0] / 2 - 0.02), 2)
            z = round(cz + rng.uniform(-1, 1) * (reach - ext[2] / 2 - 0.02), 2)
            top = rng.uniform(*top_range)
            y = round(top - ext[1] / 2, 2)
            if y - ext[1] / 2 > 0.02 or y - ext[1] / 2 < -0.45 or y + ext[1] / 2 > 0.49:
                continue
            return [x, y, z, *size, *angles, rng.choice((1, 2)), round(rng.uniform(0.86, 1.08), 2)]

    for i in range(4):
        for j in range(4):
            rows.append(stone(-3 + 2 * i, -3 + 2 * j, 1.0, (1.2, 1.65), (0.42, 0.62), (0.32, 0.47), (1.5, 5)))
    # Мелкие камни в стыках между крупными.
    for i in range(3):
        for j in range(3):
            rows.append(stone(-2 + 2 * i, -2 + 2 * j, 0.5, (0.45, 0.7), (0.34, 0.46), (0.2, 0.3), (2, 7)))
    return rows


def gen_ruin(rng):
    heights = [2.4, 1.8, 2.2, 1.6]
    rows, bottom, previous = [], -4.0, []
    for index, height in enumerate(heights):
        while True:
            count = rng.choice((3, 3, 4))
            cuts = sorted(round(rng.uniform(-6 + 2.2, 6 - 2.2) * 2) / 2 for _ in range(count - 1))
            edges = [-6.0, *cuts, 6.0]
            widths = [b - a for a, b in zip(edges, edges[1:])]
            if min(widths) < 2.2 or max(widths) > 4.8:
                continue
            if any(abs(c - p) < 0.5 for c in cuts for p in previous):
                continue  # вертикальные швы соседних рядов не совпадают
            break
        previous = cuts
        last_row = index == len(heights) - 1
        lowered = rng.randrange(len(widths)) if last_row else -1
        for k, (left, right) in enumerate(zip(edges, edges[1:])):
            x0 = left + (0 if k == 0 else 0.09)
            x1 = right - (0 if k == len(widths) - 1 else 0.09)
            top = bottom + height - (0 if last_row else 0.16)
            if k == lowered:
                top -= 0.4  # выщербленный камень в верхнем ряду
            depth = rng.choice((3.7, 3.85, 4.0))
            rows.append([round((x0 + x1) / 2, 3), round((bottom + top) / 2, 3), round(x1 - x0, 3), round(top - bottom, 3), depth, round(rng.uniform(0.82, 1.06), 2)])
        bottom += height
    if not any(r[4] == 4.0 for r in rows):
        rows[0][4] = 4.0
    return rows


def lua_table(name, comment, rows):
    def num(v):
        return str(int(v)) if float(v).is_integer() else repr(v)

    lines = [f"-- {comment}", f"local {name}: {{ {{ number }} }} = {{"]
    lines += ["\t{ " + ", ".join(num(v) for v in row) + " }," for row in rows]
    return "\n".join(lines + ["}"])


def generate():
    rng = random.Random(1207)
    print(lua_table("COBBLES", "x, y, z, длина, высота, ширина, поворот°, наклон X°, наклон Z°, порода (1 / 2), оттенок", gen_cobbles(rng)))
    print()
    print(lua_table("RUIN_STONES", "x, y, длина, высота, глубина, оттенок", gen_ruin(rng)))


# ----- check ------------------------------------------------------------------------------------


def read_table(source, name):
    body = re.search(r"local %s: [^\n]*= \{\n(.*?)\n\}" % name, source, re.S)
    if not body:
        sys.exit(f"table {name} not found in {LIBRARY}")
    return [[float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", line)] for line in body.group(1).splitlines()]


def brick_wall():
    pieces = [Piece((11.8, 7.2, 3.8), (0, -0.4, 0))]
    for course in range(8):
        y = -4 + 0.9 * (course + 0.5)
        edges = [-6, -3, 0, 3, 6] if course % 2 == 0 else [-6, -4.5, -1.5, 1.5, 4.5, 6]
        for left, right in zip(edges, edges[1:]):
            pieces.append(Piece((right - left - 0.1, 0.8, 4), ((left + right) / 2, y, 0)))
    return pieces + [Piece((11.6, 0.3, 3.6), (0, 3.35, 0)), Piece((12, 0.5, 4), (0, 3.75, 0))]


def mosaic_road():
    pieces = [Piece((8, 0.5, 8), (0, -0.25, 0))]
    for sx in (-1, 1):
        pieces += [
            Piece((0.4, 0.2, 8), (sx * 3.8, 0.1, 0)),
            Piece((0.4, 0.5, 8), (sx * 3.4, 0.25, 0)),
            Piece((0.3, 0.3, 8), (sx * 3.05, 0.15, 0)),
            Piece((0.4, 0.26, 8), (sx * 2.7, 0.13, 0)),
        ]
        pieces += [Piece((0.26, 0.27, 0.26), (sx * 2.7, 0.185, -3 + 2 * k), (45, 0, 0)) for k in range(4)]
        pieces += [Piece((2.44, 0.3, 3.94), (sx * 1.25, 0.15, sz * 2)) for sz in (-1, 1)]
    return pieces + [Piece((1.7, 0.28, 1.7), (0, 0.19, 0), (45, 0, 0)), Piece((1.3, 0.26, 1.3), (0, 0.23, 0), (45, 0, 0))]


def cobble_road(rows):
    return [Piece((8, 0.6, 8), (0, -0.2, 0))] + [Piece(tuple(r[3:6]), tuple(r[0:3]), tuple(r[6:9])) for r in rows]


def ruin_wall(rows):
    return [Piece((11.6, 7.4, 3), (0, -0.2, 0))] + [Piece((r[2], r[3], r[4]), (r[0], r[1], 0)) for r in rows]


def compose(origin, angles, offset):
    """Position of origin * CFrame.Angles(...) * CFrame.new(offset)."""
    m = rotation(*angles)
    return tuple(origin[a] + sum(m[a][j] * offset[j] for j in range(3)) for a in range(3))


def wall_torch():
    tilt = (0, 20, 0)
    origin = (0, 0, 0.1)
    return [
        Piece((1, 2, 0.2), (0, -1, -0.9)),
        Piece((0.3, 0.12, 0.08), (0, -0.3, -0.77)),
        Piece((0.3, 0.12, 0.08), (0, -1.7, -0.77)),
        Piece((0.2, 0.2, 0.7), (0, -0.9, -0.45)),
        Piece((0.3, 2.4, 0.3), origin, tilt),
        Piece((0.45, 0.2, 0.45), compose(origin, tilt, (0, -0.958, 0)), tilt),
        Piece((0.9, 0.12, 0.9), (0, 1.05, 0.55)),
        Piece((0.5, 0.6, 0.5), compose(origin, tilt, (0, 1.4, 0)), tilt),
        Piece((0.36, 0.25, 0.36), compose(origin, tilt, (0, 1.8, 0)), tilt),
    ]


def brazier():
    pieces = [Piece((4, 0.5, 4), (0, -1.75, 0)), Piece((2.4, 0.4, 2.4), (0, -1.3, 0))]
    for k in range(3):
        angle = math.radians(90 + 120 * k)
        x, z = 0.75 * math.cos(angle), 0.75 * math.sin(angle)
        pieces.append(Piece((0.22, 2.3, 0.22), (x, -0.05, z), (math.degrees(math.atan2(-x, -z)), 10, 0)))
        pieces.append(Piece((0.45, 0.26, 0.45), (-0.8 * x, 1.76, -0.8 * z), (40 * k, 12, -9)))
    # Вертикальные цилиндры: габарит (диаметр, высота, диаметр).
    return pieces + [
        Piece((1.5, 0.12, 1.5), (0, -0.4, 0)),
        Piece((2.2, 0.4, 2.2), (0, 0.9, 0)),
        Piece((3, 0.5, 3), (0, 1.35, 0)),
        Piece((2.5, 0.2, 2.5), (0, 1.62, 0)),
    ]


def obelisk_lamp():
    pieces = [
        Piece((4, 1, 4), (0, -5.5, 0)),
        Piece((3.2, 0.6, 3.2), (0, -4.7, 0)),
        Piece((2.4, 3, 2.4), (0, -2.9, 0)),
        Piece((2.1, 3, 2.1), (0, 0.1, 0)),
        Piece((1.8, 2.4, 1.8), (0, 2.8, 0)),
        Piece((2.6, 0.2, 2.6), (0, -1.4, 0)),
        Piece((2.3, 0.2, 2.3), (0, 1.6, 0)),
    ]
    for side in (-1, 1):
        pieces += [Piece((1.2, 1.8, 0.06), (0, -2.9, side * 1.21)), Piece((0.06, 1.8, 1.2), (side * 1.21, -2.9, 0))]
    return pieces + [
        Piece((2.6, 0.4, 2.6), (0, 4.2, 0)),
        Piece((3, 0.5, 3), (0, 4.65, 0)),
        Piece((0.8, 0.8, 0.8), (0, 5.3, 0), (0, 45, 45)),
    ]


def check():
    source = open(LIBRARY, encoding="utf-8").read()
    prefabs = {
        "brickWall": ((12, 8, 4), brick_wall()),
        "cobbleRoad": ((8, 1, 8), cobble_road(read_table(source, "COBBLES"))),
        "mosaicRoad": ((8, 1, 8), mosaic_road()),
        "ruinWall": ((12, 8, 4), ruin_wall(read_table(source, "RUIN_STONES"))),
        "wallTorch": ((1, 4, 2), wall_torch()),
        "brazier": ((4, 4, 4), brazier()),
        "obeliskLamp": ((4, 12, 4), obelisk_lamp()),
    }
    failed = False
    for name, (size, pieces) in prefabs.items():
        if f"local function {name}(" not in source:
            sys.exit(f"builder {name} not found in {LIBRARY}")
        half = [s / 2 for s in size]
        problems = []
        for index, piece in enumerate(pieces):
            for a in range(3):
                if piece.lo[a] < -half[a] - EPS or piece.hi[a] > half[a] + EPS:
                    problems.append(f"piece {index} leaves the bounds on axis {a}: {piece.lo[a]:.3f}..{piece.hi[a]:.3f}")
        low = [min(p.lo[a] for p in pieces) for a in range(3)]
        high = [max(p.hi[a] for p in pieces) for a in range(3)]
        for a in range(3):
            if abs(low[a] + half[a]) > EPS:
                problems.append(f"lower bound not reached on axis {a}: {low[a]:.3f}")
        for a in (0, 2):
            if abs(high[a] - half[a]) > EPS:
                problems.append(f"upper bound not reached on axis {a}: {high[a]:.3f}")
        for (i, p), (j, q) in itertools.combinations(enumerate(pieces), 2):
            for a in range(3):
                if not (p.flat(a) and q.flat(a)):
                    continue
                others = [x for x in range(3) if x != a]
                if all(min(p.hi[x], q.hi[x]) - max(p.lo[x], q.lo[x]) > 1e-3 for x in others):
                    if abs(p.hi[a] - q.hi[a]) < 1e-4 or abs(p.lo[a] - q.lo[a]) < 1e-4:
                        problems.append(f"coplanar faces on axis {a}: pieces {i} and {j}")
        tilted = sum(1 for p in pieces if p.angles[1] or p.angles[2])
        print(f"{name}: {len(pieces)} pieces ({tilted} tilted), height {low[1]:.2f}..{high[1]:.2f}, {'OK' if not problems else 'FAILED'}")
        for problem in problems:
            print("  " + problem)
        failed = failed or bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    generate() if sys.argv[1:] == ["gen"] else check()
