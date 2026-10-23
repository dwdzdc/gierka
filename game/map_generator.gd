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
const ROOM_TYPES := {
	"res://rooms/corridor.tscn": 3.0,
	"res://rooms/turn.tscn": 2.0,
	"res://rooms/junction.tscn": 2.5,
	"res://rooms/storage.tscn": 1.0,
	"res://rooms/closet.tscn": 0.6,  # ślepy zaułek: rzadziej, żeby łatwiej było uciec potworowi
	"res://rooms/ramp.tscn": 1.0,
	"res://rooms/stairwell.tscn": 1.0,
}
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


const MAX_RETRIES := 6


## Składa losową mapę z `room_count` pokoi pod `parent`. Jeśli pokoje się "zablokują"
## (zostanie mniej niż `room_count`), próbuje kolejnych wariantów seeda i wybiera najlepszy.
## Też deterministycznie: ten sam seed zawsze prowadzi do tego samego wariantu.
func generate(parent: Node3D, map_seed: int, room_count: int) -> Array[Room]:
	_parent = parent
	var best_variant := 0
	var best_size := -1
	for variant in MAX_RETRIES:
		_build_variant(map_seed, variant, room_count)
		if rooms.size() > best_size:
			best_size = rooms.size()
			best_variant = variant
		if rooms.size() >= room_count:
			_decorate()
			return rooms
		_clear()
	_build_variant(map_seed, best_variant, room_count)
	_decorate()
	return rooms


# --- Zmienność z seeda (krok 15/15h) ---------------------------------------------

const LIGHT_OFF_CHANCE := 0.1
const LIGHT_FLICKER_CHANCE := 0.2
const FLICKER_SCRIPT := preload("res://fx/flicker_light.gd")
const WOOD := preload("res://rooms/materials/wood.tres")
const RUST := preload("res://rooms/materials/rust.tres")
const CLUTTER_PER_ROOM := Vector2i(2, 5)
const CLUTTER_KEEP_CLEAR := 2.8  # tyle metrów przed drzwiami, wyjściem i kryjówkami zostaje pusto


## Ten sam typ pokoju za każdym razem trochę inny: zgaszone/migoczące lampy i drobne
## rekwizyty przy ścianach. Wszystko z RNG mapy, więc u każdego peera identycznie.
func _decorate() -> void:
	for room in rooms:
		for light in room.find_children("*", "OmniLight3D", true, false):
			var roll := _rng.randf()
			if roll < LIGHT_OFF_CHANCE:
				light.visible = false
			elif roll < LIGHT_OFF_CHANCE + LIGHT_FLICKER_CHANCE and light.get_script() == null:
				light.set_script(FLICKER_SCRIPT)
		if room.bounds.size.y < 8.0:  # bez ramp i schodów (pochyłe podłogi)
			_add_clutter(room)


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
	_place_start()
	var attempts := 0
	while rooms.size() < room_count and not _open.is_empty() and attempts < maxi(MAX_ATTEMPTS, room_count * 20):
		attempts += 1
		var index := _rng.randi_range(0, _open.size() - 1)
		var open: Dictionary = _open[index]
		_open.remove_at(index)
		if not _attach_any(open):
			_dead.append(open)  # tu nic się nie zmieściło
	_open.append_array(_dead)
	_dead.clear()
	_connect_loops()
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


## Typy pokoi w losowej kolejności, ważonej wagami (losowanie bez zwracania).
func _shuffled_types() -> Array[String]:
	var pool := ROOM_TYPES.duplicate()
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
