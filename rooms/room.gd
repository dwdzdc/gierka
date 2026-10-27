class_name Room
extends Node3D
## Moduł mapy (prefab pokoju). Kontrakt: dzieci o stałych nazwach.
##   Geometry      – CSGCombiner3D z kolizją (warstwa "world")
##   Doorways      – Marker3D przejść: na zewnętrznej powierzchni ściany, na poziomie
##                   podłogi przejścia, oś -Z na zewnątrz. Każde przejście ma DOOR_SIZE.
##   CameraZones   – CameraZone (Area3D) z dzieckiem Camera (FixedCamera)
##   LootSpawns    – Marker3D, gdzie mogą pojawić się znaleziska
##   AmbientPoints – Marker3D na zdarzenia otoczenia (fałszywe alarmy)
##   PlayerSpawns  – (opcjonalnie) Marker3D startu graczy; ma je pokój startowy
##   ExitPoint/Exit – (opcjonalnie) wyjście z mapy (ekstrakcja); dokłada je generator razem z windą
##   Vents         – Marker3D tuż pod kratkami wentylacji w suficie (potwory z wentylacją)
## Generator mapy składa pokoje po Doorways. Kamery i strefy jadą razem z pokojem.

const DOOR_SIZE := Vector2(2.0, 2.6)
const WALL_THICKNESS := 0.2
const CAP_MATERIAL := preload("res://rooms/materials/wall.tres")
const FRAME_MATERIAL := preload("res://rooms/materials/door_frame.tres")
const LAMP_MATERIAL := preload("res://rooms/materials/door_lamp.tres")
const LAMP_OFF_MATERIAL := preload("res://rooms/materials/lamp_off.tres")
const EXIT_MATERIAL := preload("res://rooms/materials/exit.tres")
const ELEVATOR_MATERIAL := preload("res://rooms/materials/metal.tres")
const SKYLIGHT_MATERIAL := preload("res://rooms/materials/skylight.tres")

## Bryła pokoju razem ze ścianami (lokalnie). Generator nie pozwala, żeby bryły się przecinały.
@export var bounds := AABB()
## Zgaszony pokój (losuje generator). Potwory widzą w nim gracza bez latarki tylko z bliska.
var dark := false


func get_doorways() -> Array[Marker3D]:
	return _markers(&"Doorways")


func get_loot_spawns() -> Array[Marker3D]:
	return _markers(&"LootSpawns")


func get_ambient_points() -> Array[Marker3D]:
	return _markers(&"AmbientPoints")


func get_player_spawns() -> Array[Marker3D]:
	return _markers(&"PlayerSpawns")


func get_vents() -> Array[Marker3D]:
	return _markers(&"Vents")


func get_exit() -> Marker3D:
	return get_node_or_null(^"ExitPoint/Exit") as Marker3D


## Zamurowuje przejście, które nigdzie nie prowadzi (dokłada ściankę w otworze).
func cap_doorway(doorway: Marker3D) -> void:
	var cap := CSGBox3D.new()
	cap.name = "Cap_" + doorway.name
	cap.size = Vector3(DOOR_SIZE.x + 0.02, DOOR_SIZE.y + 0.02, WALL_THICKNESS)
	cap.material = CAP_MATERIAL
	# Środek otworu: pół grubości ściany do środka (+Z markera) i pół wysokości drzwi w górę.
	var local := doorway.transform
	cap.transform = Transform3D(local.basis, local.origin + local.basis.z * WALL_THICKNESS / 2.0 + Vector3.UP * DOOR_SIZE.y / 2.0)
	$Geometry.add_child(cap)


## Winda w przejściu (34b): otwór zamurowany jak ślepy zaułek, od środka stalowe drzwi windy
## w zielonej futrynie ze znakiem. Zwraca znacznik wyjścia 0,8 m przed drzwiami (oś -Z na windę).
func add_elevator(doorway: Marker3D) -> Marker3D:
	cap_doorway(doorway)
	var look := Node3D.new()
	look.name = "Elevator_" + doorway.name
	look.transform = doorway.transform
	add_child(look)
	var face := WALL_THICKNESS + 0.05  # tuż przed wewnętrzną powierzchnią ściany (+Z markera)
	_frame_box(look, Vector3(0, DOOR_SIZE.y / 2.0, face), Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.1), ELEVATOR_MATERIAL)
	_frame_box(look, Vector3(0, DOOR_SIZE.y / 2.0, face + 0.06), Vector3(0.03, DOOR_SIZE.y, 0.02), EXIT_MATERIAL)  # szpara między skrzydłami
	for side in [-1.0, 1.0]:
		_frame_box(look, Vector3(side * (DOOR_SIZE.x / 2.0 + 0.1), 1.45, face + 0.03), Vector3(0.15, 2.9, 0.15), EXIT_MATERIAL)
	_frame_box(look, Vector3(0, 2.85, face + 0.03), Vector3(DOOR_SIZE.x + 0.35, 0.15, 0.15), EXIT_MATERIAL)
	_frame_box(look, Vector3(0, 3.15, face + 0.01), Vector3(1.0, 0.3, 0.1), EXIT_MATERIAL).name = "Sign"
	var holder := Node3D.new()
	holder.name = "ExitPoint"
	add_child(holder)
	var marker := Marker3D.new()
	marker.name = "Exit"
	marker.transform = Transform3D(doorway.transform.basis, doorway.position + doorway.transform.basis.z * (WALL_THICKNESS + 0.8))
	holder.add_child(marker)
	return marker


## Futryna w kontrastowym kolorze i lampka nad przejściem, od strony tego pokoju.
## Same meshe (bez kolizji): to tylko znak "tu są drzwi", widoczny z każdego ujęcia.
func add_door_frame(doorway: Marker3D) -> void:
	var frame := Node3D.new()
	frame.name = "Frame_" + doorway.name
	frame.transform = doorway.transform
	add_child(frame)
	var depth := WALL_THICKNESS + 0.05  # tuż przed wewnętrzną powierzchnią ściany (+Z markera)
	var post := 0.2
	var jamb_height := DOOR_SIZE.y + post
	for side in [-1.0, 1.0]:
		_frame_box(frame, Vector3(side * (DOOR_SIZE.x / 2.0 + post / 2.0), jamb_height / 2.0, depth), Vector3(post, jamb_height, 0.1), FRAME_MATERIAL)
	_frame_box(frame, Vector3(0, DOOR_SIZE.y + post / 2.0, depth), Vector3(DOOR_SIZE.x + 2.0 * post, post, 0.1), FRAME_MATERIAL)
	_frame_box(frame, Vector3(0, DOOR_SIZE.y + post + 0.15, depth + 0.03), Vector3(0.5, 0.12, 0.16), LAMP_MATERIAL).name = "Lamp"


## Zgaszony pokój: oprawy lamp, lampki nad drzwiami po tej stronie i świetlik zostają na
## miejscu, ale nie świecą. Słaba poświata futryn zostaje, żeby drzwi dało się znaleźć.
func switch_off_lamps() -> void:
	for lamp in find_children("Fixture*", "MeshInstance3D", true, false) + find_children("Lamp", "MeshInstance3D", true, false):
		lamp.material_override = LAMP_OFF_MATERIAL
	for solid in $Geometry.get_children():
		if solid is CSGPrimitive3D and solid.material == SKYLIGHT_MATERIAL:
			solid.material = LAMP_OFF_MATERIAL


func _frame_box(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _markers(group_node: StringName) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	var holder := get_node_or_null(NodePath(group_node))
	if holder:
		result.assign(holder.get_children())
	return result
