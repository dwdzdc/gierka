extends SceneTree
# Zasady kamer (15f), dla każdego typu pokoju osobno:
#  - każde przejście widać z kamery strefy, w której to przejście leży (w kadrze, bez zasłony),
#  - i ta kamera nie patrzy na nie prawie równolegle do ściany (kąt do normalnej < 70°).

## Wszystkie typy pokoi z rooms/ (nowy pokój nie wymaga dopisywania go tutaj).
var ROOMS: Array[String] = _room_names()
const MAX_ANGLE := 70.0

var holder := Node3D.new()
var frames := 0
var problems := 0

func _initialize() -> void:
	root.add_child.call_deferred(holder)
	for i in ROOMS.size():
		var room: Node3D = load("res://rooms/%s.tscn" % ROOMS[i]).instantiate()
		room.position = Vector3(i * 100, 0, 0)
		holder.add_child(room)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	var space := holder.get_world_3d().direct_space_state
	for room in holder.get_children():
		# Geometria nie może wystawać poza bryłę pokoju (generator sprawdza kolizje tylko brył).
		var meshes: Array = room.get_node("Geometry").get_meshes()
		if meshes.size() > 1:
			var geometry: AABB = meshes[1].get_aabb()
			if not room.bounds.grow(0.05).encloses(geometry):
				problems += 1
				print("ZLE %s: geometria %s wystaje poza bryłę %s" % [room.name, geometry, room.bounds])
		var cameras: Array = room.find_children("Camera", "Camera3D", true, false)
		for door in room.get_doorways():
			var inward: Vector3 = door.global_transform.basis.z
			# Środek otworu tuż za ścianą od strony pokoju, na wysokości klatki piersiowej.
			var point: Vector3 = door.global_position + inward * 0.6 + Vector3.UP * 1.3
			var seen_by := []
			var notes := []
			for cam in cameras:
				var zone_name: String = cam.get_parent().name
				if not _zone_contains(cam.get_parent(), point):
					continue
				if not cam.is_position_in_frustum(point):
					notes.append("%s: poza kadrem" % zone_name)
					continue
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position, point, 1))
				if not hit.is_empty():
					notes.append("%s: zasłonięte" % zone_name)
					continue
				var angle := rad_to_deg(inward.angle_to((cam.global_position - point).normalized()))
				if angle > MAX_ANGLE:
					notes.append("%s: kąt %d°" % [zone_name, angle])
					continue
				seen_by.append("%s (%d°)" % [zone_name, angle])
			if seen_by.is_empty():
				problems += 1
				print("ZLE %s.%s: %s" % [room.name, door.name, notes])
			else:
				print("OK  %s.%s: %s" % [room.name, door.name, seen_by])
	print("PROBLEMY: %d" % problems)
	return true


func _zone_contains(zone: Node3D, point: Vector3) -> bool:
	var shape_node: CollisionShape3D = zone.get_node("Shape")
	var box := shape_node.shape as BoxShape3D
	var local := shape_node.global_transform.affine_inverse() * point
	return AABB(-box.size / 2.0, box.size).has_point(local)


func _unused() -> bool:
	return true


static func _room_names() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at("res://rooms"):
		if file.ends_with(".tscn"):
			names.append(file.get_basename())
	names.sort()
	return names
