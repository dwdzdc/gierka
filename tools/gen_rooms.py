"""Generator greyboxowych pokoi (.tscn) według kontraktu z rooms/room.gd.

Uruchom: python3 tools/gen_rooms.py
UWAGA: nadpisuje rooms/<nazwa>.tscn. Jeśli edytujesz pokój ręcznie w Godocie,
usuń go z listy na dole, żeby go nie nadpisać.

Kontrakt drzwi: każde przejście ma DOOR_W x DOOR_H. Marker3D w `Doorways` stoi na
zewnętrznej powierzchni ściany, na poziomie podłogi przejścia, oś -Z na zewnątrz.
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "rooms"
T = 0.2  # grubość ścian
DOOR_W = 2.0
DOOR_H = 2.6
FLOOR_STEP = 5.0  # wysokość piętra (rampa, klatka schodowa)
CAMERA_FOV = 68.0

EXT = [
    ("Script", "res://rooms/room.gd"),
    ("Script", "res://camera/camera_zone.gd"),
    ("Script", "res://camera/fixed_camera.gd"),
    ("Script", "res://fx/flicker_light.gd"),
    ("Material", "res://rooms/materials/concrete.tres"),
    ("Material", "res://rooms/materials/wall.tres"),
    ("Material", "res://rooms/materials/wood.tres"),
    ("Material", "res://rooms/materials/metal.tres"),
]
EXT_ID = {"room": 1, "zone": 2, "cam": 3, "flicker": 4, "concrete": 5, "wall": 6, "wood": 7, "metal": 8}
# Obrót markera drzwi (stopnie wokół Y), żeby jego -Z wskazywało na zewnątrz danej ściany.
SIDE_YAW = {"N": 0, "W": 90, "S": 180, "E": -90}


def v(*xs):
    return ", ".join(f"{round(x, 4) + 0.0:g}" for x in xs)  # + 0.0 zamienia -0 na 0


def tf(x, y, z, yaw_deg=0.0):
    """Transform3D w formacie .tscn: najpierw WIERSZE bazy, potem pozycja."""
    a = math.radians(yaw_deg)
    c, s = round(math.cos(a), 6), round(math.sin(a), 6)
    return f"Transform3D({v(c, 0, s, 0, 1, 0, -s, 0, c, x, y, z)})"


def wall_pieces(length, h, doors):
    """Kawałki ściany wzdłuż osi (od -L/2 do L/2) z otworami drzwi.
    doors: [(offset, y_floor)]. Zwraca [(a, b, y0, y1)]."""
    pieces, cursor = [], -length / 2
    for off, y in sorted(doors):
        a, b = off - DOOR_W / 2, off + DOOR_W / 2
        if a > cursor:
            pieces.append((cursor, a, 0.0, h))
        if y > 0:
            pieces.append((a, b, 0.0, y))  # ściana pod drzwiami na piętrze
        if y + DOOR_H < h:
            pieces.append((a, b, y + DOOR_H, h))  # nadproże
        cursor = b
    if cursor < length / 2:
        pieces.append((cursor, length / 2, 0.0, h))
    return pieces


def build(name, sx, sz, h, doors, solids=(), zones=(), lights=(), loot=(), ambient=(), spawns=()):
    """doors: [(nazwa, strona N/S/E/W, offset wzdłuż ściany, y podłogi przejścia)]
    solids: [("box", pos, size, mat)] albo [("prism", [(x, y), ...], z0, z1, mat)] (profil w XY, wyciągnięty wzdłuż Z)
    zones: [(nazwa, (x0, x1, z0, z1), poz. kamery, cel kamery, follow, priorytet[, (y0, y1)])]"""
    nodes, subs = [], []

    def box(node_name, pos, size, mat):
        nodes.append(
            f'[node name="{node_name}" type="CSGBox3D" parent="Geometry"]\n'
            f"transform = {tf(*pos)}\nsize = Vector3({v(*size)})\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    def prism(node_name, points, z0, z1, mat):
        # CSGPolygon3D wyciąga profil od z=0 w stronę -Z, więc węzeł stoi na z1.
        flat = ", ".join(v(x, y) for x, y in points)
        nodes.append(
            f'[node name="{node_name}" type="CSGPolygon3D" parent="Geometry"]\n'
            f"transform = {tf(0, 0, z1)}\npolygon = PackedVector2Array({flat})\ndepth = {z1 - z0:g}\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    box("Floor", (0, -0.1, 0), (sx + 2 * T, 0.2, sz + 2 * T), "concrete")
    box("Ceiling", (0, h + 0.1, 0), (sx + 2 * T, 0.2, sz + 2 * T), "concrete")

    per_side = {s: [] for s in "NSEW"}
    for _, side, off, y in doors:
        per_side[side].append((off, y))
    for side, side_doors in per_side.items():
        along_x = side in "NS"
        length = sx + 2 * T if along_x else sz
        fixed = (-(sz / 2 + T / 2) if side == "N" else sz / 2 + T / 2) if along_x else (
            -(sx / 2 + T / 2) if side == "W" else sx / 2 + T / 2)
        for i, (a, b, y0, y1) in enumerate(wall_pieces(length, h, side_doors)):
            mid, seg_len, seg_h = (a + b) / 2, b - a, y1 - y0
            pos = (mid, y0 + seg_h / 2, fixed) if along_x else (fixed, y0 + seg_h / 2, mid)
            size = (seg_len, seg_h, T) if along_x else (T, seg_h, seg_len)
            box(f"Wall{side}{i}", pos, size, "wall")

    for i, solid in enumerate(solids):
        if solid[0] == "box":
            box(f"Solid{i}", solid[1], solid[2], solid[3])
        else:
            prism(f"Solid{i}", solid[1], solid[2], solid[3], solid[4])

    def markers(holder, items):
        nodes.append(f'[node name="{holder}" type="Node3D" parent="."]\n')
        for item in items:
            n, pos = item[0], item[1]
            yaw = item[2] if len(item) > 2 else 0.0
            nodes.append(f'[node name="{n}" type="Marker3D" parent="{holder}"]\ntransform = {tf(*pos, yaw)}\n')

    door_markers = []
    for dname, side, off, y in doors:
        out = {"N": (off, y, -(sz / 2 + T)), "S": (off, y, sz / 2 + T),
               "E": (sx / 2 + T, y, off), "W": (-(sx / 2 + T), y, off)}[side]
        door_markers.append((dname, out, SIDE_YAW[side]))
    markers("Doorways", door_markers)

    nodes.append('[node name="CameraZones" type="Node3D" parent="."]\n')
    for zone in zones:
        zname, (x0, x1, z0, z1), cam_pos, target, follow, priority = zone[:6]
        y0, y1 = zone[6] if len(zone) > 6 else (0.0, h)
        sid = f"zone_{zname}"
        subs.append(f'[sub_resource type="BoxShape3D" id="{sid}"]\nsize = Vector3({v(x1 - x0, y1 - y0, z1 - z0)})\n')
        nodes.append(
            f'[node name="{zname}" type="Area3D" parent="CameraZones"]\n'
            f"collision_layer = 0\ncollision_mask = 2\nmonitorable = false\n"
            f'script = ExtResource("{EXT_ID["zone"]}")\ncamera_priority = {priority}\n'
        )
        nodes.append(
            f'[node name="Shape" type="CollisionShape3D" parent="CameraZones/{zname}"]\n'
            f"transform = {tf((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)}\nshape = SubResource(\"{sid}\")\n"
        )
        nodes.append(
            f'[node name="Camera" type="Camera3D" parent="CameraZones/{zname}"]\n'
            f"transform = {tf(*cam_pos)}\nfov = {CAMERA_FOV:g}\nnear = 0.05\n"
            f'script = ExtResource("{EXT_ID["cam"]}")\nlook_target = Vector3({v(*target)})\nfollow = {follow:g}\n'
        )

    nodes.append('[node name="Lights" type="Node3D" parent="."]\n')
    for i, (pos, color, energy, rng, flicker) in enumerate(lights):
        script = f'script = ExtResource("{EXT_ID["flicker"]}")\n' if flicker else ""
        nodes.append(
            f'[node name="Light{i}" type="OmniLight3D" parent="Lights"]\n'
            f"transform = {tf(*pos)}\nlight_color = Color({v(*color)}, 1)\nlight_energy = {energy:g}\n"
            f"shadow_enabled = true\nomni_range = {rng:g}\n{script}"
        )

    markers("LootSpawns", loot)
    markers("AmbientPoints", ambient)
    if spawns:
        markers("PlayerSpawns", spawns)

    # Bryła pokoju (ze ścianami) do testu kolizji przy składaniu mapy.
    bounds = f"AABB({v(-(sx / 2 + T), -0.2, -(sz / 2 + T), sx + 2 * T, h + 0.4, sz + 2 * T)})"
    header = f"[gd_scene load_steps={len(EXT) + len(subs) + 1} format=3]\n\n"
    header += "\n".join(f'[ext_resource type="{t}" path="{p}" id="{i + 1}"]' for i, (t, p) in enumerate(EXT)) + "\n\n"
    body = "\n".join(subs) + "\n" if subs else ""
    root = (f'[node name="{name}" type="Node3D"]\nscript = ExtResource("{EXT_ID["room"]}")\nbounds = {bounds}\n\n'
            '[node name="Geometry" type="CSGCombiner3D" parent="."]\nuse_collision = true\n\n')
    (OUT / f"{name.lower()}.tscn").write_text(header + body + "\n" + root + "\n".join(nodes))
    print("zapisano", name)


WARM, COLD = (1.0, 0.82, 0.6), (0.75, 0.85, 1.0)
S = FLOOR_STEP

# Zasady kamer (sprawdza tests/camera_rules_test.gd): każde przejście widoczne z co najmniej
# jednego ujęcia pokoju i nie pod kątem prawie równoległym do ściany. Małe pokoje: jedno ujęcie.

# Hall: 16x12, strefa startowa (spawn graczy). Drzwi na wschód i na południe.
build(
    "Hall", 16, 12, 5.0,
    doors=[("East", "E", 0, 0), ("South", "S", -4, 0)],
    solids=[
        ("box", (-4, 0.45, -3.5), (2.4, 0.9, 1.2), "wood"),     # stół
        ("box", (5.5, 0.6, 4.2), (1.2, 1.2, 1.2), "wood"),      # skrzynie
        ("box", (4.2, 0.45, 4.6), (0.9, 0.9, 0.9), "wood"),
        ("box", (-7.6, 1.0, -3), (0.6, 2.0, 3), "metal"),       # szafki pod zachodnią ścianą
    ],
    zones=[
        ("West", (-8, 1, -6, 6), (7.6, 4.6, -5.6), (-4, 0.6, 2), 0.0, 0),
        ("East", (-1, 8, -6, 6), (-7.6, 4.6, -5.6), (4, 0.6, 2), 0.0, 0),
    ],
    lights=[((0, 4.6, 0), WARM, 1.0, 12.0, False)],
    loot=[("Loot0", (-4, 0.95, -3.5))],
    ambient=[("Ambient0", (-7, 1, 5))],
    spawns=[("Spawn0", (-5, 0.05, 1.5), -90), ("Spawn1", (-5, 0.05, 0), -90),
            ("Spawn2", (-6.2, 0.05, 1.5), -90), ("Spawn3", (-6.2, 0.05, 0), -90)],
)

# Corridor: 16x4, drzwi na obu końcach. Kamery na końcach patrzą wzdłuż na przeciwległe drzwi.
build(
    "Corridor", 16, 4, 4.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (3, 0.4, 1.4), (0.8, 0.8, 0.8), "wood"),
        ("box", (-4, 1.0, -1.65), (1.4, 2.0, 0.5), "metal"),  # szafka przy ścianie
    ],
    zones=[
        ("WestHalf", (-8, 1, -2, 2), (7.6, 3.6, 1.4), (-5, 0.8, 0), 0.35, 0),
        ("EastHalf", (-1, 8, -2, 2), (-7.6, 3.6, -1.4), (5, 0.8, 0), 0.35, 0),
    ],
    lights=[((0, 3.6, 0), COLD, 0.9, 9.0, True)],
    ambient=[("Ambient0", (5, 3.4, 0))],
)

# Storage: 20x20, dwa regały tworzą trzy alejki po ~6 m. Drzwi na zachód i na wschód.
build(
    "Storage", 20, 20, 6.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (1.5, 1.1, -3.5), (10, 2.2, 1.0), "metal"),   # regał A
        ("box", (1.5, 1.1, 3.5), (10, 2.2, 1.0), "metal"),    # regał B
        ("box", (8.8, 0.6, -8.8), (1.2, 1.2, 1.2), "wood"),
        ("box", (8.8, 0.6, -7.4), (1.2, 1.2, 1.2), "wood"),
        ("box", (8.8, 1.8, -8.8), (1.2, 1.2, 1.2), "wood"),
        ("box", (-8.8, 0.5, -8.8), (1.0, 1.0, 1.0), "wood"),
    ],
    zones=[
        ("Entry", (-10, -2.5, -10, 10), (2, 5.6, -9.6), (-7, 0.6, 2), 0.25, 0),
        ("NorthAisle", (-4.5, 10, -10, -3.5), (9.6, 5.4, -9.6), (-3, 0.6, -7), 0.2, 0),
        ("MiddleAisle", (-4.5, 10, -4, 4), (-9.4, 5.4, 0.5), (7, 0.6, 0), 0.3, 0),
        ("SouthAisle", (-4.5, 10, 3.5, 10), (9.6, 5.4, 9.6), (-3, 0.6, 7), 0.0, 0),
        # Pas za regałami przy wschodnich drzwiach: widok znad środka magazynu.
        ("EastEnd", (6.5, 10, -10, 10), (0, 5.7, 0), (9, 0.6, 0), 0.25, 1),
    ],
    lights=[((2, 5.6, 0), (1.0, 0.75, 0.5), 1.0, 12.0, True), ((-7, 5.6, -6), (0.6, 0.75, 1.0), 0.9, 10.0, False)],
    loot=[("Loot0", (8.8, 2.45, -8.8)), ("Loot1", (-8.8, 1.05, -8.8))],
    ambient=[("Ambient0", (9, 1, 9)), ("Ambient1", (0, 5, -7))],
)

# Turn: 6x6, zakręt (drzwi na zachód i na północ). Jedno ujęcie.
build(
    "Turn", 6, 6, 4.0,
    doors=[("West", "W", 0, 0), ("North", "N", 0, 0)],
    solids=[("box", (2.2, 0.5, -2.2), (0.9, 1.0, 0.9), "wood")],
    zones=[("All", (-3, 3, -3, 3), (2.8, 3.6, 2.8), (-1.5, 0.5, -1.5), 0.25, 0)],
    lights=[((0, 3.6, 0), COLD, 0.6, 6.0, True)],
    ambient=[("Ambient0", (2.2, 3.2, -2.2))],
)

# Junction: 10x10, skrzyżowanie T (zachód, wschód, północ). Bez filara, jedno ujęcie.
build(
    "Junction", 10, 10, 4.5,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("North", "N", 0, 0)],
    solids=[("box", (-4, 0.5, 4), (1.0, 1.0, 1.0), "wood")],
    zones=[("All", (-5, 5, -5, 5), (0, 4.2, 4.8), (0, 0.5, -2.5), 0.2, 0)],
    lights=[((0, 4.1, -1), WARM, 0.8, 10.0, False)],
    ambient=[("Ambient0", (-4, 1, -4))],
)

# Closet: 7x7, ślepy zaułek ze znaleziskami. Jedno ujęcie.
build(
    "Closet", 7, 7, 4.0,
    doors=[("West", "W", 0, 0)],
    solids=[
        ("box", (2.5, 0.5, -2.5), (1, 1, 1), "wood"),
        ("box", (2.6, 0.4, 2.6), (0.8, 0.8, 0.8), "wood"),
        ("box", (0.5, 1.0, -3.2), (2.0, 2.0, 0.6), "metal"),
    ],
    zones=[("All", (-3.5, 3.5, -3.5, 3.5), (3.2, 3.6, 3.2), (-2, 0.6, -1), 0.2, 0)],
    lights=[((0.5, 3.6, 0), WARM, 0.6, 6.0, True)],
    loot=[("Loot0", (2.5, 1.05, -2.5)), ("Loot1", (0.5, 2.05, -3.2))],
)

# Ramp: 16x4, korytarz w górę o jedno piętro. Dolne drzwi na zachodzie, górne na wschodzie.
build(
    "Ramp", 16, 4, S + 4.0,
    doors=[("Low", "W", 0, 0), ("High", "E", 0, S)],
    solids=[
        ("prism", [(-5, 0), (5, 0), (5, S)], -2, 2, "concrete"),
        ("box", (6.5, S / 2, 0), (3, S, 4), "concrete"),  # górny podest
    ],
    zones=[
        ("Lower", (-8, 1, -2, 2), (7.6, S + 3.4, 1.4), (-4, 0.8, 0), 0.4, 0),
        ("Upper", (-1, 8, -2, 2), (-7.6, S + 2.6, -1.4), (6, S + 0.6, 0), 0.4, 0),
    ],
    lights=[((-6, 3.8, 0), COLD, 0.7, 8.0, False), ((6, S + 3.6, 0), WARM, 0.6, 7.0, True)],
    ambient=[("Ambient0", (0, S, 0))],
)

# Stairwell: 10x8, klatka schodowa na jedno piętro (dwa biegi z półpiętrem).
# Oba wejścia na zachodzie: dolne (z=-2, y=0) i górne (z=2, y=S).
build(
    "Stairwell", 10, 8, S + 4.5,
    doors=[("Low", "W", -2, 0), ("High", "W", 2, S)],
    solids=[
        ("prism", [(-1.5, 0), (3.5, 0), (3.5, S / 2)], -4, 0, "concrete"),  # bieg 1
        ("box", (4.25, S / 4, 0), (1.5, S / 2, 8), "concrete"),  # półpiętro
        # bieg 2 + górny podest jako jedna pełna bryła (bez pustki pod spodem)
        ("prism", [(-5, 0), (3.5, 0), (3.5, S / 2), (-1.5, S), (-5, S)], 0, 4, "concrete"),
    ],
    zones=[
        # Każda kamera stoi nad "swoją" stroną klatki, żeby bryła drugiego biegu nie zasłaniała drzwi.
        ("Low", (-5, 5, -4, 0.6), (4.6, S + 4.0, -3.6), (-3, 0.5, -2), 0.3, 0),
        ("High", (-5, 5, -0.6, 4), (4.6, S + 4.0, 3.6), (-3, S + 0.5, 2), 0.3, 0),
    ],
    lights=[((0, S + 4.1, 0), COLD, 0.8, 10.0, True)],
    ambient=[("Ambient0", (4.2, S / 2 + 0.5, 0))],
)
