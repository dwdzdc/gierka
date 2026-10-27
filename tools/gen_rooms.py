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
    ("Material", "res://rooms/materials/skylight.tres"),
    ("Material", "res://rooms/materials/tile.tres"),
    ("Material", "res://rooms/materials/cloth.tres"),
]
EXT_ID = {"room": 1, "zone": 2, "cam": 3, "flicker": 4, "concrete": 5, "wall": 6, "wood": 7, "metal": 8, "rust": 9, "lamp": 10, "exit": 11, "vent": 12, "locker": 13, "skylight": 14,
          "tile": 15, "cloth": 16}
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


def group(*parts):
    """Mebel z kilku części (box/cyl). Dopasowanie pokoju do siatki skaluje pozycje, ale nie rozmiary,
    więc części skalowane osobno rozjeżdżają się (nogi obok blatu). Grupa przesuwa się jako całość:
    skaluje się tylko jej punkt zaczepienia (pierwsza część), reszta zachowuje odstępy."""
    return ("group", parts)


def optional(chance, *parts):
    """Drobiazg opcjonalny (15v): rura, beczka, skrzynia... Na mapie stoi z szansą `chance`
    (losuje MapGenerator z RNG mapy, u wszystkich tak samo). W scenie pokoju zawsze jest, więc
    zasady kamer i mapa pokrycia sprawdzają najgorszy przypadek: bez niego jest tylko luźniej.
    Nie oznaczać tak mebli, na których leżą znaczniki łupu, ani kryjówek."""
    return ("optional", chance, parts)


def table(pos, length, depth, mat="wood"):
    """Długi stół z prześwitem pod blatem (kryjówka dla kucającego). pos = środek na podłodze."""
    x, z = pos
    parts = [("box", (x, TABLE_TOP + 0.05, z), (length, 0.1, depth), mat)]
    for dx in (-length / 2 + 0.08, length / 2 - 0.08):
        for dz in (-depth / 2 + 0.08, depth / 2 - 0.08):
            parts.append(("box", (x + dx, TABLE_TOP / 2, z + dz), (0.1, TABLE_TOP, 0.1), "metal"))
    return group(*parts)


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


LOCKER_CLEAR = 0.5  # pół boku kwadratu przed szafką, który musi zostać wolny (15y)
LOCKER_ERRORS = []


def solid_xz_bounds(sd):
    """Obrys bryły w XZ i zakres Y: (x0, x1, z0, z1, y0, y1). Prostokąt opisany, więc z zapasem."""
    kind = sd[0]
    if kind == "box":
        (x, y, z), (w, hh, d) = sd[1], sd[2]
        a = math.radians(sd[4]) if len(sd) > 4 else 0.0
        ex = abs(math.cos(a)) * w / 2 + abs(math.sin(a)) * d / 2
        ez = abs(math.sin(a)) * w / 2 + abs(math.cos(a)) * d / 2
        return (x - ex, x + ex, z - ez, z + ez, y - hh / 2, y + hh / 2)
    if kind == "cyl":
        (x, y, z), r, hh = sd[1], sd[2], sd[3]
        return (x - r, x + r, z - r, z + r, y - hh / 2, y + hh / 2)
    if kind == "prism":
        xs, ys = [p[0] for p in sd[1]], [p[1] for p in sd[1]]
        return (min(xs), max(xs), sd[2], sd[3], min(ys), max(ys))
    if kind == "vprism":
        xs, zs = [p[0] for p in sd[1]], [p[1] for p in sd[1]]
        return (min(xs), max(xs), min(zs), max(zs), sd[2], sd[3])
    if kind == "bars":
        (x0, y0, z0), (x1, y1, z1) = sd[1], sd[2]
        return (min(x0, x1) - 0.05, max(x0, x1) + 0.05, min(z0, z1) - 0.05, max(z0, z1) + 0.05, min(y0, y1), max(y0, y1))
    raise ValueError(kind)


