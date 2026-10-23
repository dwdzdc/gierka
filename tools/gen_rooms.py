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
DOOR_W = 1.6
DOOR_H = 2.4

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
            f"transform = {tf(*cam_pos)}\nfov = 62.0\nnear = 0.05\n"
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

# Hall: 10x8, strefa startowa (spawn graczy). Drzwi na wschód i na południe.
build(
    "Hall", 10, 8, 3.5,
    doors=[("East", "E", 0, 0), ("South", "S", -2.5, 0)],
    solids=[
        ("box", (-2.5, 0.45, -2.6), (1.8, 0.9, 0.9), "wood"),   # stół
        ("box", (3.6, 0.5, 2.9), (1, 1, 1), "wood"),            # skrzynie
        ("box", (3.6, 0.4, 1.9), (0.8, 0.8, 0.8), "wood"),
        ("box", (1.2, 1.75, -0.8), (0.6, 3.5, 0.6), "concrete"),  # filar zasłaniający część kadru
    ],
    zones=[
        ("West", (-5, 0.6, -4, 4), (4.6, 3.1, 3.6), (-2.5, 0.6, -1.0), 0.0, 0),
        ("East", (-0.6, 5, -4, 4), (-4.6, 3.1, 3.6), (3.0, 0.6, -0.8), 0.0, 0),
    ],
    lights=[((0, 3.1, 0.5), WARM, 0.9, 7.5, False)],
    loot=[("Loot0", (-2.5, 0.95, -2.6))],
    ambient=[("Ambient0", (-4.5, 1, 3.5))],
    spawns=[("Spawn0", (-2.5, 0.05, 1.5), -90), ("Spawn1", (-2.5, 0.05, 0.3), -90),
            ("Spawn2", (-3.7, 0.05, 1.5), -90), ("Spawn3", (-3.7, 0.05, 0.3), -90)],
)

# Corridor: 12x2.5, drzwi na obu końcach.
build(
    "Corridor", 12, 2.5, 3.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (2.2, 0.35, 0.75), (0.7, 0.7, 0.7), "wood"),
        ("box", (-3.0, 0.9, -0.95), (1.2, 1.8, 0.5), "metal"),  # szafka przy ścianie
    ],
    zones=[
        ("WestHalf", (-6.2, 0.8, -1.25, 1.25), (5.6, 2.6, 0.9), (-4.0, 0.8, 0), 0.35, 0),
        ("EastHalf", (-0.8, 6.2, -1.25, 1.25), (-5.6, 2.6, -0.9), (4.0, 0.8, 0), 0.35, 0),
    ],
    lights=[((0, 2.7, 0), COLD, 0.8, 6.0, True)],
    ambient=[("Ambient0", (3.5, 2.5, 0))],
)

# Storage: 12x12, regały tworzą trzy alejki. Drzwi na zachód i na wschód.
build(
    "Storage", 12, 12, 4.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (1.0, 1.1, -2.0), (6, 2.2, 0.8), "metal"),   # regał A
        ("box", (1.0, 1.1, 2.5), (6, 2.2, 0.8), "metal"),    # regał B
        ("box", (4.9, 0.5, -4.9), (1, 1, 1), "wood"),
        ("box", (4.9, 0.5, -3.8), (1, 1, 1), "wood"),
        ("box", (4.9, 1.5, -4.9), (1, 1, 1), "wood"),
        ("box", (-5.2, 0.4, -5.2), (0.8, 0.8, 0.8), "wood"),
    ],
    zones=[
        ("Entry", (-6, -1.4, -6, 6), (-1.2, 3.6, -5.6), (-4.5, 0.6, 2.0), 0.25, 0),
        ("NorthAisle", (-2.0, 6, -6, -1.6), (5.7, 3.7, -2.6), (-1.5, 0.4, -4.2), 0.2, 0),
        ("MiddleAisle", (-2.0, 6, -2.0, 2.5), (5.6, 3.6, 0.25), (-2.0, 0.6, 0.25), 0.3, 0),
        ("SouthAisle", (-2.0, 6, 2.1, 6), (-5.6, 3.6, 5.6), (4.0, 0.6, 4.5), 0.0, 0),
        # Wschodni koniec regałów: martwe pole dla kamer alejek, wykryte testem widoczności.
        ("EastEnd", (3.9, 6, -2.8, 2.9), (1.0, 3.8, -5.6), (4.8, 0.6, 0.0), 0.3, 1),
    ],
    lights=[((3.0, 3.6, 0.2), (1.0, 0.75, 0.5), 0.8, 7.0, True), ((-4.0, 3.6, -1.0), (0.6, 0.75, 1.0), 0.8, 7.5, False)],
    loot=[("Loot0", (4.9, 2.1, -4.9)), ("Loot1", (-5.2, 0.85, -5.2))],
    ambient=[("Ambient0", (5.5, 1, 5.5)), ("Ambient1", (0, 3.5, -4))],
)

