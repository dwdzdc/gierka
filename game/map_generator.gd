class_name MapGenerator
extends RefCounted
## Składa mapę z modułów (Room) po ich Doorways. Deterministycznie: ten sam seed i liczba
## pokoi dają tę samą mapę na każdym komputerze, więc przez sieć wysyłamy tylko te dwie liczby.
##
## Algorytm: start od pokoju startowego. W pętli: losowe wolne przejście, losowy typ pokoju
## (według wag), losowe przejście nowego pokoju; obracamy nowy pokój tak, żeby oba przejścia
## stykały się czołami, i sprawdzamy, czy nie wchodzi w już postawione pokoje.
## Na końcu niewykorzystane przejścia są zamurowywane.

const START_ROOM := "res://rooms/hall.tscn"
## Typy pokoi i ich wagi losowania. Więcej przejść = większa szansa na rozgałęzienia.
## Korytarze (ok. 60%) częściej niż pokoje: pokoje mają być raczej "przechodnie" i rzadsze.
const ROOM_TYPES := {
	# korytarze
	"res://rooms/corridor.tscn": 1.5,
	"res://rooms/link8.tscn": 0.8,
	"res://rooms/link12.tscn": 0.8,
	"res://rooms/corridor_l.tscn": 1.5,
	"res://rooms/corridor_t.tscn": 1.6,
	"res://rooms/corridor_x.tscn": 1.0,
	# pokoje
	"res://rooms/storage.tscn": 1.2,
	"res://rooms/junction.tscn": 0.9,
	"res://rooms/turn.tscn": 0.6,
	"res://rooms/closet.tscn": 0.5,  # ślepy zaułek: rzadziej, żeby łatwiej było uciec potworowi
	"res://rooms/cells.tscn": 0.9,  # lochy
	"res://rooms/atrium.tscn": 0.7,  # wielki hol z fontanną
	"res://rooms/library.tscn": 0.6,  # rotunda z antresolą
	# unikalne (15u): każdy najwyżej raz na 20 pokoi
	"res://rooms/boiler.tscn": 0.5,  # kotłownia
	"res://rooms/chapel.tscn": 0.5,  # kaplica
	"res://rooms/canteen.tscn": 0.5,  # stołówka
	"res://rooms/archive.tscn": 0.5,  # archiwum z szafami na akta
	"res://rooms/showers.tscn": 0.5,  # prysznice z przebieralnią
	"res://rooms/servers.tscn": 0.5,  # serwerownia
	# piętra
	"res://rooms/ramp.tscn": 0.6,
	"res://rooms/stairwell.tscn": 0.6,
}
## Pokoje charakterystyczne nie powtarzają się jak korytarze (15s): najwyżej jeden pokój danego
## typu na tyle pokoi mapy (zawsze co najmniej jeden). Przy pięciu bibliotekach żadna nie jest już
## punktem orientacyjnym. Typy spoza listy (korytarze, łączniki, piętra, małe pokoje): bez limitu,
## więc limity nigdy nie blokują składania mapy.
const ROOM_LIMITS := {
	"res://rooms/storage.tscn": 10,
	"res://rooms/closet.tscn": 10,
	"res://rooms/cells.tscn": 10,
	"res://rooms/atrium.tscn": 20,
	"res://rooms/library.tscn": 20,
	"res://rooms/boiler.tscn": 20,
	"res://rooms/chapel.tscn": 20,
	"res://rooms/canteen.tscn": 20,
	"res://rooms/archive.tscn": 20,
	"res://rooms/showers.tscn": 20,
	"res://rooms/servers.tscn": 20,
}
## Każde wystąpienie typu z limitem mnoży jego wagę przez tyle: powtórki, jeśli już są, rzadziej
## lądują obok siebie.
const REPEAT_WEIGHT_FACTOR := 0.5
const MAX_ATTEMPTS := 400
## Bryły sąsiadów stykają się ścianami; zmniejszamy je odrobinę, żeby styk nie był kolizją.
const OVERLAP_TOLERANCE := 0.05