def check_lockers(name, solids, lockers):
    """15y: gracz wychodzi z szafki w punkt `Front` (1 m przed nią, props/locker.tscn). Bryła, która
    tam stoi (także opcjonalna `Opt_`), zamyka go w meblu. Sprawdzamy po przeskalowaniu do siatki."""
    flat = []
    for sd in solids:
        flat.extend(sd[2] if sd[0] == "optional" else [sd])
    for pos, yaw in lockers:
        a = math.radians(yaw)
        fx, fz = pos[0] + math.sin(a), pos[2] + math.cos(a)  # lokalne +Z szafki w świecie (patrz tf)
        for sd in flat:
            x0, x1, z0, z1, y0, y1 = solid_xz_bounds(sd)
            if y1 < 0.3 or y0 > 1.9:  # próg albo coś pod sufitem: nie blokuje
                continue
            if (x0 < fx + LOCKER_CLEAR and x1 > fx - LOCKER_CLEAR and z0 < fz + LOCKER_CLEAR and z1 > fz - LOCKER_CLEAR):
                LOCKER_ERRORS.append(f"{name}: bryła {sd[0]} {sd[1]} stoi przed szafką {pos} (wyjście {fx:.2f}, {fz:.2f})")


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
    def scale_solid(sd):
        if sd[0] == "prism":
            return ("prism", [(x * kx, y) for x, y in sd[1]], sd[2] * kz, sd[3] * kz, sd[4])
        if sd[0] == "vprism":
            return ("vprism", [(x * kx, z * kz) for x, z in sd[1]], sd[2], sd[3], sd[4])
        if sd[0] == "bars":
            p0, p1 = at(sd[1]), at(sd[2])
            along_x = abs(p1[0] - p0[0]) > abs(p1[2] - p0[2])
            k = kx if along_x else kz
            return ("bars", p0, p1, [(g0 * k, g1 * k) for g0, g1 in sd[3]])
        return (sd[0], at(sd[1])) + tuple(sd[2:])

    def place_solid(sd):
        if sd[0] == "optional":
            return [("optional", sd[1], [s for part in sd[2] for s in place_solid(part)])]
        if sd[0] != "group":
            return [scale_solid(sd)]
        anchor = sd[1][0][1]
        moved = at(anchor)
        dx, dz = moved[0] - anchor[0], moved[2] - anchor[2]
        return [(p[0], (p[1][0] + dx, p[1][1], p[1][2] + dz)) + tuple(p[2:]) for p in sd[1]]
    solids = [s for sd in solids for s in place_solid(sd)]
    zones = [(z[0], (z[1][0] * kx, z[1][1] * kx, z[1][2] * kz, z[1][3] * kz), at(z[2]), at(z[3])) + tuple(z[4:]) for z in zones]
    lights = [(at(l[0]),) + tuple(l[1:]) for l in lights]
    loot = [(m[0], at(m[1])) + tuple(m[2:]) for m in loot]
    ambient = [(m[0], at(m[1])) + tuple(m[2:]) for m in ambient]
    spawns = [(m[0], at(m[1])) + tuple(m[2:]) for m in spawns]
    if exit_point:
        exit_point = (at(exit_point[0]),) + tuple(exit_point[1:])
    lockers = [(at(pos), yaw) for pos, yaw in lockers]
    check_lockers(name, solids, lockers)
    if vent:
        vent = (vent[0] * kx, vent[1] * kz)
    nodes, subs = [], []

    def box(node_name, pos, size, mat, yaw=0.0, parent="Geometry"):
        nodes.append(
            f'[node name="{node_name}" type="CSGBox3D" parent="{parent}"]\n'
            f"transform = {tf(*pos, yaw)}\nsize = Vector3({v(*size)})\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    def cyl(node_name, pos, radius, height, mat, parent="Geometry"):
        nodes.append(
            f'[node name="{node_name}" type="CSGCylinder3D" parent="{parent}"]\n'
            f"transform = {tf(*pos)}\nradius = {radius:g}\nheight = {height:g}\nsides = 10\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    def vprism(node_name, points, y0, y1, mat, parent="Geometry"):
        # Profil w XZ wyciągnięty pionowo: CSGPolygon3D obrócony o +90° wokół X
        # (lokalne Y -> świat Z, wyciąganie wzdłuż lokalnego -Z -> świat +Y).
        flat = ", ".join(v(x, z) for x, z in points)
        nodes.append(
            f'[node name="{node_name}" type="CSGPolygon3D" parent="{parent}"]\n'
            f"transform = Transform3D({v(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, y0, 0)})\npolygon = PackedVector2Array({flat})\ndepth = {y1 - y0:g}\n"
            f'material = ExtResource("{EXT_ID[mat]}")\n'
        )

    def prism(node_name, points, z0, z1, mat, parent="Geometry"):
        # CSGPolygon3D wyciąga profil od z=0 w stronę -Z, więc węzeł stoi na z1.
        flat = ", ".join(v(x, y) for x, y in points)
        nodes.append(
            f'[node name="{node_name}" type="CSGPolygon3D" parent="{parent}"]\n'
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

    bars_bodies = []

    def emit(solid, node_name, parent="Geometry"):
        if solid[0] == "box":
            box(node_name, solid[1], solid[2], solid[3], solid[4] if len(solid) > 4 else 0.0, parent)
        elif solid[0] == "bars":
            bars_bodies.append((node_name,) + tuple(solid[1:]))
        elif solid[0] == "vprism":
            vprism(node_name, solid[1], solid[2], solid[3], solid[4], parent)
        elif solid[0] == "cyl":
            cyl(node_name, solid[1], solid[2], solid[3], solid[4], parent)
        else:
            prism(node_name, solid[1], solid[2], solid[3], solid[4], parent)

    for i, solid in enumerate(solids):
        if solid[0] == "optional":
            # Pod-kombinator CSG: generator mapy usuwa go w całości, bryła pokoju przelicza się sama.
            nodes.append(f'[node name="Opt_{i}" type="CSGCombiner3D" parent="Geometry"]\nmetadata/chance = {solid[1]:g}\n')
            for j, part in enumerate(solid[2]):
                emit(part, f"Part{j}", f"Geometry/Opt_{i}")
        else:
            emit(solid, f"Solid{i}" if solid[0] != "bars" else f"Bars{i}")

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

    # Kraty: pręty to same meshe, a kolizja to płaska płyta na warstwie "bars" (4): zatrzymuje
    # graczy i potwory, ale nie zasłania wzroku ani kamer (te pytają tylko warstwę 1).
    if bars_bodies:
        subs.append('[sub_resource type="BoxMesh" id="bar_mesh"]\nsize = Vector3(0.05, 1, 0.05)\n'
                    f'material = ExtResource("{EXT_ID["metal"]}")\n')
    for bname, (x0, y0, z0), (x1, y1, z1), gaps in bars_bodies:
        # Krata od (x0, y0, z0) do (x1, y1, z1): pionowa ściana prętów wzdłuż X albo Z.
        along_x = abs(x1 - x0) > abs(z1 - z0)
        a0, a1 = (x0, x1) if along_x else (z0, z1)
        height = y1 - y0
        nodes.append(f'[node name="{bname}" type="StaticBody3D" parent="."]\ncollision_layer = 8\ncollision_mask = 0\n')
        # Płyty kolizji między przerwami (przerwa = otwarte drzwiczki celi).
        cuts = sorted(gaps)
        segments, cursor = [], a0
        for g0, g1 in cuts:
            if g0 > cursor:
                segments.append((cursor, g0))
            cursor = max(cursor, g1)
        if cursor < a1:
            segments.append((cursor, a1))
        for k, (s0, s1) in enumerate(segments):
            sid = f"{bname}_shape{k}"
            mid = (s0 + s1) / 2
            size = (s1 - s0, height, 0.1) if along_x else (0.1, height, s1 - s0)
            subs.append(f'[sub_resource type="BoxShape3D" id="{sid}"]\nsize = Vector3({v(*size)})\n')
            pos = (mid, y0 + height / 2, z0) if along_x else (x0, y0 + height / 2, mid)
            nodes.append(f'[node name="Shape{k}" type="CollisionShape3D" parent="{bname}"]\n'
                         f'transform = {tf(*pos)}\nshape = SubResource("{sid}")\n')
            n = max(1, int((s1 - s0) / 0.22))
            for b in range(n + 1):
                t = s0 + (s1 - s0) * b / n
                bpos = (t, y0 + height / 2, z0) if along_x else (x0, y0 + height / 2, t)
                nodes.append(f'[node name="Bar{k}_{b}" type="MeshInstance3D" parent="{bname}"]\n'
                             f'transform = Transform3D({v(1, 0, 0, 0, height, 0, 0, 0, 1, *bpos)})\nmesh = SubResource("bar_mesh")\n')
        # poprzeczki u góry i na dole
        for k, yy in enumerate((y0 + 0.1, y1 - 0.1)):
            length = a1 - a0
            mid = (a0 + a1) / 2
            pos = (mid, yy, z0) if along_x else (x0, yy, mid)
            scale = (length / 0.05, 0.05, 1) if along_x else (1, 0.05, length / 0.05)
            nodes.append(f'[node name="Rail{k}" type="MeshInstance3D" parent="{bname}"]\n'
                         f'transform = Transform3D({v(scale[0], 0, 0, 0, scale[1], 0, 0, 0, scale[2], *pos)})\nmesh = SubResource("bar_mesh")\n')

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
        ("box", (-4, 0.45, -3.4), (2.4, 0.9, 1.0), "wood"),     # stół (płytszy: wyjście z szafek, 15y)
        ("box", (5.5, 0.6, 4.2), (1.2, 1.2, 1.2), "wood"),      # skrzynie
        ("box", (4.2, 0.45, 4.6), (0.9, 0.9, 0.9), "wood"),
        ("box", (-7.6, 1.0, -3), (0.6, 2.0, 3), "metal"),       # szafki pod zachodnią ścianą
        ("box", (-4.8, 0.25, -2.6), (0.45, 0.5, 0.45), "wood"),  # krzesła przy stole
        ("box", (-3.2, 0.25, -2.6), (0.45, 0.5, 0.45), "wood"),
        group(("box", (3.5, 0.5, -5.5), (3.0, 1.0, 0.9), "rust"),     # stół warsztatowy
              ("box", (4.2, 1.15, -5.5), (0.6, 0.3, 0.35), "metal")),  # skrzynka z narzędziami
        optional(0.6, ("cyl", (6.9, 0.6, -4.6), 0.4, 1.2, "rust")),             # beczki
        optional(0.6, ("cyl", (6.0, 0.6, -5.3), 0.4, 1.2, "rust")),
        optional(0.6, ("box", (0, 4.5, 5.6), (16, 0.25, 0.25), "metal")),       # rury pod sufitem
        optional(0.6, ("box", (0, 4.15, 5.65), (16, 0.15, 0.15), "rust")),
        table((1.5, -1.0), 3.2, 1.3),  # stół z prześwitem: wyspa do krążenia i kryjówka
    ],
    zones=[
        ("West", (-8, 1, -6, 6), (7.6, 4.6, -5.6), (-4, 0.6, 2), 0.0, 0),
        ("East", (-1, 8, -6, 6), (-7.6, 4.6, -5.6), (4, 0.6, 2), 0.0, 0),
    ],
    lights=[((-4, 4.5, 0), WARM, 1.1, 10.0, False), ((4, 4.5, 0), WARM, 1.0, 10.0, True)],
    loot=[("Loot0", (-4, 0.95, -3.4))],
    ambient=[("Ambient0", (-7, 1, 5))],
    spawns=[("Spawn0", (-5, 0.05, 1.5), -90), ("Spawn1", (-5, 0.05, 0), -90),
            ("Spawn2", (-6.2, 0.05, 1.5), -90), ("Spawn3", (-6.2, 0.05, 0), -90),
            ("Spawn4", (-5, 0.05, -1.5), -90)],
    lockers=[((-6.0, 0, -5.55), 0), ((-4.9, 0, -5.55), 0), ((-3.8, 0, -5.55), 0)],
    vent=(2, 3),
)

# Corridor: 16x4, drzwi na obu końcach. Kamery na końcach patrzą wzdłuż na przeciwległe drzwi.
build(
    "Corridor", 16, 4, 4.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        optional(0.6, ("box", (3, 0.4, 1.4), (0.8, 0.8, 0.8), "wood")),
        ("box", (1.5, 0.6, -1.7), (1.6, 1.2, 0.45), "rust"),   # niska szafka
        optional(0.6, ("cyl", (5.6, 0.6, 1.5), 0.4, 1.2, "rust")),             # beczka
        optional(0.6, ("box", (-1.5, 0.3, 1.6), (0.9, 0.6, 0.6), "wood")),     # skrzynka
        optional(0.6, ("box", (0, 3.6, -1.75), (16, 0.2, 0.2), "metal")),      # rury wzdłuż ściany
        optional(0.6, ("box", (0, 3.3, -1.8), (16, 0.12, 0.12), "rust")),
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
        # regały z towarem
        group(("box", (2.0, 1.1, -3.5), (9, 2.2, 1.0), "metal"),
              ("box", (1.0, 2.5, -3.5), (1.2, 0.6, 0.8), "wood"),
              ("box", (3.0, 2.45, -3.5), (0.9, 0.5, 0.8), "wood")),
        group(("box", (2.0, 1.1, 3.5), (9, 2.2, 1.0), "metal"),
              ("box", (2.0, 2.5, 3.5), (1.4, 0.6, 0.8), "wood"),
              ("box", (5.0, 2.4, 3.5), (0.7, 0.4, 0.7), "metal")),
        group(("box", (8.8, 0.6, -8.8), (1.2, 1.2, 1.2), "wood"),  # stos skrzyń
              ("box", (8.8, 0.6, -7.4), (1.2, 1.2, 1.2), "wood"),
              ("box", (8.8, 1.8, -8.8), (1.2, 1.2, 1.2), "wood")),
        ("box", (-8.8, 0.5, -8.8), (1.0, 1.0, 1.0), "wood"),
        # palety ze skrzyniami w alejkach przy ścianach
        optional(0.7, group(("box", (0, 0.08, -8.6), (1.4, 0.16, 1.2), "wood"),
              ("box", (0, 0.65, -8.6), (1.1, 1.0, 1.0), "wood"))),
        optional(0.7, group(("box", (3.5, 0.08, 8.6), (1.4, 0.16, 1.2), "wood"),
              ("box", (3.5, 0.55, 8.6), (1.2, 0.8, 1.0), "wood"),
              ("box", (3.5, 1.25, 8.6), (0.8, 0.6, 0.8), "wood"))),
        # beczki w kącie
        optional(0.6, ("cyl", (-8.6, 0.6, 8.6), 0.4, 1.2, "rust")),
        optional(0.6, ("cyl", (-7.7, 0.6, 8.7), 0.4, 1.2, "rust")),
        optional(0.6, ("cyl", (-8.5, 0.6, 7.7), 0.4, 1.2, "rust")),
        table((8.2, 3.0), 2.6, 1.2, "rust"),  # stół warsztatowy z prześwitem przy wschodnim pasie
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
        optional(0.6, ("box", (2.2, 0.5, -2.2), (0.9, 1.0, 0.9), "wood")),
        optional(0.6, ("cyl", (-2.3, 0.6, 2.3), 0.4, 1.2, "rust")),
        optional(0.6, ("box", (0.8, 3.5, 2.75), (4, 0.2, 0.2), "metal")),  # rura
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
        optional(0.6, ("box", (-4, 0.5, 4), (1.0, 1.0, 1.0), "wood")),
        optional(0.6, ("cyl", (4.1, 0.6, 4.1), 0.4, 1.2, "rust")),
        optional(0.6, ("cyl", (3.3, 0.6, 4.4), 0.4, 1.2, "rust")),
        table((0, -1.0), 3.0, 1.2),  # wyspa na środku: krążenie i kryjówka
        group(("box", (3.8, 0.5, -4.4), (2.0, 1.0, 0.8), "rust"),     # stół warsztatowy
              ("box", (3.6, 1.15, -4.4), (0.5, 0.3, 0.3), "metal")),
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
        optional(0.6, ("box", (2.6, 0.4, 2.6), (0.8, 0.8, 0.8), "wood")),
        ("box", (0.5, 1.0, -3.2), (2.0, 2.0, 0.6), "metal"),
        ("box", (3.2, 1.0, 0.2), (0.6, 2.0, 2.4), "metal"),     # regał przy wschodniej ścianie
        optional(0.6, ("cyl", (-2.6, 0.6, -2.6), 0.4, 1.2, "rust")),
        optional(0.6, ("box", (0.6, 0.3, 3.0), (1.0, 0.6, 0.7), "wood")),  # nie przed szafką (15y)
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
        optional(0.6, ("box", (0, S + 3.4, -1.75), (16, 0.2, 0.2), "metal")),  # rury pod sufitem
        optional(0.6, ("box", (-6.8, 0.4, 1.4), (0.8, 0.8, 0.8), "wood")),
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
        optional(0.6, ("box", (-4.4, 0.4, -3.5), (0.8, 0.8, 0.7), "wood")),
        optional(0.6, ("cyl", (-4.3, S + 0.6, 3.4), 0.4, 1.2, "rust")),
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
        solids=[optional(0.5, ("box", (0, 3.6, -1.55), (li + 0.4, 0.2, 0.2), "metal"))],  # rura wzdłuż ściany
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
        optional(0.6, ("box", (0, 3.6, 3.65), (7.6, 0.2, 0.2), "metal")),  # rura
        optional(0.6, ("box", (-2.6, 0.4, 3.2), (0.8, 0.8, 0.7), "wood")),
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
        optional(0.6, ("box", (0, 3.6, 3.65), (11.6, 0.2, 0.2), "metal")),
        optional(0.6, ("cyl", (4.6, 0.6, 3.3), 0.4, 1.2, "rust")),
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
        optional(0.6, ("box", (-4.6, 0.4, 1.3), (0.8, 0.8, 0.7), "wood")),
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

# --- Nowe pokoje (15k) ---------------------------------------------------------------

# Cells: lochy. Korytarz wzdłuż X (z -1.8..1.8), po trzy cele z każdej strony za kratą.
# Krata nie zasłania wzroku (warstwa "bars"), drzwiczki każdej celi są otwarte (przerwa w kracie).
# Cela to ślepy zaułek: kryjówka tylko, jeśli potwór nie zajrzy przez kratę.
CELL_X = (-7.8, -2.6, 2.6, 7.8)
build(
    "Cells", 15.6, 11.6, 4.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        # ścianki między celami
        *[("box", (x, 2.0, zc), (0.3, 4.0, 4.0), "wall") for x in (-2.6, 2.6) for zc in (-3.8, 3.8)],
        # kraty z otwartymi drzwiczkami (przerwa ~1 m przy jednej ze ścianek)
        *[("bars", (CELL_X[k], 0, side * 1.8), (CELL_X[k + 1], 2.6, side * 1.8),
           [(CELL_X[k] + 0.3, CELL_X[k] + 1.3)]) for k in range(3) for side in (-1, 1)],
        ("box", (0, 3.3, -1.8), (15.6, 1.4, 0.3), "wall"),  # nadproże nad kratami (północ)
        ("box", (0, 3.3, 1.8), (15.6, 1.4, 0.3), "wall"),   # nadproże (południe)
        # prycze i wiadra w celach
        ("box", (-5.2, 0.25, -5.1), (2.0, 0.5, 0.9), "wood"),
        ("box", (5.2, 0.25, 5.1), (2.0, 0.5, 0.9), "wood"),
        ("box", (0.4, 0.25, -5.1), (2.0, 0.5, 0.9), "wood"),
        optional(0.6, ("cyl", (-1.5, 0.25, 4.8), 0.25, 0.5, "rust")),
        optional(0.6, ("cyl", (6.5, 0.25, -4.6), 0.25, 0.5, "rust")),
        optional(0.6, ("box", (-6.6, 0.15, 3.6), (0.9, 0.3, 1.6), "wood")),  # zbutwiała słoma/sienik
    ],
    zones=[
        ("WestHalf", (-7.8, 0.4, -1.8, 1.8), (7.4, 3.5, 1.2), (-5, 0.7, 0), 0.3, 0),
        ("EastHalf", (-0.4, 7.8, -1.8, 1.8), (-7.4, 3.5, -1.2), (5, 0.7, 0), 0.3, 0),
        # Każda cela: kamera po drugiej stronie korytarza, patrzy przez kratę do środka.
        *[(f"Cell{k}{'N' if side < 0 else 'S'}", (CELL_X[k], CELL_X[k + 1], -5.8, -1.8) if side < 0 else (CELL_X[k], CELL_X[k + 1], 1.8, 5.8),
           ((CELL_X[k] + CELL_X[k + 1]) / 2, 3.3, -side * 1.5), ((CELL_X[k] + CELL_X[k + 1]) / 2, 0.4, side * 4.2), 0.2, 1)
          for k in range(3) for side in (-1, 1)],
    ],
    lights=[((-4, 3.6, 0), WARM, 0.6, 7.0, True), ((4, 3.6, 0), WARM, 0.5, 7.0, False)],
    loot=[("Loot0", (-5.2, 0.55, -5.1)), ("Loot1", (5.2, 0.55, 5.1)), ("Loot2", (0.4, 0.55, -5.1))],
    ambient=[("Ambient0", (0, 3.4, -4)), ("Ambient1", (-5, 3.4, 4))],
    vent=(0, 0),
    outer=(16, 12),
)

# Atrium: wielki hol z fontanną (jak w Amnesii). Wysoko, kolumny po bokach, ławki.
build(
    "Atrium", 19.6, 23.6, 8.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("North", "N", 0, 0)],
    solids=[
        ("cyl", (0, 0.35, 2), 2.4, 0.7, "concrete"),   # niecka fontanny
        ("cyl", (0, 1.4, 2), 0.4, 2.2, "concrete"),    # trzon
        ("cyl", (0, 2.6, 2), 1.1, 0.25, "concrete"),   # górna misa
        ("cyl", (0, 3.0, 2), 0.25, 0.6, "metal"),      # zwieńczenie
        *[("cyl", (x, 4.0, z), 0.45, 8.0, "concrete") for x in (-6.5, 6.5) for z in (-7, 0, 7)],  # kolumny
        ("box", (-8.6, 0.25, -4), (0.8, 0.5, 2.6), "wood"),  # ławki pod ścianami
        ("box", (8.6, 0.25, 5), (0.8, 0.5, 2.6), "wood"),
        ("box", (-4, 0.25, 9.5), (2.6, 0.5, 0.8), "wood"),
        ("box", (0, 7.6, 0), (19.6, 0.3, 0.4), "wood"),      # belki stropu
        ("box", (0, 7.6, -8), (19.6, 0.3, 0.4), "wood"),
        ("box", (0, 7.6, 8), (19.6, 0.3, 0.4), "wood"),
        optional(0.6, ("cyl", (7.8, 0.6, -10.2), 0.4, 1.2, "rust")),
    ],
    # Połowa holu na ujęcie, kamera wysoko nad przeciwległą ścianą (fontanna w środku zasłania
    # tylko wąski pas, a ten widać z drugiej kamery).
    zones=[
        ("North", (-9.8, 9.8, -11.8, 1.0), (0, 6.5, 11.2), (0, 0.5, -6), 0.25, 0),
        ("South", (-9.8, 9.8, 0.0, 11.8), (0, 6.5, -11.2), (0, 0.5, 6), 0.25, 0),
    ],
    lights=[((0, 7.0, 2), WARM, 1.2, 16.0, False), ((-6, 6.5, -8), WARM, 0.7, 10.0, True), ((6, 6.5, 8), WARM, 0.7, 10.0, False)],
    loot=[("Loot0", (0, 0.75, 4.2)), ("Loot1", (8.6, 0.55, 5))],
    ambient=[("Ambient0", (0, 7, -10)), ("Ambient1", (-9, 1, 10))],
    vent=(-6, -4),
    lockers=[((-9.35, 0, 6.0), 90), ((9.35, 0, -6.0), -90)],
)

