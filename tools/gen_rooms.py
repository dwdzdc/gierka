"""Generator greyboxowych pokoi (.tscn) według kontraktu z rooms/room.gd.

Uruchom: python3 tools/gen_rooms.py
UWAGA: nadpisuje rooms/<nazwa>.tscn. Jeśli edytujesz pokój ręcznie w Godocie,
usuń go z listy na dole, żeby go nie nadpisać.

Kontrakt drzwi: każde przejście ma DOOR_W x DOOR_H. Marker3D w `Doorways` stoi na
zewnętrznej powierzchni ściany, na poziomie podłogi przejścia, oś -Z na zewnątrz.
"""
import math
import re
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "rooms"
T = 0.2  # grubość ścian
DOOR_W = 2.0
DOOR_H = 2.6
FLOOR_STEP = 5.0  # wysokość piętra (rampa, klatka schodowa)
CAMERA_FOV = 68.0
LIGHT_SCALE = 1.3  # wspólne strojenie jasności wszystkich lamp

EXT = [
    ("Script", "res://rooms/room.gd"),
    ("Script", "res://camera/camera_zone.gd"),
    ("Script", "res://camera/fixed_camera.gd"),
    ("Script", "res://fx/flicker_light.gd"),
    ("Material", "res://rooms/materials/concrete.tres"),
    ("Material", "res://rooms/materials/wall.tres"),
    ("Material", "res://rooms/materials/wood.tres"),
    ("Material", "res://rooms/materials/metal.tres"),
    ("Material", "res://rooms/materials/rust.tres"),
    ("Material", "res://rooms/materials/door_lamp.tres"),
    ("Material", "res://rooms/materials/exit.tres"),
    ("Material", "res://rooms/materials/vent.tres"),
    ("PackedScene", "res://props/locker.tscn"),
]
EXT_ID = {"room": 1, "zone": 2, "cam": 3, "flicker": 4, "concrete": 5, "wall": 6, "wood": 7, "metal": 8, "rust": 9, "lamp": 10, "exit": 11, "vent": 12, "locker": 13}
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


TABLE_TOP = 1.1  # spód blatu: kucający gracz (1.0 m) mieści się pod spodem, stojący i potwór nie


def table(pos, length, depth, mat="wood"):
    """Długi stół z prześwitem pod blatem (kryjówka dla kucającego). pos = środek na podłodze."""
    x, z = pos
    parts = [("box", (x, TABLE_TOP + 0.05, z), (length, 0.1, depth), mat)]
    for dx in (-length / 2 + 0.08, length / 2 - 0.08):
        for dz in (-depth / 2 + 0.08, depth / 2 - 0.08):
            parts.append(("box", (x + dx, TABLE_TOP / 2, z + dz), (0.1, TABLE_TOP, 0.1), "metal"))
    return parts


GRID = 2.0  # siatka mapy: patrz snap_room()


def snap_room(sx, sz, outer):
    """Siatka 2 m: zewnętrzne wymiary pokoju (ze ścianami) są parzyste, a przejścia jednego pokoju
    różnią się pozycją o wielokrotność 2 m. Wtedy przejścia wszystkich pokoi na mapie leżą na
    wspólnej siatce, więc dwa wolne przejścia mogą trafić w siebie albo dać się połączyć
    łącznikiem o długości z siatki (pętle, game/map_generator.gd).
    Pokój projektujemy we "wnętrzu" sx x sz; tu wnętrze dopasowuje się do siatki, a całe
    wyposażenie skaluje się razem z nim (meble przy ścianie zostają przy ścianie)."""
    w = outer[0] if outer else GRID * round((sx + 2 * T) / GRID)
    d = outer[1] if outer else GRID * round((sz + 2 * T) / GRID)
    return w - 2 * T, d - 2 * T, (w - 2 * T) / sx, (d - 2 * T) / sz