var rooms: Array[Room] = []
## Połączone przejścia: [{"a": Marker3D, "b": Marker3D}] (przydatne do testów i debugowania).
var connections: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _parent: Node3D
var _open: Array[Dictionary] = []  # wolne przejścia: {"room": Room, "door": Marker3D}
var _dead: Array[Dictionary] = []  # przejścia, do których nic się nie zmieściło
## Ile pętli (dodatkowych połączeń) powstało w ostatniej mapie.
var loops := 0
var _door_counts := {}  # ścieżka -> liczba przejść (cache)
var _room_count := 0  # docelowa liczba pokoi bieżącej mapy (do limitów typów)
var _type_counts := {}  # ścieżka sceny -> ile pokoi tego typu już stoi


const MAX_RETRIES := 6
## Od tylu pokoi wymagamy co najmniej jednej pętli (mniejsze mapy często nie mają na nią miejsca).
const MIN_ROOMS_FOR_LOOP := 12


## Składa losową mapę z `room_count` pokoi pod `parent`. Jeśli pokoje się "zablokują"
## (zostanie mniej niż `room_count`) albo nie powstała żadna pętla, próbuje kolejnych wariantów
## seeda i wybiera najlepszy. Też deterministycznie: ten sam seed zawsze daje ten sam wariant.
func generate(parent: Node3D, map_seed: int, room_count: int) -> Array[Room]:
	_parent = parent
	var best_variant := 0
	var best_score := -1
	var wanted_loops := 1 if room_count >= MIN_ROOMS_FOR_LOOP else 0
	for variant in MAX_RETRIES:
		_build_variant(map_seed, variant, room_count)
		var size := rooms.size() - _links
		var loop_count := mini(loops + closed_loops, wanted_loops)
		var score := size * 10 + loop_count
		if score > best_score:
			best_score = score
			best_variant = variant
		if size >= room_count and loop_count >= wanted_loops:
			_decorate()
			_plan_doors()
			return rooms
		_clear()
	_build_variant(map_seed, best_variant, room_count)
	_decorate()
	_plan_doors()
	return rooms


# --- Zmienność z seeda (krok 15/15h) ---------------------------------------------

## Część pokoi jest całkiem ciemna (bez hali startowej): tam latarka ma sens.
## W oświetlonych pokojach część lamp migocze.
const DARK_ROOM_CHANCE := 0.2
const LIGHT_FLICKER_CHANCE := 0.2
const FLICKER_SCRIPT := preload("res://fx/flicker_light.gd")
const WOOD := preload("res://rooms/materials/wood.tres")
const RUST := preload("res://rooms/materials/rust.tres")
const CLUTTER_PER_ROOM := Vector2i(2, 5)
const CLUTTER_KEEP_CLEAR := 2.8  # tyle metrów przed drzwiami, wyjściem i kryjówkami zostaje pusto


## Ten sam typ pokoju za każdym razem trochę inny: ciemne pokoje, migoczące lampy i drobne
## rekwizyty przy ścianach. Wszystko z RNG mapy, więc u każdego peera identycznie.
func _decorate() -> void:
	for room in rooms:
		var dark := room != rooms[0] and _rng.randf() < DARK_ROOM_CHANCE
		room.dark = dark
		for light in room.find_children("*", "OmniLight3D", true, false):
			if dark:
				light.visible = false
			elif _rng.randf() < LIGHT_FLICKER_CHANCE and light.get_script() == null:
				light.set_script(FLICKER_SCRIPT)
				light.set_process(true)  # skrypt doklejony po _ready: Godot sam go nie włączy
		if dark:
			room.switch_off_lamps()
		# Bez ramp i schodów (pochyłe podłogi) i bez wąskich korytarzy (3,6 m): skrzynia pod jedną
		# ścianą i mebel pod drugą potrafiły zatkać przejście.
		if room.bounds.size.y < 8.0 and minf(room.bounds.size.x, room.bounds.size.z) > 4.5 and not _is_corridor(room):
			_add_clutter(room)


func _is_corridor(room: Room) -> bool:
	return room.name.contains("Corridor") or room.name.contains("Link") or room.name.contains("Bend")


