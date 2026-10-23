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
	"res://rooms/junction.tscn": 2.0,
	"res://rooms/storage.tscn": 1.0,
	"res://rooms/closet.tscn": 1.0,
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
			return rooms
		_clear()
	_build_variant(map_seed, best_variant, room_count)
	return rooms


func _build_variant(map_seed: int, variant: int, room_count: int) -> void:
	_rng.seed = map_seed * 7919 + variant  # prosta, przenośna formuła (bez zależności od hash())
	_place_start()
	var attempts := 0
	while rooms.size() < room_count and not _open.is_empty() and attempts < MAX_ATTEMPTS:
		attempts += 1
		var index := _rng.randi_range(0, _open.size() - 1)
		var open: Dictionary = _open[index]
		_open.remove_at(index)
		if not _attach_any(open):
			_cap(open)  # tu nic się nie zmieściło
	for open in _open:
		_cap(open)
	_open.clear()


func _clear() -> void:
	for room in rooms:
		room.free()
	rooms.clear()
	connections.clear()
	_open.clear()


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