# Library: rotunda (jak w zamku Dimitrescu). Ośmiokąt (ścięte narożniki), antresola dookoła
# na 3,6 m z regałami i balustradą, wejście rampą, kolumny pod antresolą, stoliki na dole,
# świetlik w suficie. Drzwi tylko na dole (pod antresolą).
MEZZ = 3.6  # wierzch antresoli
RING = 6.8  # wewnętrzna krawędź antresoli od środka
LH = 8.0
build(
    "Library", 19.6, 19.6, LH,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        # ścięte narożniki (ośmiokąt). Ścięcie 3 m zostawia w rogu antresoli ~2,1 m przejścia
        # (przy 5 m zostawało 0,7 m, węziej niż postać: antresoli nie dało się obejść, 15r).
        *[("vprism", [(sx * 9.8, sz * 9.8), (sx * 6.8, sz * 9.8), (sx * 9.8, sz * 6.8)], 0, LH, "wall") for sx in (-1, 1) for sz in (-1, 1)],
        # antresola: cztery pasy pod ścianami
        ("box", (0, MEZZ - 0.15, -8.3), (19.6, 0.3, 3.0), "wood"),
        ("box", (0, MEZZ - 0.15, 8.3), (19.6, 0.3, 3.0), "wood"),
        ("box", (-8.3, MEZZ - 0.15, 0), (3.0, 0.3, 13.6), "wood"),
        ("box", (8.3, MEZZ - 0.15, 0), (3.0, 0.3, 13.6), "wood"),
        # balustrada na wewnętrznej krawędzi (przerwa przy rampie: wschód, z -4.5..-2.5)
        ("box", (0, MEZZ + 0.5, -RING), (2 * RING, 1.0, 0.1), "wood"),
        ("box", (0, MEZZ + 0.5, RING), (2 * RING, 1.0, 0.1), "wood"),
        ("box", (-RING, MEZZ + 0.5, 0), (0.1, 1.0, 2 * RING), "wood"),
        ("box", (RING, MEZZ + 0.5, 2.15), (0.1, 1.0, 9.3), "wood"),
        ("box", (RING, MEZZ + 0.5, -5.65), (0.1, 1.0, 2.3), "wood"),
        # rampa na antresolę (wznosi się wzdłuż +X)
        ("prism", [(0, 0), (RING, 0), (RING, MEZZ)], -4.5, -2.5, "wood"),
        # kolumny pod antresolą (nie w przejściu od drzwi)
        *[("cyl", (x, (MEZZ - 0.3) / 2, z), 0.3, MEZZ - 0.3, "concrete")
          for x, z in [(-RING, -RING), (RING, -RING), (-RING, RING), (RING, RING), (0, -RING), (0, RING), (-RING, -3.4), (-RING, 3.4), (RING, 3.4)]],
        # regały na antresoli, pod ścianami
        ("box", (0, MEZZ + 1.1, -9.45), (8.0, 2.2, 0.6), "wood"),
        ("box", (0, MEZZ + 1.1, 9.45), (8.0, 2.2, 0.6), "wood"),
        ("box", (-9.45, MEZZ + 1.1, -4.0), (0.6, 2.2, 3.0), "wood"),
        ("box", (-9.45, MEZZ + 1.1, 4.0), (0.6, 2.2, 3.0), "wood"),
        ("box", (9.45, MEZZ + 1.1, 4.0), (0.6, 2.2, 3.0), "wood"),
        # niskie regały na dole, pod antresolą, między drzwiami a narożnikami
        ("box", (-9.45, 1.0, 4.2), (0.6, 2.0, 2.4), "wood"),
        ("box", (9.45, 1.0, -4.2), (0.6, 2.0, 2.4), "wood"),
        ("box", (-3.0, 1.0, -9.45), (3.0, 2.0, 0.6), "wood"),
        ("box", (3.0, 1.0, 9.45), (3.0, 2.0, 0.6), "wood"),
        # stoliki i krzesła na środku
        table((-3.0, 2.5), 2.4, 1.2),
        table((3.0, 3.5), 2.4, 1.2),
        ("box", (-3.0, 0.25, 3.6), (0.45, 0.5, 0.45), "wood"),
        ("box", (3.6, 0.25, 4.6), (0.45, 0.5, 0.45), "wood"),
        ("box", (-2.0, 0.25, 1.4), (0.45, 0.5, 0.45), "wood"),
        ("box", (-3.4, 0.5, -1.0), (1.2, 1.0, 0.8), "wood"),  # pulpit
        # świetlik: jasna tafla w suficie
        ("box", (0, LH - 0.02, 0), (4.0, 0.06, 4.0), "skylight"),
    ],
    zones=[
        ("GroundWest", (-9.8, 0.5, -9.8, 9.8), (6.0, 3.0, 6.0), (-5, 0.5, -2), 0.25, 0, (0, 3.4)),
        ("GroundEast", (-0.5, 9.8, -9.8, 9.8), (-6.0, 3.0, -6.0), (5, 0.5, 2), 0.25, 0, (0, 3.4)),
        ("UpperNorth", (-9.8, 9.8, -9.8, 0.5), (0, 7.4, 6.0), (0, MEZZ, -8), 0.25, 1, (3.4, LH)),
        ("UpperSouth", (-9.8, 9.8, -0.5, 9.8), (0, 7.4, -6.0), (0, MEZZ, 8), 0.25, 1, (3.4, LH)),
    ],
    lights=[((0, LH - 1.0, 0), COLD, 1.6, 15.0, False), ((-8, MEZZ + 2.6, 0), WARM, 0.6, 8.0, True),
            ((8, MEZZ + 2.6, 0), WARM, 0.6, 8.0, False), ((0, 3.0, -8.5), WARM, 0.5, 7.0, False)],
    loot=[("Loot0", (-3.0, 1.25, 2.5)), ("Loot1", (0, MEZZ + 0.05, -8.3)), ("Loot2", (-8.3, MEZZ + 0.05, 6))],
    ambient=[("Ambient0", (0, MEZZ + 1, 8.5)), ("Ambient1", (-8.5, 1, -2))],
    vent=(5, 5),
    lockers=[((-9.35, 0, -2.8), 90)],
)