func _add_clutter(room: Room) -> void:
	var count := _rng.randi_range(CLUTTER_PER_ROOM.x, CLUTTER_PER_ROOM.y)
	var keep_clear: Array[Vector3] = []
	for marker in room.get_doorways() + room.get_player_spawns():
		keep_clear.append(marker.position)
	if room.get_exit():
		keep_clear.append(room.get_exit().position)
	for spot in room.find_children("Locker*", "", true, false):
		keep_clear.append(spot.position + spot.transform.basis.z)
	var occupied := _solid_footprints(room)
	var inner := room.bounds.grow(-Room.WALL_THICKNESS - 0.5)
	for i in count * 4:  # kilka prób na każdy rekwizyt
		if count == 0:
			break
		# Przy losowej ścianie, 0.5 m od niej.
		var along := _rng.randf()
		var position := Vector3.ZERO
		match _rng.randi_range(0, 3):
			0: position = Vector3(lerpf(inner.position.x, inner.end.x, along), 0, inner.position.z)
			1: position = Vector3(lerpf(inner.position.x, inner.end.x, along), 0, inner.end.z)
			2: position = Vector3(inner.position.x, 0, lerpf(inner.position.z, inner.end.z, along))
			_: position = Vector3(inner.end.x, 0, lerpf(inner.position.z, inner.end.z, along))
		var size := _rng.randf_range(0.6, 0.95)
		var footprint := Rect2(Vector2(position.x, position.z) - Vector2.ONE * size / 2.0, Vector2.ONE * size)
		if keep_clear.any(func(p: Vector3) -> bool: return Vector2(p.x, p.z).distance_to(Vector2(position.x, position.z)) < CLUTTER_KEEP_CLEAR):
			continue
		if occupied.any(func(r: Rect2) -> bool: return r.grow(0.2).intersects(footprint)):
			continue
		occupied.append(footprint)
		_spawn_prop(room, position, size)
		count -= 1


func _spawn_prop(room: Room, position: Vector3, size: float) -> void:
	var prop: CSGShape3D
	if _rng.randf() < 0.4:
		var barrel := CSGCylinder3D.new()
		barrel.radius = size * 0.45
		barrel.height = 1.1
		barrel.sides = 10
		barrel.material = RUST
		barrel.position = position + Vector3.UP * 0.55
		prop = barrel
	else:
		var crate := CSGBox3D.new()
		crate.size = Vector3.ONE * size
		crate.material = WOOD
		crate.position = position + Vector3.UP * size / 2.0
		crate.rotation.y = _rng.randf_range(-0.4, 0.4)
		prop = crate
		if _rng.randf() < 0.3:  # druga skrzynia na wierzchu
			var top := CSGBox3D.new()
			top.size = Vector3.ONE * size * 0.7
			top.material = WOOD
			top.position = Vector3.UP * size * 0.85
			top.rotation.y = _rng.randf_range(-0.6, 0.6)
			crate.add_child(top)
	prop.name = "Clutter%d" % room.get_node("Geometry").get_child_count()
	room.get_node("Geometry").add_child(prop)


## Rzuty na podłogę (XZ) brył, które już stoją w pokoju (meble, regały), plus szafki.
func _solid_footprints(room: Room) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for node in room.get_node("Geometry").get_children():
		if node is CSGBox3D and node.position.y < 2.5 and not node.name.begins_with("Wall") and node.name != "Floor":
			var half := Vector2(node.size.x, node.size.z) / 2.0
			result.append(Rect2(Vector2(node.position.x, node.position.z) - half, half * 2.0))
		elif node is CSGCylinder3D:
			result.append(Rect2(Vector2(node.position.x, node.position.z) - Vector2.ONE * node.radius, Vector2.ONE * node.radius * 2.0))
	for spot in room.find_children("Locker*", "", true, false):
		result.append(Rect2(Vector2(spot.position.x, spot.position.z) - Vector2(0.6, 0.6), Vector2(1.2, 1.2)))
	return result


