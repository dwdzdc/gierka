class_name Room
extends Node3D
## Moduł mapy (prefab pokoju). Kontrakt: dzieci o stałych nazwach.
##   Geometry      – CSGCombiner3D albo meshe z kolizją (warstwa "world")
##   Doorways      – Marker3D w miejscach przejść do innych pokoi
##   CameraZones   – CameraZone (Area3D) z dzieckiem Camera (FixedCamera)
##   LootSpawns    – Marker3D, gdzie mogą pojawić się znaleziska
##   AmbientPoints – Marker3D na zdarzenia otoczenia (fałszywe alarmy)
## Generator mapy będzie składał pokoje po Doorways. Kamery jadą razem z pokojem.


func get_doorways() -> Array[Marker3D]:
	return _markers(&"Doorways")


func get_loot_spawns() -> Array[Marker3D]:
	return _markers(&"LootSpawns")


func get_ambient_points() -> Array[Marker3D]:
	return _markers(&"AmbientPoints")


func _markers(group_node: StringName) -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	var holder := get_node_or_null(NodePath(group_node))
	if holder:
		result.assign(holder.get_children())
	return result