# --- Unikalne pokoje (15u) -------------------------------------------------------------
# Każdy z charakterystycznym rekwizytem i kolorem światła (punkty orientacyjne: „za kotłownią
# w lewo”). Na mapie najwyżej raz na 20 pokoi (MapGenerator.ROOM_LIMITS).
FIRE = (1.0, 0.5, 0.2)
FLUO = (0.8, 1.0, 0.8)
SERVER = (0.45, 0.65, 1.0)

# Boiler: kotłownia. Wielki kocioł z paleniskiem (pomarańczowy blask), drugi mniejszy, rury,
# hałda węgla. Za kotłem wąska nisza przy ścianie (osobne ujęcie).
build(
    "Boiler", 15.6, 11.6, 5.0,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0)],
    solids=[
        group(("cyl", (-1.5, 2.0, -2.6), 1.6, 4.0, "rust"),     # kocioł
              ("cyl", (-1.5, 4.2, -2.6), 1.0, 0.4, "metal"),
              ("cyl", (-1.5, 4.7, -2.6), 0.35, 0.6, "metal"),    # komin do sufitu
              ("box", (-1.5, 0.8, -0.95), (1.0, 0.9, 0.12), "metal")),  # drzwiczki paleniska
        group(("cyl", (3.5, 1.5, -3.6), 1.1, 3.0, "rust"),
              ("cyl", (3.5, 3.9, -3.6), 0.25, 1.8, "metal")),
        optional(0.6, ("box", (0, 4.4, -5.5), (15.6, 0.3, 0.3), "metal")),       # rury pod sufitem
        optional(0.6, ("box", (0, 4.0, -5.55), (15.6, 0.2, 0.2), "rust")),
        ("box", (6.8, 2.5, -5.5), (0.25, 5.0, 0.25), "metal"),    # piony
        ("box", (-6.5, 2.5, -5.5), (0.25, 5.0, 0.25), "metal"),
        ("box", (7.65, 1.6, -2.0), (0.2, 1.2, 1.6), "metal"),     # tablica z zaworami
        group(("box", (-6.2, 0.4, 4.3), (2.6, 0.8, 2.4), "concrete"),  # hałda węgla
              ("box", (-6.4, 1.0, 4.6), (1.6, 0.5, 1.6), "concrete")),
        table((3.0, 4.6), 2.6, 1.0, "rust"),
        optional(0.6, ("cyl", (0.6, 0.6, 4.9), 0.4, 1.2, "rust")),  # beczki (nie pod kamerą w narożniku)
        optional(0.6, ("cyl", (-0.3, 0.6, 5.1), 0.4, 1.2, "rust")),
    ],
    zones=[
        ("West", (-7.8, 0.5, -5.8, 5.8), (6.5, 4.4, 5.2), (-4, 0.5, -2.5), 0.25, 0),
        ("East", (-0.5, 7.8, -5.8, 5.8), (-6.5, 4.4, 5.2), (4, 0.5, -2.5), 0.25, 0),
        ("BehindBoiler", (-4.0, 1.0, -5.8, -4.2), (2.0, 3.6, -5.2), (-3.5, 0.5, -5.0), 0.2, 1),
        ("BehindSmall", (2.0, 7.8, -5.8, -4.5), (0.5, 3.6, -5.3), (6, 0.5, -5.2), 0.2, 1),
    ],
    lights=[((-1.5, 1.2, -0.6), FIRE, 0.9, 7.0, True), ((3, 4.6, 1.5), WARM, 0.7, 10.0, False)],
    loot=[("Loot0", (3.0, 1.25, 4.6)), ("Loot1", (-6.4, 1.3, 4.6))],
    ambient=[("Ambient0", (-1.5, 4.5, -4.5)), ("Ambient1", (6, 1, -4))],
    vent=(2, 2),
    lockers=[((-2.5, 0, 5.55), 180)],
)