func _build_variant(map_seed: int, variant: int, room_count: int) -> void:
	_rng.seed = map_seed * 7919 + variant  # prosta, przenośna formuła (bez zależności od hash())
	_room_count = room_count
	_type_counts.clear()
	_place_start()
	closed_loops = 0
	_links = 0
	loop_stats = {"tries": 0, "pairs": 0, "short_loop": 0, "no_plan": 0, "blocked": 0}
	var attempts := 0
	while rooms.size() - _links < room_count and not _open.is_empty() and attempts < maxi(MAX_ATTEMPTS, room_count * 20):
		attempts += 1
		var index := _rng.randi_range(0, _open.size() - 1)
		var open: Dictionary = _open[index]
		_open.remove_at(index)
		if not _attach_any(open):
			_dead.append(open)  # tu nic się nie zmieściło
		elif closed_loops < (rooms.size() - _links) / ROOMS_PER_LOOP:
			# Pętle domykamy w trakcie budowy: teraz wolnych przejść jest dużo, na końcu
			# zostaje ich kilka i rzadko da się je połączyć.
			_close_loops(1)
	_open.append_array(_dead)
	_dead.clear()
	_connect_loops()
	_close_loops(maxi(1, room_count / ROOMS_PER_LOOP) - closed_loops)
	for open in _open:
		_cap(open)
	_open.clear()


## Dwa wolne przejścia w tym samym miejscu, zwrócone do siebie = przejście między sąsiednimi
## pokojami. Zamiast je zamurować, łączymy: powstaje pętla, więc mniej ślepych zaułków.
func _connect_loops() -> void:
	loops = 0
	var i := 0
	while i < _open.size():
		var a: Transform3D = _open[i].room.transform * _open[i].door.transform
		var matched := -1
		for j in range(i + 1, _open.size()):
			var b: Transform3D = _open[j].room.transform * _open[j].door.transform
			if a.origin.distance_to(b.origin) < 0.05 and a.basis.z.dot(b.basis.z) < -0.99:
				matched = j
				break
		if matched == -1:
			i += 1
			continue
		var other: Dictionary = _open[matched]
		connections.append({"a": _open[i].door, "b": other.door})
		_open[i].room.add_door_frame(_open[i].door)
		other.room.add_door_frame(other.door)
		loops += 1
		_open.remove_at(matched)
		_open.remove_at(i)


# --- Drzwi (15l, 15m) ----------------------------------------------------------------

## Drzwi stoją w części przejść; część z nich na start otwarta, kilka zakluczonych.
const DOOR_CHANCE := 0.65
const DOOR_START_OPEN_CHANCE := 0.3
## Zakluczonych losowo od 0 do tej części wszystkich drzwi (nie zawsze tyle).
const MAX_LOCKED_FRACTION := 0.1

## Plan drzwi: [{"a": Marker3D, "b": Marker3D, "state": Door.State}]. Drzwi stoją w miejscu
## przejścia `a` (oś -Z w stronę `b`). Main stawia według tego węzły Door.
var door_plan: Array[Dictionary] = []
## Pokoje osiągalne z hali bez przechodzenia przez zakluczone drzwi: tam leżą klucze.
var key_rooms: Array[Room] = []


func _plan_doors() -> void:
	door_plan.clear()
	for connection in connections:
		if _rng.randf() < DOOR_CHANCE:
			var state := Door.State.OPEN if _rng.randf() < DOOR_START_OPEN_CHANCE else Door.State.CLOSED
			door_plan.append({"a": connection.a, "b": connection.b, "state": state})
	# Zakluczone: nigdy w hali (start i winda), i tak, żeby zostało gdzie położyć klucze.
	var lockable: Array[Dictionary] = door_plan.filter(func(d: Dictionary) -> bool:
		return _room_of(d.a) != rooms[0] and _room_of(d.b) != rooms[0])
	_shuffle(lockable)
	var locked_count := _rng.randi_range(0, int(door_plan.size() * MAX_LOCKED_FRACTION))
	for door in lockable.slice(0, locked_count):
		door.state = Door.State.LOCKED
	key_rooms = _rooms_reachable_without_locked()
	if key_rooms.size() < 2:  # sama hala: nie ma gdzie położyć kluczy, nic nie zakluczamy
		for door in door_plan:
			if door.state == Door.State.LOCKED:
				door.state = Door.State.CLOSED
		key_rooms = _rooms_reachable_without_locked()
	key_rooms.erase(rooms[0])


func locked_door_count() -> int:
	return door_plan.filter(func(d: Dictionary) -> bool: return d.state == Door.State.LOCKED).size()


func _rooms_reachable_without_locked() -> Array[Room]:
	var locked := {}
	for door in door_plan:
		if door.state == Door.State.LOCKED:
			locked[door.a] = true
	var neighbours := {}
	for room in rooms:
		neighbours[room] = []
	for connection in connections:
		if locked.has(connection.a):
			continue
		neighbours[_room_of(connection.a)].append(_room_of(connection.b))
		neighbours[_room_of(connection.b)].append(_room_of(connection.a))
	var result: Array[Room] = [rooms[0]]
	var i := 0
	while i < result.size():
		for next in neighbours[result[i]]:
			if not result.has(next):
				result.append(next)
		i += 1
	return result


func _room_of(marker: Marker3D) -> Room:
	return marker.get_parent().get_parent() as Room


# --- Domykanie pętli łącznikami (16h) ----------------------------------------------

## Gołe korytarze z siatki (długość ze ścianami -> scena) i narożnik 4x4 (tools/gen_rooms.py).
const LINKS := {
	4: "res://rooms/link4.tscn", 6: "res://rooms/link6.tscn", 8: "res://rooms/link8.tscn",
	10: "res://rooms/link10.tscn", 12: "res://rooms/link12.tscn", 14: "res://rooms/link14.tscn",
	16: "res://rooms/link16.tscn",
}
const BEND := "res://rooms/bend.tscn"
const BEND_HALF := 2.0
## Ile pętli chcemy: jedna na tyle pokoi (co najmniej jedna, jeśli się da).
const ROOMS_PER_LOOP := 10
## Pętla ma obejmować kilka pokoi: krótsza (np. wokół jednego pokoju) nic nie daje w ucieczce.
const MIN_LOOP_HOPS := 3
const MAX_LOOP_REACH := 60.0
const MAX_SEGMENT := 32  # najdłuższy prosty odcinek łącznika (dwa najdłuższe korytarze)

## Pętle domknięte łącznikami w ostatniej mapie (osobno od `loops`, czyli przejść stykających się czołami).
var closed_loops := 0
## Diagnostyka domykania (do testów): ile par odpadło na którym etapie.
var loop_stats := {}
var _links := 0  # ile łączników stoi na mapie (nie liczą się do liczby pokoi)


## Szuka par wolnych przejść, które da się połączyć łącznikiem (proste korytarze i do dwóch
## narożników), i stawia do `count` takich łączników. Dzięki siatce 2 m odległości między
## przejściami są parzyste, więc łączniki z siatki pasują. Najpierw najdłuższe pętle (najwięcej
## pokoi po drodze w drzewie), a z nich te z najmniejszą liczbą kawałków.
func _close_loops(count: int) -> void:
	if count <= 0:
		return
	loop_stats.tries += 1
	var hops := _room_hops()
	var candidates: Array = []
	# Także przejścia, do których nie zmieścił się żaden pokój: wąski łącznik może się zmieścić.
	var free := _open + _dead
	for i in free.size():
		for j in range(i + 1, free.size()):
			var a: Dictionary = free[i]
			var b: Dictionary = free[j]
			if a.room == b.room:
				continue
			loop_stats.pairs += 1
			var distance: int = hops.get(a.room, {}).get(b.room, 0)
			if distance < MIN_LOOP_HOPS:
				loop_stats.short_loop += 1
				continue
			var plan := _plan_link(a, b)
			if plan.is_empty():
				loop_stats.no_plan += 1
				continue
			candidates.append({"a": a, "b": b, "hops": distance, "plan": plan, "order": candidates.size()})
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.hops != y.hops:
			return x.hops > y.hops
		if x.plan.size() != y.plan.size():
			return x.plan.size() < y.plan.size()
		return x.order < y.order)
	var built := 0
	for candidate in candidates:
		if built >= count:
			break
		if not (_is_free(candidate.a) and _is_free(candidate.b)):
			continue  # przejście zajęte przez wcześniejszą pętlę
		if _build_link(candidate.a, candidate.b, candidate.plan):
			built += 1
			closed_loops += 1
		else:
			loop_stats.blocked += 1