def check_grid(name, sx, sz, doors):
    points = []
    for _, side, off, _y in doors:
        points.append({"N": (off, -(sz / 2 + T)), "S": (off, sz / 2 + T),
                       "E": (sx / 2 + T, off), "W": (-(sx / 2 + T), off)}[side])
    for a in points:
        for b in points:
            for k in (0, 1):
                diff = (a[k] - b[k]) / GRID
                assert abs(diff - round(diff)) < 1e-6, f"{name}: przejścia poza siatką {GRID} m: {a} vs {b}"


def build(name, sx, sz, h, doors, solids=(), zones=(), lights=(), loot=(), ambient=(), spawns=(), exit_point=None, vent=None, lockers=(), outer=None):
    """doors: [(nazwa, strona N/S/E/W, offset wzdłuż ściany, y podłogi przejścia)]
    solids: [("box", pos, size, mat)], [("cyl", pos, promień, wysokość, mat)] (np. beczka)
            albo [("prism", [(x, y), ...], z0, z1, mat)] (profil w XY, wyciągnięty wzdłuż Z)
    zones: [(nazwa, (x0, x1, z0, z1), poz. kamery, cel kamery, follow, priorytet[, (y0, y1)])]
    outer: (szer., głęb.) ze ścianami, gdy zaokrąglenie do siatki nie wystarcza (patrz snap_room)."""
    sx, sz, kx, kz = snap_room(sx, sz, outer)

    def at(p):  # pozycja z projektu -> pozycja w dopasowanym do siatki pokoju
        return (p[0] * kx, p[1], p[2] * kz)

    check_grid(name, sx, sz, doors)
    solids = [(sd[0], at(sd[1])) + tuple(sd[2:]) if sd[0] != "prism"
              else ("prism", [(x * kx, y) for x, y in sd[1]], sd[2] * kz, sd[3] * kz, sd[4]) for sd in solids]
    zones = [(z[0], (z[1][0] * kx, z[1][1] * kx, z[1][2] * kz, z[1][3] * kz), at(z[2]), at(z[3])) + tuple(z[4:]) for z in zones]
    lights = [(at(l[0]),) + tuple(l[1:]) for l in lights]
    loot = [(m[0], at(m[1])) + tuple(m[2:]) for m in loot]
    ambient = [(m[0], at(m[1])) + tuple(m[2:]) for m in ambient]
    spawns = [(m[0], at(m[1])) + tuple(m[2:]) for m in spawns]
    if exit_point:
        exit_point = (at(exit_point[0]),) + tuple(exit_point[1:])
    lockers = [(at(pos), yaw) for pos, yaw in lockers]
    if vent:
        vent = (vent[0] * kx, vent[1] * kz)
    nodes, subs = [], []

    def box(node_name, pos, size, mat):
        nodes.append(
            f'[node name="{node_name}" type="CSGBox3D" parent="Geometry"]\n'
            f"transform = {tf(*pos)}\nsize = Vector3({v(*size)})\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    def cyl(node_name, pos, radius, height, mat):
        nodes.append(
            f'[node name="{node_name}" type="CSGCylinder3D" parent="Geometry"]\n'
            f"transform = {tf(*pos)}\nradius = {radius:g}\nheight = {height:g}\nsides = 10\n"
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
        elif solid[0] == "cyl":
            cyl(f"Solid{i}", solid[1], solid[2], solid[3], solid[4])
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
    if lights:
        subs.append('[sub_resource type="BoxMesh" id="lamp_mesh"]\nsize = Vector3(0.7, 0.08, 0.35)\n'
                    f'material = ExtResource("{EXT_ID["lamp"]}")\n')
    for i, (pos, color, energy, rng, flicker) in enumerate(lights):
        # Widoczna oprawa przy suficie nad źródłem światła (bez kolizji, tylko wygląd).
        nodes.append(f'[node name="Fixture{i}" type="MeshInstance3D" parent="Lights"]\n'
                     f"transform = {tf(pos[0], pos[1] + 0.25, pos[2])}\nmesh = SubResource(\"lamp_mesh\")\ncast_shadow = 0\n")
        script = f'script = ExtResource("{EXT_ID["flicker"]}")\n' if flicker else ""
        nodes.append(
            f'[node name="Light{i}" type="OmniLight3D" parent="Lights"]\n'
            f"transform = {tf(*pos)}\nlight_color = Color({v(*color)}, 1)\nlight_energy = {energy * LIGHT_SCALE:g}\n"
            f"shadow_enabled = true\nomni_range = {rng:g}\n"
            # Wygaszanie z odległością: na dużych mapach dalekie światła nic nie kosztują.
            f"distance_fade_enabled = true\ndistance_fade_begin = 30.0\ndistance_fade_shadow = 20.0\ndistance_fade_length = 10.0\n{script}"
        )

    markers("LootSpawns", loot)
    markers("AmbientPoints", ambient)
    if spawns:
        markers("PlayerSpawns", spawns)
    if exit_point:
        markers("ExitPoint", [("Exit",) + tuple(exit_point)])
    if lockers:
        nodes.append('[node name="HidingSpots" type="Node3D" parent="."]\n')
        for i, (pos, yaw) in enumerate(lockers):
            nodes.append(f'[node name="Locker{i}" parent="HidingSpots" instance=ExtResource("{EXT_ID["locker"]}")]\n'
                         f"transform = {tf(*pos, yaw)}\n")
    if vent:
        # Kratka wentylacji w suficie: ciemna płyta z listwami (wygląd), znacznik tuż pod nią.
        vx, vz = vent
        box("VentFrame", (vx, h - 0.03, vz), (1.2, 0.06, 1.2), "vent")
        for k in range(-2, 3):
            box(f"VentSlat{k + 2}", (vx + k * 0.22, h - 0.09, vz), (0.06, 0.06, 1.1), "metal")
        markers("Vents", [("Vent0", (vx, h - 0.15, vz))])

    # Bryła pokoju (ze ścianami) do testu kolizji przy składaniu mapy.
    bounds = f"AABB({v(-(sx / 2 + T), -0.2, -(sz / 2 + T), sx + 2 * T, h + 0.4, sz + 2 * T)})"
    header = f"[gd_scene load_steps={len(EXT) + len(subs) + 1} format=3]\n\n"
    header += "\n".join(f'[ext_resource type="{t}" path="{p}" id="{i + 1}"]' for i, (t, p) in enumerate(EXT)) + "\n\n"
    body = "\n".join(subs) + "\n" if subs else ""
    root = (f'[node name="{name}" type="Node3D"]\nscript = ExtResource("{EXT_ID["room"]}")\nbounds = {bounds}\n\n'
            '[node name="Geometry" type="CSGCombiner3D" parent="."]\nuse_collision = true\n\n')
    file_name = re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()  # CorridorL -> corridor_l
    (OUT / f"{file_name}.tscn").write_text(header + body + "\n" + root + "\n".join(nodes))
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
        ("box", (-4.8, 0.25, -2.6), (0.45, 0.5, 0.45), "wood"),  # krzesła przy stole
        ("box", (-3.2, 0.25, -2.6), (0.45, 0.5, 0.45), "wood"),
        ("box", (3.5, 0.5, -5.5), (3.0, 1.0, 0.9), "rust"),     # stół warsztatowy
        ("box", (4.2, 1.15, -5.5), (0.6, 0.3, 0.35), "metal"),  # skrzynka z narzędziami
        ("cyl", (6.9, 0.6, -4.6), 0.4, 1.2, "rust"),             # beczki
        ("cyl", (6.0, 0.6, -5.3), 0.4, 1.2, "rust"),
        ("box", (0, 4.5, 5.6), (16, 0.25, 0.25), "metal"),       # rury pod sufitem
        ("box", (0, 4.15, 5.65), (16, 0.15, 0.15), "rust"),
        *table((1.5, -1.0), 3.2, 1.3),  # stół z prześwitem: wyspa do krążenia i kryjówka
        # wyjście z mapy: drzwi windy w zachodniej ścianie, zielona futryna i znak
        ("box", (-7.95, 1.3, 3.5), (0.1, 2.6, 2.0), "metal"),
        ("box", (-7.92, 1.45, 2.4), (0.15, 2.9, 0.15), "exit"),
        ("box", (-7.92, 1.45, 4.6), (0.15, 2.9, 0.15), "exit"),
        ("box", (-7.92, 2.85, 3.5), (0.15, 0.15, 2.35), "exit"),
        ("box", (-7.94, 3.3, 3.5), (0.1, 0.35, 1.0), "exit"),
    ],
    zones=[
        ("West", (-8, 1, -6, 6), (7.6, 4.6, -5.6), (-4, 0.6, 2), 0.0, 0),
        ("East", (-1, 8, -6, 6), (-7.6, 4.6, -5.6), (4, 0.6, 2), 0.0, 0),
    ],
    lights=[((-4, 4.5, 0), WARM, 1.1, 10.0, False), ((4, 4.5, 0), WARM, 1.0, 10.0, True)],
    loot=[("Loot0", (-4, 0.95, -3.5))],
    ambient=[("Ambient0", (-7, 1, 5))],
    spawns=[("Spawn0", (-5, 0.05, 1.5), -90), ("Spawn1", (-5, 0.05, 0), -90),
            ("Spawn2", (-6.2, 0.05, 1.5), -90), ("Spawn3", (-6.2, 0.05, 0), -90),
            ("Spawn4", (-5, 0.05, -1.5), -90)],
    exit_point=((-7.2, 0.05, 3.5), -90),
    lockers=[((-6.0, 0, -5.55), 0), ((-4.9, 0, -5.55), 0), ((-3.8, 0, -5.55), 0)],
    vent=(2, 3),
)