def pew(x, z, length=3.0):
    """Ławka kościelna: siedzisko i oparcie od południa (wierni patrzą na północ, na ołtarz)."""
    return group(("box", (x, 0.225, z), (length, 0.45, 0.5), "wood"),
                 ("box", (x, 0.7, z + 0.22), (length, 0.5, 0.08), "wood"))


# Chapel: kaplica. Rzędy ławek po obu stronach nawy, ołtarz z czerwonym suknem na podwyższeniu,
# wysokie okno (świeci jak świetlik) z krzyżem w północnej ścianie.
build(
    "Chapel", 11.6, 19.6, 7.0,
    doors=[("South", "S", 0, 0), ("East", "E", 2, 0)],
    solids=[
        *[pew(side * 2.9, z) for side in (-1, 1) for z in (-4.0, -2.0, 0.0, 2.0, 4.0, 6.0)],
        ("box", (0, 0.1, -7.6), (6.0, 0.2, 2.6), "concrete"),     # podwyższenie
        group(("box", (0, 0.7, -8.0), (2.4, 1.0, 0.9), "concrete"),  # ołtarz
              ("box", (0, 1.225, -8.0), (2.5, 0.05, 1.0), "cloth"),
              ("box", (0, 0.85, -7.53), (1.0, 0.7, 0.03), "cloth")),
        ("box", (0, 4.2, -9.77), (1.6, 3.0, 0.06), "skylight"),   # okno
        ("box", (0, 4.2, -9.7), (0.15, 2.0, 0.06), "metal"),       # krzyż na oknie
        ("box", (0, 4.7, -9.7), (1.0, 0.15, 0.06), "metal"),
        ("cyl", (-2.0, 0.85, -8.6), 0.08, 1.5, "metal"),           # świeczniki
        ("cyl", (2.0, 0.85, -8.6), 0.08, 1.5, "metal"),
        ("box", (0, 0.01, 2.0), (1.4, 0.02, 15.0), "cloth"),       # chodnik w nawie
        ("box", (-5.3, 0.6, 8.6), (0.8, 1.2, 1.6), "wood"),        # skrzynia na śpiewniki
    ],
    zones=[
        ("Altar", (-5.8, 5.8, -9.8, -3.0), (3.5, 6.0, 9.2), (0, 0.5, -7), 0.2, 0),
        ("Nave", (-5.8, 5.8, -3.5, 9.8), (-5.0, 6.0, -8.8), (1.5, 0.5, 4), 0.25, 0),
    ],
    lights=[((0, 6.6, -2), WARM, 1.0, 12.0, False), ((0, 6.6, 5), WARM, 0.8, 10.0, True), ((0, 6.6, -8.5), COLD, 0.7, 8.0, False)],
    loot=[("Loot0", (0, 1.3, -8.0)), ("Loot1", (-2.9, 0.5, 4.0))],
    ambient=[("Ambient0", (0, 5.5, -9)), ("Ambient1", (-4.5, 1, 8))],
    vent=(3, -4),
    lockers=[((-5.55, 0, -5.0), 90)],  # konfesjonał
)