## Liczba przejść między pokojami w drzewie (BFS z każdego pokoju).
func _room_hops() -> Dictionary:
	var neighbours := {}
	for room in rooms:
		neighbours[room] = []
	for connection in connections:
		var ra: Node = connection.a.get_parent().get_parent()
		var rb: Node = connection.b.get_parent().get_parent()
		neighbours[ra].append(rb)
		neighbours[rb].append(ra)
	var result := {}
	for start in rooms:
		var distance := {start: 0}
		var queue: Array = [start]
		while not queue.is_empty():
			var current = queue.pop_front()
			for next in neighbours[current]:
				if not distance.has(next):
					distance[next] = distance[current] + 1
					queue.append(next)
		result[start] = distance
	return result


## Plan łącznika z `a` do `b`: lista [ścieżka sceny, przejście wejściowe, kierunek wyjścia].
## Szuka kształtu: prosto, prosto-narożnik-prosto albo z dwoma narożnikami (Z / U), z odcinkami
## z siatki. Pusta, jeśli się nie da. Sama geometria; kolizje sprawdza _build_link.
func _plan_link(a: Dictionary, b: Dictionary) -> Array:
	var ta: Transform3D = a.room.transform * a.door.transform
	var tb: Transform3D = b.room.transform * b.door.transform
	if absf(tb.origin.y - ta.origin.y) > 0.05:
		loop_stats.other_floor = loop_stats.get("other_floor", 0) + 1
		return []
	if ta.origin.distance_to(tb.origin) > MAX_LOOP_REACH:
		loop_stats.far = loop_stats.get("far", 0) + 1
		return []
	var start := Vector2(ta.origin.x, ta.origin.z)
	var goal := Vector2(tb.origin.x, tb.origin.z)
	var dir := Vector2(-ta.basis.z.x, -ta.basis.z.z).round()  # na zewnątrz A = w głąb łącznika
	var arrive := Vector2(tb.basis.z.x, tb.basis.z.z).round()  # tak wchodzimy do B
	# Prosto.
	var direct := _segment_to(start, dir, goal, arrive)
	if direct >= 0:
		return _straight(direct)
	# Jeden albo dwa narożniki; pierwszy odcinek przed narożnikiem z siatki.
	for first: int in SEGMENTS:
		for turn1: int in [-1, 1]:
			var p1: Vector2 = start + dir * (first + BEND_HALF)
			var d1: Vector2 = Vector2(-dir.y, dir.x) * turn1
			p1 += d1 * BEND_HALF
			var rest := _segment_to(p1, d1, goal, arrive)
			if rest >= 0:
				return _straight(first) + [[BEND, "", d1]] + _straight(rest)
			for middle: int in SEGMENTS:
				for turn2: int in [-1, 1]:
					var d2: Vector2 = Vector2(-d1.y, d1.x) * turn2
					var p2: Vector2 = p1 + d1 * (middle + BEND_HALF) + d2 * BEND_HALF
					var last := _segment_to(p2, d2, goal, arrive)
					if last >= 0:
						return _straight(first) + [[BEND, "", d1]] + _straight(middle) + [[BEND, "", d2]] + _straight(last)
	return []


## Odcinki z siatki: 0 (bez korytarza) i długości, które da się złożyć z łączników.
const SEGMENTS := [0, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]


## Długość prostego odcinka z `from` w kierunku `dir`, który kończy się dokładnie w `goal`
## i wchodzi tam w kierunku `arrive`. -1, jeśli się nie da.
func _segment_to(from: Vector2, dir: Vector2, goal: Vector2, arrive: Vector2) -> int:
	if dir.dot(arrive) < 0.99:
		return -1
	var delta := goal - from
	var along := delta.dot(dir)
	if (delta - dir * along).length() > 0.05:
		return -1
	var n := roundi(along)
	if absf(along - n) > 0.05 or n < 0 or (n > 0 and _straight(n).is_empty()):
		return -1
	return n