# Corridor: 16x4, drzwi na obu końcach. Kamery na końcach patrzą wzdłuż na przeciwległe drzwi.
build(
    "Corridor", 16, 4, 4.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (3, 0.4, 1.4), (0.8, 0.8, 0.8), "wood"),
        ("box", (1.5, 0.6, -1.7), (1.6, 1.2, 0.45), "rust"),   # niska szafka
        ("cyl", (5.6, 0.6, 1.5), 0.4, 1.2, "rust"),             # beczka
        ("box", (-1.5, 0.3, 1.6), (0.9, 0.6, 0.6), "wood"),     # skrzynka
        ("box", (0, 3.6, -1.75), (16, 0.2, 0.2), "metal"),      # rury wzdłuż ściany
        ("box", (0, 3.3, -1.8), (16, 0.12, 0.12), "rust"),
    ],
    zones=[
        ("WestHalf", (-8, 1, -2, 2), (7.6, 3.6, 1.4), (-5, 0.8, 0), 0.35, 0),
        ("EastHalf", (-1, 8, -2, 2), (-7.6, 3.6, -1.4), (5, 0.8, 0), 0.35, 0),
    ],
    lights=[((-4, 3.6, 0), COLD, 0.8, 7.0, False), ((4, 3.6, 0), COLD, 0.8, 7.0, True)],
    ambient=[("Ambient0", (5, 3.4, 0))],
    vent=(-6, 0),
    lockers=[((-4, 0, -1.55), 0)],
)