# Canteen: stołówka. Dwa rzędy długich stołów z prześwitem (kryjówki), kuchnia pod północną
# ścianą (blat, kuchenki, okap, lodówka), zielonkawe świetlówki.
build(
    "Canteen", 15.6, 15.6, 4.5,
    doors=[("West", "W", 0, 0), ("East", "E", 0, 0), ("South", "S", 0, 0)],
    solids=[
        table((-3.0, -2.2), 5.0, 1.2),
        table((-3.0, 2.2), 5.0, 1.2),
        table((3.5, -2.2), 4.0, 1.2),
        table((3.5, 2.2), 4.0, 1.2),
        *[("box", (x, 0.225, z), (0.4, 0.45, 0.4), "metal") for x, z in [(-4.5, -1.2), (-2.0, -3.2), (-3.5, 3.2), (2.5, -1.2), (4.5, 3.2), (3.0, 1.2)]],
        group(("box", (0, 0.5, -7.2), (10.0, 1.0, 0.8), "metal"),   # blat kuchenny
              ("box", (-3.5, 1.05, -7.2), (1.2, 0.1, 0.7), "rust"),  # kuchenki
              ("box", (-1.9, 1.05, -7.2), (1.2, 0.1, 0.7), "rust"),
              ("cyl", (-3.8, 1.25, -7.2), 0.25, 0.3, "metal"),       # garnki
              ("cyl", (-1.7, 1.2, -7.1), 0.2, 0.2, "metal"),
              ("box", (3.0, 1.1, -7.3), (1.0, 0.2, 0.4), "wood")),   # tace
        ("box", (-2.7, 3.6, -7.3), (3.2, 0.6, 1.2), "metal"),       # okap
        ("box", (6.9, 1.1, -6.9), (1.2, 2.2, 1.0), "metal"),        # lodówka
        optional(0.6, ("cyl", (6.9, 0.45, 6.6), 0.35, 0.9, "rust")),               # kosze
        optional(0.6, ("cyl", (6.1, 0.45, 6.9), 0.35, 0.9, "rust")),
    ],
    zones=[
        ("West", (-7.8, 0.5, -7.8, 7.8), (7.4, 4.1, -7.4), (-3, 0.5, 2), 0.25, 0),
        ("East", (-0.5, 7.8, -7.8, 7.8), (-7.4, 4.1, -7.4), (3, 0.5, 2), 0.25, 0),
    ],
    lights=[((-3, 4.2, 0), FLUO, 0.8, 9.0, False), ((4, 4.2, 0), FLUO, 0.8, 9.0, True), ((0, 4.2, -6), FLUO, 0.6, 7.0, False)],
    loot=[("Loot0", (-3.0, 1.25, 2.2)), ("Loot1", (0.5, 1.05, -7.2))],
    ambient=[("Ambient0", (-2.7, 3.2, -7)), ("Ambient1", (6, 1, 6))],
    vent=(0, 4),
    lockers=[((-7.35, 0, -5.0), 90)],
)