## Prosty odcinek długości `length` z jednego albo dwóch korytarzy z siatki ([] dla 0).
func _straight(length: int) -> Array:
	if length == 0:
		return []
	if length < 4 or length > MAX_SEGMENT:
		return []
	if LINKS.has(length):
		return [[LINKS[length], "West", null]]
	var first := mini(16, length - 4)
	if LINKS.has(first) and LINKS.has(length - first):
		return [[LINKS[first], "West", null], [LINKS[length - first], "West", null]]
	return []


## Stawia łącznik według planu. Najpierw sprawdza wszystkie kawałki (kolizje, trafienie w B),
## dopiero potem cokolwiek dodaje do mapy.
func _build_link(a: Dictionary, b: Dictionary, plan: Array) -> bool:
	var pieces: Array = []  # [{"room": Room, "door": Marker3D (dołączające), "exit": Marker3D}]
	var current := a
	var planned_bounds: Array[AABB] = []
	var target_b: Transform3D = b.room.transform * b.door.transform
	var ok := true
	for step in plan:
		var piece := _instantiate(step[0])
		var choice := _orient_piece(piece, step, current)
		if choice.is_empty():
			piece.free()
			ok = false
			break
		piece.transform = _aligned_transform(choice.door, current)
		var bounds := (piece.transform * piece.bounds).grow(-OVERLAP_TOLERANCE)
		if rooms.any(func(r: Room) -> bool: return bounds.intersects(r.transform * r.bounds)) \
				or planned_bounds.any(func(other: AABB) -> bool: return bounds.intersects(other)):
			piece.free()
			ok = false
			break
		planned_bounds.append(piece.transform * piece.bounds)
		pieces.append({"room": piece, "door": choice.door, "exit": choice.exit})
		current = {"room": piece, "door": choice.exit}
	if ok:
		var end: Transform3D = current.room.transform * current.door.transform
		ok = end.origin.distance_to(target_b.origin) < 0.05 and end.basis.z.dot(target_b.basis.z) < -0.99
	if not ok:
		for piece in pieces:
			piece.room.free()
		return false
	var previous := a
	for piece in pieces:
		_place(piece.room, piece.door, previous)
		_links += 1
		_take(previous)
		previous = {"room": piece.room, "door": piece.exit}
	_take(previous)
	_take(b)
	connections.append({"a": previous.door, "b": b.door})
	previous.room.add_door_frame(previous.door)
	b.room.add_door_frame(b.door)
	return true


func _is_free(open: Dictionary) -> bool:
	return _open.has(open) or _dead.has(open)


func _take(open: Dictionary) -> void:
	_open.erase(open)
	_dead.erase(open)


## Którym przejściem kawałek dołącza i którym wychodzi. Korytarz: West/East. Narożnik: ta
## z dwóch orientacji, której wyjście skręca w zaplanowanym kierunku.
func _orient_piece(piece: Room, step: Array, current: Dictionary) -> Dictionary:
	var doors := piece.get_doorways()
	for door in doors:
		if step[1] != "" and door.name != step[1]:
			continue
		var exit: Marker3D = doors[1] if door == doors[0] else doors[0]
		if step[2] != null:
			var placed := _aligned_transform(door, current) * exit.transform
			var out := Vector2(-placed.basis.z.x, -placed.basis.z.z)
			if out.dot(step[2]) < 0.99:
				continue
		return {"door": door, "exit": exit}
	return {}


func _clear() -> void:
	for room in rooms:
		room.free()
	rooms.clear()
	connections.clear()
	_open.clear()
	_dead.clear()


## Stała mapa (do testów): łańcuch [[ścieżka, przejście poprzedniego, przejście nowego], ...].
func build_chain(parent: Node3D, chain: Array) -> Array[Room]:
	_parent = parent
	_place_start()
	for link in chain:
		var previous := rooms[-1]
		var open := _take_open(previous, link[1])
		var room := _instantiate(link[0])
		_place(room, room.get_node("Doorways/" + link[2]), open)
	for open in _open:
		_cap(open)
	_open.clear()
	return rooms


func _place_start() -> void:
	var start := _instantiate(START_ROOM)
	_parent.add_child(start)
	rooms.append(start)
	for door in start.get_doorways():
		_open.append({"room": start, "door": door})