# Storage: 20x20, dwa regały tworzą trzy alejki po ~6 m. Drzwi na zachód i na wschód.
build(
    "Storage", 20, 20, 6.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        ("box", (2.0, 1.1, -3.5), (9, 2.2, 1.0), "metal"),    # regał A
        ("box", (2.0, 1.1, 3.5), (9, 2.2, 1.0), "metal"),     # regał B
        ("box", (8.8, 0.6, -8.8), (1.2, 1.2, 1.2), "wood"),
        ("box", (8.8, 0.6, -7.4), (1.2, 1.2, 1.2), "wood"),
        ("box", (8.8, 1.8, -8.8), (1.2, 1.2, 1.2), "wood"),
        ("box", (-8.8, 0.5, -8.8), (1.0, 1.0, 1.0), "wood"),
        # towar na regałach
        ("box", (1.0, 2.5, -3.5), (1.2, 0.6, 0.8), "wood"),
        ("box", (3.0, 2.45, -3.5), (0.9, 0.5, 0.8), "wood"),
        ("box", (2.0, 2.5, 3.5), (1.4, 0.6, 0.8), "wood"),
        ("box", (5.0, 2.4, 3.5), (0.7, 0.4, 0.7), "metal"),
        # palety ze skrzyniami w alejkach przy ścianach
        ("box", (0, 0.08, -8.6), (1.4, 0.16, 1.2), "wood"),
        ("box", (0, 0.65, -8.6), (1.1, 1.0, 1.0), "wood"),
        ("box", (3.5, 0.08, 8.6), (1.4, 0.16, 1.2), "wood"),
        ("box", (3.5, 0.55, 8.6), (1.2, 0.8, 1.0), "wood"),
        ("box", (3.5, 1.25, 8.6), (0.8, 0.6, 0.8), "wood"),
        # beczki w kącie
        ("cyl", (-8.6, 0.6, 8.6), 0.4, 1.2, "rust"),
        ("cyl", (-7.7, 0.6, 8.7), 0.4, 1.2, "rust"),
        ("cyl", (-8.5, 0.6, 7.7), 0.4, 1.2, "rust"),
        *table((8.2, 3.0), 2.6, 1.2, "rust"),  # stół warsztatowy z prześwitem przy wschodnim pasie
    ],
    zones=[
        ("Entry", (-10, -2.5, -10, 10), (2, 5.6, -9.6), (-7, 0.6, 2), 0.25, 0),
        ("NorthAisle", (-4.5, 10, -10, -3.5), (9.6, 5.4, -9.6), (-3, 0.6, -7), 0.2, 0),
        ("MiddleAisle", (-4.5, 10, -4, 4), (-9.4, 5.4, 0.5), (7, 0.6, 0), 0.3, 0),
        ("SouthAisle", (-4.5, 10, 3.5, 10), (9.6, 5.4, 9.6), (-3, 0.6, 7), 0.0, 0),
        # Pas za regałami przy wschodnich drzwiach: widok znad środka magazynu.
        ("EastEnd", (6.5, 10, -10, 10), (0, 5.7, 0), (9, 0.6, 0), 0.25, 1),
    ],
    lights=[((-6, 5.5, 0), (1.0, 0.75, 0.5), 1.0, 11.0, False), ((4, 5.5, -7), (0.6, 0.75, 1.0), 0.9, 10.0, False),
            ((4, 5.5, 7), (1.0, 0.75, 0.5), 0.9, 10.0, True), ((4, 5.5, 0), (1.0, 0.75, 0.5), 0.8, 9.0, False)],
    loot=[("Loot0", (8.8, 2.45, -8.8)), ("Loot1", (-8.8, 1.05, -8.8))],
    ambient=[("Ambient0", (9, 1, 9)), ("Ambient1", (0, 5, -7))],
    vent=(-6, 6),
    lockers=[((-9.55, 0, -6.0), 90), ((-9.55, 0, -4.9), 90)],  # front szafki (+Z) do środka pokoju
)