# Turn: 4x4, zakręt (drzwi na zachód i na północ).
build(
    "Turn", 4, 4, 3.0,
    doors=[("West", "W", 0, 0), ("North", "N", 0, 0)],
    solids=[("box", (1.4, 0.5, 1.4), (0.9, 1.0, 0.9), "wood")],
    zones=[("All", (-2, 2, -2, 2), (1.75, 2.7, 1.75), (-1.0, 0.5, -1.0), 0.3, 0)],
    lights=[((0, 2.7, 0), COLD, 0.5, 4.0, True)],
    ambient=[("Ambient0", (1.5, 2.5, -1.5))],
)

# Junction: 6x6, skrzyżowanie T (zachód, wschód, północ).
build(
    "Junction", 6, 6, 3.5,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("North", "N", 0, 0)],
    solids=[("box", (0, 1.75, 1.2), (0.7, 3.5, 0.7), "concrete")],
    zones=[
        ("West", (-3, 0.5, -3, 3), (2.7, 3.2, 2.7), (-1.5, 0.5, -1.0), 0.25, 0),
        ("East", (-0.5, 3, -3, 3), (-2.7, 3.2, 2.7), (1.5, 0.5, -1.0), 0.25, 0),
    ],
    lights=[((0, 3.1, -1.0), WARM, 0.6, 6.0, False)],
    ambient=[("Ambient0", (-2.5, 1, -2.5))],
)

# Closet: 5x5, ślepy zaułek ze znaleziskami.
build(
    "Closet", 5, 5, 3.0,
    doors=[("West", "W", 0, 0)],
    solids=[
        ("box", (1.8, 0.5, -1.8), (1, 1, 1), "wood"),
        ("box", (1.8, 0.4, 1.9), (0.8, 0.8, 0.8), "wood"),
        ("box", (0.8, 0.9, -2.2), (1.4, 1.8, 0.5), "metal"),
    ],
    zones=[("All", (-2.5, 2.5, -2.5, 2.5), (-2.2, 2.7, 2.2), (1.2, 0.5, -0.8), 0.25, 0)],
    lights=[((0.5, 2.7, 0), WARM, 0.45, 4.5, True)],
    loot=[("Loot0", (1.8, 1.05, -1.8)), ("Loot1", (1.8, 0.85, 1.9))],
)

# Ramp: 10x2.5, korytarz w górę o jedno piętro (3 m). Dolne drzwi na zachodzie, górne na wschodzie.
build(
    "Ramp", 10, 2.5, 6.0,
    doors=[("Low", "W", 0, 0), ("High", "E", 0, 3.0)],
    solids=[
        ("prism", [(-3, 0), (3, 0), (3, 3)], -1.25, 1.25, "concrete"),
        ("box", (4, 1.5, 0), (2, 3, 2.5), "concrete"),  # górny podest
    ],
    zones=[
        ("Lower", (-5, 1, -1.25, 1.25), (4.6, 5.6, 0.9), (-3.0, 0.8, 0), 0.4, 0),
        ("Upper", (-1, 5, -1.25, 1.25), (-4.6, 5.0, -0.9), (4.0, 3.6, 0), 0.4, 0),
    ],
    lights=[((-3.5, 3.2, 0), COLD, 0.6, 6.0, False), ((3.5, 5.6, 0), WARM, 0.5, 5.0, True)],
    ambient=[("Ambient0", (0, 4, 0))],
)

# Stairwell: 6x5, klatka schodowa na jedno piętro (dwa biegi z podestem).
# Oba wejścia na zachodzie: dolne (z=-1.25, y=0) i górne (z=1.25, y=3).
build(
    "Stairwell", 6, 5, 6.2,
    doors=[("Low", "W", -1.25, 0), ("High", "W", 1.25, 3.0)],
    solids=[
        ("prism", [(-1, 0), (2, 0), (2, 1.5)], -2.5, 0, "concrete"),  # bieg 1
        ("box", (2.5, 0.75, 0), (1, 1.5, 5), "concrete"),  # półpiętro
        # bieg 2 + górny podest jako jedna pełna bryła (bez pustki pod spodem)
        ("prism", [(-3, 0), (2, 0), (2, 1.5), (-1, 3), (-3, 3)], 0, 2.5, "concrete"),
    ],
    zones=[
        ("Low", (-3, 3, -2.5, 0.4), (2.7, 5.8, 2.2), (-2.0, 0.5, -1.3), 0.3, 0),
        ("High", (-3, 3, -0.4, 2.5), (2.7, 5.8, -2.2), (-2.0, 3.5, 1.3), 0.3, 0),
    ],
    lights=[((0, 5.8, 0), COLD, 0.7, 7.0, True)],
    ambient=[("Ambient0", (2.5, 3, 0))],
)