func _attach_any(open: Dictionary) -> bool:
	# Gdy to ostatnie wolne przejście, ślepy zaułek zakończyłby mapę przed czasem.
	var allow_dead_end := not _open.is_empty()
	for path in _shuffled_types():
		if not allow_dead_end and _door_count(path) < 2:
			continue
		var room := _instantiate(path)
		var doors := room.get_doorways()
		_shuffle(doors)
		for door in doors:
			if _fits(room, door, open):
				_place(room, door, open)
				return true
		room.free()
	return false


func _fits(room: Room, door: Marker3D, open: Dictionary) -> bool:
	var bounds := (_aligned_transform(door, open) * room.bounds).grow(-OVERLAP_TOLERANCE)
	for other in rooms:
		if bounds.intersects(other.transform * other.bounds):
			return false
	return true


func _place(room: Room, door: Marker3D, open: Dictionary) -> void:
	room.transform = _aligned_transform(door, open)
	connections.append({"a": open.door, "b": door})
	open.room.add_door_frame(open.door)
	room.add_door_frame(door)
	room.name = "%02d_%s" % [rooms.size(), room.name]  # te same nazwy u każdego peera
	_type_counts[room.scene_file_path] = _type_counts.get(room.scene_file_path, 0) + 1
	_parent.add_child(room)
	rooms.append(room)
	for other_door in room.get_doorways():
		if other_door != door:
			_open.append({"room": room, "door": other_door})


## Transformacja nowego pokoju, przy której jego przejście `door` stoi w miejscu
## wolnego przejścia `open`, obrócone o 180° (przejścia patrzą na siebie).
func _aligned_transform(door: Marker3D, open: Dictionary) -> Transform3D:
	var target: Transform3D = open.room.transform * open.door.transform
	target.basis = Basis(Vector3.UP, PI) * target.basis
	var result := target * door.transform.affine_inverse()
	# Obroty są wielokrotnościami 90°: zaokrąglamy, żeby błędy float nie rosły z każdym pokojem.
	for axis in 3:
		result.basis[axis] = result.basis[axis].round()
	result.origin = result.origin.snapped(Vector3.ONE * 0.001)
	return result


func _cap(open: Dictionary) -> void:
	open.room.cap_doorway(open.door)


func _take_open(room: Room, door_name: String) -> Dictionary:
	for i in _open.size():
		if _open[i].room == room and _open[i].door.name == door_name:
			var open: Dictionary = _open[i]
			_open.remove_at(i)
			return open
	push_error("Brak wolnego przejścia %s w %s" % [door_name, room.name])
	return {}


func _door_count(path: String) -> int:
	if not _door_counts.has(path):
		var probe := _instantiate(path)
		_door_counts[path] = probe.get_doorways().size()
		probe.free()
	return _door_counts[path]


func _instantiate(path: String) -> Room:
	return (load(path) as PackedScene).instantiate() as Room


## Ile pokoi danego typu może stać na mapie (-1: bez limitu).
func type_limit(path: String, room_count: int) -> int:
	return maxi(1, room_count / ROOM_LIMITS[path]) if ROOM_LIMITS.has(path) else -1


## Typy pokoi w losowej kolejności, ważonej wagami (losowanie bez zwracania). Typy, które
## wyczerpały limit, odpadają; powtórki typów z limitem mają mniejszą wagę.
func _shuffled_types() -> Array[String]:
	var pool := {}
	for path in ROOM_TYPES:
		var placed: int = _type_counts.get(path, 0)
		var limit := type_limit(path, _room_count)
		if limit >= 0 and placed >= limit:
			continue
		pool[path] = ROOM_TYPES[path] * (pow(REPEAT_WEIGHT_FACTOR, placed) if limit >= 0 else 1.0)
	var result: Array[String] = []
	while not pool.is_empty():
		var total := 0.0
		for weight in pool.values():
			total += weight
		var roll := _rng.randf() * total
		for path in pool.keys():
			roll -= pool[path]
			if roll <= 0.0:
				result.append(path)
				pool.erase(path)
				break
	return result


## Fisher-Yates na naszym RNG (Array.shuffle() używa globalnego RNG, więc nie jest deterministyczne).
func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