# Turn: 6x6, zakręt (drzwi na zachód i na północ). Jedno ujęcie.
build(
    "Turn", 6, 6, 4.0,
    doors=[("West", "W", 0, 0), ("North", "N", 0, 0)],
    solids=[
        ("box", (2.2, 0.5, -2.2), (0.9, 1.0, 0.9), "wood"),
        ("cyl", (-2.3, 0.6, 2.3), 0.4, 1.2, "rust"),
        ("box", (0.8, 3.5, 2.75), (4, 0.2, 0.2), "metal"),  # rura
    ],
    zones=[("All", (-3, 3, -3, 3), (2.8, 3.6, 2.8), (-1.5, 0.5, -1.5), 0.25, 0)],
    lights=[((0, 3.6, 0), COLD, 0.6, 6.0, True)],
    ambient=[("Ambient0", (2.2, 3.2, -2.2))],
    vent=(-1.5, 1.5),
    outer=(8, 8),  # przejścia na sąsiednich ścianach: połowa boku musi być parzysta
)

# Junction: 10x10, skrzyżowanie T (zachód, wschód, północ). Bez filara, jedno ujęcie.
build(
    "Junction", 10, 10, 4.5,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("North", "N", 0, 0)],
    solids=[
        ("box", (-4, 0.5, 4), (1.0, 1.0, 1.0), "wood"),
        ("cyl", (4.1, 0.6, 4.1), 0.4, 1.2, "rust"),
        ("cyl", (3.3, 0.6, 4.4), 0.4, 1.2, "rust"),
        *table((0, -1.0), 3.0, 1.2),  # wyspa na środku: krążenie i kryjówka
        ("box", (3.8, 0.5, -4.4), (2.0, 1.0, 0.8), "rust"),     # stół warsztatowy
        ("box", (3.6, 1.15, -4.4), (0.5, 0.3, 0.3), "metal"),
    ],
    # Kamera stromo w dół: widzi też pas tuż pod sobą (wykryte mapą pokrycia, tools/coverage_map.gd).
    zones=[("All", (-5, 5, -5, 5), (0, 4.3, 4.9), (0, 0, 0.5), 0.2, 0)],
    lights=[((0, 4.1, -1), WARM, 0.8, 10.0, False)],
    ambient=[("Ambient0", (-4, 1, -4))],
    vent=(2, 2),
    lockers=[((-4.3, 0, -4.55), 0)],
    outer=(12, 12),
)

