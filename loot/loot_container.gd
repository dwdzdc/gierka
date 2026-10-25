class_name LootContainer
extends Area3D
## Pojemnik do przeszukania (33b): niska skrzynia z wiekiem, celowo inna niż szafka do chowania
## (E przy szafce = schowaj się, E przy skrzyni = przeszukaj). Spawnuje go host przez
## MultiplayerSpawner; zawartość zna tylko host, a klienci widzą tylko, czy jest otwarta.
## Bez kolizji: stawiany po wypieczeniu NavMesh, więc nie może blokować przejść potworom.

enum Content { EMPTY, COINS, BATTERY }

const SIZE := Vector3(0.8, 0.5, 0.55)
const USE_DISTANCE := 1.3
const WOOD := preload("res://rooms/materials/wood.tres")
const METAL := preload("res://rooms/materials/metal.tres")

## Synchronizowane (spawn + zmiana): otwarta skrzynia ma podniesione wieko.
@export var opened := false:
	set(value):
		opened = value
		if _lid:
			_lid.rotation.x = -1.9 if opened else 0.0
## Tylko u hosta.
var content := Content.EMPTY
var value := 0
var _lid: Node3D


func _ready() -> void:
	add_to_group(&"loot_containers")
	_build_visual()
	opened = opened


func can_search_from(position: Vector3) -> bool:
	var delta := position - global_position
	delta.y = 0.0
	return not opened and delta.length() <= USE_DISTANCE


func _build_visual() -> void:
	var body := _box(Vector3(SIZE.x, SIZE.y - 0.06, SIZE.z), WOOD)
	body.position.y = (SIZE.y - 0.06) / 2.0
	add_child(body)
	for x in [-SIZE.x / 2.0 + 0.08, SIZE.x / 2.0 - 0.08]:  # metalowe okucia
		var band := _box(Vector3(0.05, SIZE.y - 0.04, SIZE.z + 0.02), METAL)
		band.position = Vector3(x, (SIZE.y - 0.04) / 2.0, 0)
		add_child(band)
	# Wieko na zawiasie z tyłu (+Z), otwiera się do tyłu.
	_lid = Node3D.new()
	_lid.position = Vector3(0, SIZE.y - 0.06, SIZE.z / 2.0)
	add_child(_lid)
	var lid := _box(Vector3(SIZE.x + 0.02, 0.06, SIZE.z + 0.02), WOOD)
	lid.position = Vector3(0, 0.03, -SIZE.z / 2.0)
	_lid.add_child(lid)


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance
