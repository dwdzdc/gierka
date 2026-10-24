extends SceneTree
## Mapy pokrycia kamer (krok 10c): dla każdego typu pokoju rysuje widok z góry do
## docs/coverage/<pokój>.png. Kolory:
##   zielony – postać w tym miejscu widać z kamery strefy, w której stoi
##   żółty   – widać tylko z innej kamery pokoju (zadziała bezpiecznik, ale ujęcie skacze)
##   czerwony – nie widać z żadnej kamery (martwe pole)
##   szary   – zajęte (meble, ściany)
## Uruchom: godot --headless --path . -s tools/coverage_map.gd

## Wszystkie typy pokoi z rooms/ (nowy pokój nie wymaga dopisywania go tutaj).
var ROOMS: Array[String] = _room_names()
const STEP := 0.5  # m
const PIXELS_PER_STEP := 10
const HEIGHTS := [1.5, 0.7]  # głowa, biodra (jak CameraDirector)

var holder := Node3D.new()
var frames := 0


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
	for i in ROOMS.size():
		_draw(holder.get_child(i), ROOMS[i])
	return true


func _draw(room: Node3D, room_name: String) -> void:
	var space := holder.get_world_3d().direct_space_state
	var bounds: AABB = room.bounds
	var cols := int(bounds.size.x / STEP)
	var rows := int(bounds.size.z / STEP)
	var image := Image.create(cols * PIXELS_PER_STEP, rows * PIXELS_PER_STEP, false, Image.FORMAT_RGB8)
	var counts := {"zielony": 0, "żółty": 0, "czerwony": 0}
	var cameras: Array = room.find_children("Camera", "Camera3D", true, false)
	for c in cols:
		for r in rows:
			var local := Vector3(bounds.position.x + (c + 0.5) * STEP, 0, bounds.position.z + (r + 0.5) * STEP)
			var color := _classify(room, room.to_global(local), cameras, space)
			image.fill_rect(Rect2i(c * PIXELS_PER_STEP, r * PIXELS_PER_STEP, PIXELS_PER_STEP, PIXELS_PER_STEP), color)
			if color == Color.GREEN: counts["zielony"] += 1
			elif color == Color.YELLOW: counts["żółty"] += 1
			elif color == Color.RED: counts["czerwony"] += 1
	image.save_png("res://docs/coverage/%s.png" % room_name)
	var total: int = counts["zielony"] + counts["żółty"] + counts["czerwony"]
	print("%-10s zielony %3d%%  żółty %3d%%  czerwony %3d%%" % [room_name, counts["zielony"] * 100 / maxi(total, 1), counts["żółty"] * 100 / maxi(total, 1), counts["czerwony"] * 100 / maxi(total, 1)])


## Kolor dla jednego punktu podłogi (na najniższym piętrze pokoju albo na rampie pod nim).
func _classify(room: Node3D, point: Vector3, cameras: Array, space: PhysicsDirectSpaceState3D) -> Color:
	# Podłoga: raycast z góry, pierwsze trafienie poniżej sufitu.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * (room.bounds.end.y - 0.5), point + Vector3.DOWN, 1))
	if hit.is_empty():
		return Color.DIM_GRAY
	var floor: Vector3 = hit.position
	# Miejsce na postać (kapsuła 0.35 x 1.7).
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	query.shape = capsule
	query.transform = Transform3D(Basis(), floor + Vector3.UP * 0.9)
	query.collision_mask = 1
	if not space.intersect_shape(query, 1).is_empty():
		return Color.DIM_GRAY
	var own := false
	var any := false
	for camera in cameras:
		if _sees(camera, floor, space):
			any = true
			if _zone_contains(camera.get_parent(), floor + Vector3.UP):
				own = true
	return Color.GREEN if own else (Color.YELLOW if any else Color.RED)


func _sees(camera: Camera3D, floor: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for h in HEIGHTS:
		var p: Vector3 = floor + Vector3.UP * h
		if camera.is_position_in_frustum(p) and space.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position, p, 1)).is_empty():
			return true
	return false


func _zone_contains(zone: Node3D, point: Vector3) -> bool:
	var shape_node: CollisionShape3D = zone.get_node("Shape")
	var box := shape_node.shape as BoxShape3D
	return AABB(-box.size / 2.0, box.size).has_point(shape_node.global_transform.affine_inverse() * point)


static func _room_names() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at("res://rooms"):
		if file.ends_with(".tscn"):
			names.append(file.get_basename())
	names.sort()
	return names