# Closet: 7x7, ślepy zaułek ze znaleziskami. Jedno ujęcie.
build(
    "Closet", 7, 7, 4.0,
    doors=[("West", "W", 0, 0)],
    solids=[
        ("box", (2.5, 0.5, -2.5), (1, 1, 1), "wood"),
        ("box", (2.6, 0.4, 2.6), (0.8, 0.8, 0.8), "wood"),
        ("box", (0.5, 1.0, -3.2), (2.0, 2.0, 0.6), "metal"),
        ("box", (3.2, 1.0, 0.2), (0.6, 2.0, 2.4), "metal"),     # regał przy wschodniej ścianie
        ("cyl", (-2.6, 0.6, -2.6), 0.4, 1.2, "rust"),
        ("box", (-2.4, 0.3, 2.6), (1.0, 0.6, 0.7), "wood"),
    ],
    zones=[("All", (-3.5, 3.5, -3.5, 3.5), (3.2, 3.6, 3.2), (-2, 0.6, -1), 0.2, 0)],
    lights=[((0.5, 3.6, 0), WARM, 0.6, 6.0, True)],
    loot=[("Loot0", (2.5, 1.05, -2.5)), ("Loot1", (0.5, 2.05, -3.2))],
    vent=(-1, 1),
    lockers=[((-3.05, 0, 2.6), 90)],
)