def filing_row(x):
    """Rząd szaf na akta (2 m) wzdłuż Z, z kartonami na wierzchu."""
    return group(("box", (x, 1.0, 0), (0.7, 2.0, 7.0), "metal"),
                 ("box", (x, 2.15, -2.2), (0.5, 0.3, 0.6), "wood"),
                 ("box", (x, 2.12, 0.4), (0.5, 0.24, 0.5), "wood"),
                 ("box", (x, 2.15, 2.6), (0.55, 0.3, 0.7), "wood"))


# Archive: archiwum. Rzędy szaf na akta wzdłuż Z (alejki prosto od kamer na końcach),
# biurko i katalog kartkowy przy wejściu.
build(
    "Archive", 15.6, 11.6, 4.0,
    doors=[("West", "W", 0, 0), ("North", "N", 4, 0)],
    solids=[
        filing_row(-3.4),
        filing_row(0.2),
        filing_row(5.8),
        table((-6.0, -4.2), 2.0, 1.0),
        ("box", (-6.8, 0.6, 4.4), (1.2, 1.2, 0.6), "wood"),   # katalog kartkowy
        ("box", (7.4, 1.0, 4.4), (0.6, 2.0, 2.4), "metal"),    # szafa pod wschodnią ścianą
        optional(0.6, ("box", (2.0, 0.3, 4.8), (0.8, 0.6, 0.6), "wood")),     # kartony na podłodze
        optional(0.6, ("box", (2.6, 0.25, 5.2), (0.6, 0.5, 0.5), "wood")),
    ],
    zones=[
        ("North", (-7.8, 7.8, -5.8, 0.3), (-2.0, 3.7, 5.4), (2, 0, -4), 0.2, 0),
        ("South", (-7.8, 7.8, -0.3, 5.8), (2.0, 3.7, -5.4), (-2, 0, 4), 0.2, 0),
        # Pas przy zachodnich drzwiach, za pierwszym rzędem szaf: z alejek szafy zasłaniają drzwi.
        ("Entry", (-7.8, -3.75, -5.8, 5.8), (-4.0, 3.7, 5.4), (-6, 0.5, -3), 0.25, 1),
        ("EastAisle", (6.15, 7.8, -5.8, 5.8), (7.0, 3.7, 5.4), (7.0, 0.5, -4), 0.2, 1),
    ],
    lights=[((-1.5, 3.7, -2), COLD, 0.6, 7.0, True), ((2.5, 3.7, 2.5), COLD, 0.6, 7.0, False)],
    loot=[("Loot0", (-6.0, 1.25, -4.2)), ("Loot1", (0.2, 2.35, 0.4))],
    ambient=[("Ambient0", (3, 3.5, 0)), ("Ambient1", (-6, 1, 3))],
    vent=(-5.5, 0),
)

# Showers: prysznice z przebieralnią. Kafle na ścianach, kabiny pod wschodnią ścianą (otwarte
# na zachód), szafki (kryjówki) pod południową, ławka na środku.
build(
    "Showers", 11.6, 11.6, 3.6,
    doors=[("West", "W", 0, 0), ("North", "N", 0, 0)],
    solids=[
        ("box", (0, 1.1, 5.77), (11.6, 2.2, 0.05), "tile"),
        ("box", (5.77, 1.1, 0), (0.05, 2.2, 11.6), "tile"),
        ("box", (-3.4, 1.1, -5.77), (4.8, 2.2, 0.05), "tile"),
        ("box", (3.4, 1.1, -5.77), (4.8, 2.2, 0.05), "tile"),
        ("box", (-5.77, 1.1, -3.4), (0.05, 2.2, 4.8), "tile"),
        ("box", (-5.77, 1.1, 3.4), (0.05, 2.2, 4.8), "tile"),
        *[("box", (4.9, 1.0, z), (1.8, 2.0, 0.08), "tile") for z in (-3.6, -1.2, 1.2, 3.6)],  # ścianki kabin
        *[("box", (5.6, 2.2, z), (0.3, 0.06, 0.15), "metal") for z in (-4.7, -2.4, 0.0, 2.4, 4.7)],  # słuchawki
        ("box", (-1.0, 0.25, 1.0), (3.0, 0.5, 0.5), "wood"),   # ławka
        ("box", (-5.45, 0.85, -3.5), (0.6, 0.15, 1.6), "tile"),  # umywalki
        ("box", (-5.45, 0.85, 3.5), (0.6, 0.15, 1.6), "tile"),
    ],
    zones=[
        ("Room", (-5.8, 3.0, -5.8, 5.8), (5.2, 3.3, 5.2), (-2, 0.5, -2), 0.25, 0),
        ("Stalls", (2.8, 5.8, -5.8, 5.8), (-5.2, 3.3, -5.2), (4.5, 0.5, 1.5), 0.2, 1),
    ],
    lights=[((0, 3.3, -1), (0.8, 0.95, 1.0), 0.7, 8.0, True), ((4.5, 3.3, 2), (0.8, 0.95, 1.0), 0.4, 5.0, False)],
    loot=[("Loot0", (-1.0, 0.55, 1.0))],
    ambient=[("Ambient0", (5, 2.5, -4.7)), ("Ambient1", (-4, 1, -4))],
    vent=(-2, -3),
    lockers=[((-3.5, 0, 5.55), 180), ((-2.4, 0, 5.55), 180), ((-1.3, 0, 5.55), 180)],
)


def rack_row(x):
    """Rząd szaf serwerowych wzdłuż Z: pięć szaf z przerwami, korytka kablowe nad nimi."""
    return group(*[("box", (x, 1.05, z), (1.0, 2.1, 1.9), "metal") for z in (-4.0, -2.0, 0.0, 2.0, 4.0)],
                 ("box", (x, 2.9, 0), (0.4, 0.08, 10.0), "metal"))


# Servers: serwerownia. Dwa rzędy szaf, szeroka alejka na środku (drzwi na obu końcach),
# boczne alejki pod ścianami z klimatyzatorami, niebieskie światło.
build(
    "Servers", 11.6, 15.6, 3.6,
    doors=[("North", "N", 0, 0), ("South", "S", 0, 0)],
    solids=[
        rack_row(-2.7),
        rack_row(2.7),
        ("box", (-5.3, 1.0, -6.6), (0.8, 2.0, 1.6), "metal"),   # klimatyzatory
        ("box", (5.3, 1.0, 6.4), (0.8, 2.0, 1.6), "metal"),
        group(("box", (-4.2, 0.4, 6.6), (2.0, 0.8, 0.9), "wood"),  # pulpit operatora z monitorem
              ("box", (-4.2, 1.05, 6.8), (0.6, 0.45, 0.08), "metal")),
        optional(0.6, ("box", (0, 3.35, -7.0), (11.6, 0.15, 0.4), "metal")),   # korytko pod sufitem
    ],
    zones=[
        ("North", (-2.2, 2.2, -7.8, 0.3), (-1.5, 3.3, 7.4), (0, 0.5, -5), 0.2, 0),
        ("South", (-2.2, 2.2, -0.3, 7.8), (1.5, 3.3, -7.4), (0, 0.5, 5), 0.2, 0),
        ("WestAisle", (-5.8, -2.2, -7.8, 7.8), (-4.3, 3.3, -7.4), (-4.3, 0.5, 4), 0.2, 1),
        ("EastAisle", (2.2, 5.8, -7.8, 7.8), (4.3, 3.3, 7.4), (4.3, 0.5, -4), 0.2, 1),
    ],
    lights=[((0, 3.3, -3), SERVER, 0.6, 8.0, False), ((0, 3.3, 4), SERVER, 0.6, 8.0, True)],
    loot=[("Loot0", (-4.2, 0.85, 6.4))],
    ambient=[("Ambient0", (-5, 1, -6)), ("Ambient1", (4.5, 3, 0))],
    vent=(0, 0),
)


# 15y: dopiero na końcu, żeby zobaczyć wszystkie kolizje naraz (pliki są już zapisane, ale
# niepoprawne pokoje trzeba poprawić przed commitem).
assert not LOCKER_ERRORS, "\n".join(LOCKER_ERRORS)
