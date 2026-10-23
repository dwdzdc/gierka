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
## Generator mapy składa pokoje po Doorways. Kamery i strefy jadą razem z pokojem.

const DOOR_SIZE := Vector2(2.0, 2.6)
const WALL_THICKNESS := 0.2
const CAP_MATERIAL := preload("res://rooms/materials/wall.tres")

## Bryła pokoju razem ze ścianami (lokalnie). Generator nie pozwala, żeby bryły się przecinały.
@export var bounds := AABB()


func get_doorways() -> Array[Marker3D]:
	return _markers(&"Doorways")


func get_loot_spawns() -> Array[Marker3D]:
	return _markers(&"LootSpawns")


func get_ambient_points() -> Array[Marker3D]:
	return _markers(&"AmbientPoints")


func get_player_spawns() -> Array[Marker3D]:
	return _markers(&"PlayerSpawns")


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


func _markers(group_node: StringName) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	var holder := get_node_or_null(NodePath(group_node))
	if holder:
		result.assign(holder.get_children())
	return result