# Ramp: 16x4, korytarz w górę o jedno piętro. Dolne drzwi na zachodzie, górne na wschodzie.
build(
    "Ramp", 16, 4, S + 4.0,
    doors=[("Low", "W", 0, 0), ("High", "E", 0, S)],
    solids=[
        ("prism", [(-5, 0), (5, 0), (5, S)], -2, 2, "concrete"),
        ("box", (6.5, S / 2, 0), (3, S, 4), "concrete"),  # górny podest
        ("box", (0, S + 3.4, -1.75), (16, 0.2, 0.2), "metal"),  # rury pod sufitem
        ("box", (-6.8, 0.4, 1.4), (0.8, 0.8, 0.8), "wood"),
    ],
    zones=[
        ("Lower", (-8, 1, -2, 2), (7.6, S + 3.4, 1.4), (-4, 0.8, 0), 0.4, 0),
        ("Upper", (-1, 8, -2, 2), (-7.6, S + 2.6, -1.4), (6, S + 0.6, 0), 0.4, 0),
    ],
    lights=[((-6, 3.8, 0), COLD, 0.7, 8.0, False), ((6, S + 3.6, 0), WARM, 0.6, 7.0, True)],
    ambient=[("Ambient0", (0, S, 0))],
    vent=(-6.5, 0),
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
        ("box", (-4.4, 0.4, -3.5), (0.8, 0.8, 0.7), "wood"),
        ("cyl", (-4.3, S + 0.6, 3.4), 0.4, 1.2, "rust"),
    ],
    zones=[
        # Każda kamera stoi nad "swoją" stroną klatki, żeby bryła drugiego biegu nie zasłaniała drzwi.
        ("Low", (-5, 5, -4, 0.6), (4.6, S + 4.0, -3.6), (-3, 0.5, -2), 0.3, 0),
        ("High", (-5, 5, -0.6, 4), (4.6, S + 4.0, 3.6), (-3, S + 0.5, 2), 0.3, 0),
    ],
    lights=[((0, S + 4.1, 0), COLD, 0.8, 10.0, True)],
    ambient=[("Ambient0", (4.2, S / 2 + 0.5, 0))],
    vent=(-3.5, -2.5),
)

# --- Łączniki (siatka 2 m) --------------------------------------------------------
# Gołe korytarze o długości z siatki i narożnik 4x4. Generator mapy domyka nimi pętle między
# dwoma wolnymi przejściami (game/map_generator.gd, _close_loops). Szerokość 4 m ze ścianami.
LINK_LENGTHS = range(4, 18, 2)


def link(length):
    li = length - 2 * T
    half = li / 2
    lights = [((0, 3.6, 0), COLD, 0.7, max(6.0, li * 0.6), False)] if length >= 6 else []
    build(
        f"Link{length}", li, 3.6, 4.0,
        doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
        solids=[("box", (0, 3.6, -1.55), (li + 0.4, 0.2, 0.2), "metal")],  # rura wzdłuż ściany
        zones=[
            ("WestHalf", (-half, 0.3, -1.8, 1.8), (half - 0.4, 3.6, 1.2), (-half + 1.0, 0.8, 0), 0.3, 0),
            ("EastHalf", (-0.3, half, -1.8, 1.8), (-half + 0.4, 3.6, -1.2), (half - 1.0, 0.8, 0), 0.3, 0),
        ],
        lights=lights,
        vent=(0, 0),
    )


for n in LINK_LENGTHS:
    link(n)

# Bend: narożnik korytarza 4x4 (zachód i północ).
build(
    "Bend", 3.6, 3.6, 4.0,
    doors=[("West", "W", 0, 0), ("North", "N", 0, 0)],
    zones=[("All", (-1.8, 1.8, -1.8, 1.8), (1.4, 3.5, 1.4), (-0.8, 0.5, -0.8), 0.2, 0)],
    lights=[((0, 3.6, 0), COLD, 0.6, 5.0, False)],
    vent=(0.6, 0.6),
)

# --- Prawdziwe korytarze (15i) -----------------------------------------------------
# Kształty L, T i X z ramionami szerokości 4 m (ze ścianami). Bryła do kolizji to prostokąt,
# a to, co nie jest korytarzem, wypełniają pełne bloki ściany od podłogi do sufitu.
CH = 4.0  # wysokość korytarzy


def fill(x0, x1, z0, z1):
    return ("box", ((x0 + x1) / 2, CH / 2, (z0 + z1) / 2), (x1 - x0, CH, z1 - z0), "wall")


# CorridorL: zachód -> narożnik -> północ. Ramię poziome z 0..4, pionowe x 0..4 (zewn.).
build(
    "CorridorL", 7.6, 7.6, CH,
    doors=[("West", "W", 2, 0), ("North", "N", 2, 0)],
    solids=[
        fill(-3.8, 0.2, -3.8, 0.2),
        ("box", (2.0, 3.6, 3.65), (7.6, 0.2, 0.2), "metal"),  # rura
        ("box", (-2.6, 0.4, 3.2), (0.8, 0.8, 0.7), "wood"),
    ],
    zones=[("All", (-3.8, 3.8, -3.8, 3.8), (3.4, 3.6, 3.4), (-1.0, 0.5, -1.0), 0.3, 0)],
    lights=[((2, 3.6, 2), COLD, 0.7, 7.0, False)],
    ambient=[("Ambient0", (2, 3.4, -2))],
    vent=(2, 2),
    outer=(8, 8),
)

# CorridorT: poziomy pasek (zachód-wschód) na z 0..4, ramię na północ x -2..2 (zewn.).
build(
    "CorridorT", 11.6, 7.6, CH,
    doors=[("West", "W", 2, 0), ("East", "E", 2, 0), ("North", "N", 0, 0)],
    solids=[
        fill(-5.8, -1.8, -3.8, 0.2),
        fill(1.8, 5.8, -3.8, 0.2),
        ("box", (0, 3.6, 3.65), (11.6, 0.2, 0.2), "metal"),
        ("cyl", (4.6, 0.6, 3.3), 0.4, 1.2, "rust"),
    ],
    zones=[
        ("WestHalf", (-5.8, 0.2, 0.2, 3.8), (5.4, 3.6, 3.4), (-4.6, 0.8, 2), 0.3, 0),
        ("EastHalf", (-0.2, 5.8, 0.2, 3.8), (-5.4, 3.6, 0.6), (4.6, 0.8, 2), 0.3, 0),
        ("NorthArm", (-1.8, 1.8, -3.8, 0.2), (1.2, 3.6, 3.4), (0, 0.8, -3), 0.2, 1),
    ],
    lights=[((0, 3.6, 2), COLD, 0.8, 8.0, False)],
    ambient=[("Ambient0", (-4, 3.4, 2))],
    vent=(0, 2),
    outer=(12, 8),
)

# CorridorX: skrzyżowanie czterech ramion szerokości 4 m.
build(
    "CorridorX", 11.6, 11.6, CH,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("North", "N", 0, 0), ("South", "S", 0, 0)],
    solids=[
        fill(-5.8, -1.8, -5.8, -1.8), fill(1.8, 5.8, -5.8, -1.8),
        fill(-5.8, -1.8, 1.8, 5.8), fill(1.8, 5.8, 1.8, 5.8),
        ("box", (-4.6, 0.4, 1.3), (0.8, 0.8, 0.7), "wood"),
    ],
    zones=[
        ("West", (-5.8, 0, -1.8, 1.8), (5.4, 3.6, 1.2), (-4.6, 0.8, 0), 0.3, 0),
        ("East", (0, 5.8, -1.8, 1.8), (-5.4, 3.6, -1.2), (4.6, 0.8, 0), 0.3, 0),
        ("North", (-1.8, 1.8, -5.8, -1.8), (1.2, 3.6, 5.4), (0, 0.8, -4.6), 0.3, 1),
        ("South", (-1.8, 1.8, 1.8, 5.8), (-1.2, 3.6, -5.4), (0, 0.8, 4.6), 0.3, 1),
    ],
    lights=[((0, 3.6, 0), COLD, 0.8, 9.0, True)],
    ambient=[("Ambient0", (0, 3.4, -4))],
    vent=(0, 0),
    outer=(12, 12),
)
