extends SceneTree
# Mylące cięcia (60): po cięciu kierunek ruchu gracza na ekranie nie może się odwrócić
# (zasada 180° z filmu). Liczy się kierunek w poziomie (lewo/prawo): gdy obie kamery stoją po
# tej samej stronie linii ruchu, gracz idący w lewo dalej idzie w lewo, zmienia się najwyżej
# głębia. Gdy obie kamery patrzą wzdłuż ruchu (lewo/prawo prawie zero), liczy się głębia:
# „oddala się” nie może przejść w „idzie na kamerę”, bo wtedy wygląda, jakby zawrócił.
#  - w pokoju (sprawdzane): każda para stref, które na siebie nachodzą albo się stykają,
#    ruch w poprzek ich wspólnej granicy (crossing),
#  - przez drzwi (tylko raport, 60B): strefa tuż przed przejściem po obu stronach.
#   godot --headless --path . -s tests/camera_flip_test.gd [-- --rooms=30 --list]

const SIDE := 0.2  # poniżej tego udziału ruch w poziomie na ekranie jest niezauważalny
const ALONG := 0.3  # obie kamery patrzą wzdłuż ruchu, gdy obie mają mniej niż tyle w poziomie
# Znane wyjątki: boczna alejka przy całej długości pokoju, do której wchodzi się w poprzek z obu
# połówek środkowej alejki. Połówki patrzą w przeciwne strony (inaczej cięcie w środku odwraca
# ruch), więc kamera alejki zgodzi się tylko z jedną. To ślepe zaułki, nie droga przez pokój.
const KNOWN := ["archive: South↔EastAisle", "servers: North↔WestAisle", "servers: South↔EastAisle"]
var main: Node3D
var f := 0
var count := 30
var seeds := [1, 2, 3, 42, 1234]
var list := "--list" in OS.get_cmdline_user_args()
var room_flips := {}  # "pokój: A↔B (kąt)" -> true
var door_pairs := 0
var door_flips := 0
var door_by_type := {}  # "TypA→TypB" -> liczba odwróceń


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rooms="):
			count = a.trim_prefix("--rooms=").to_int()
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)


## Ruch po podłodze na ekranie kamery: x = w prawo, y = w głąb (od kamery).
static func screen_motion(cam: Camera3D, motion: Vector3) -> Vector2:
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0, forward.x)
	return Vector2(motion.dot(right), motion.dot(forward))


## Czy cięcie z kamery a na b przy ruchu `motion` (poziomy, jednostkowy) odwraca kierunek.
static func flips(a: Camera3D, b: Camera3D, motion: Vector3) -> bool:
	var sa := screen_motion(a, motion)
	var sb := screen_motion(b, motion)
	if sa.x * sb.x < 0.0 and minf(absf(sa.x), absf(sb.x)) > SIDE:
		return true
	return maxf(absf(sa.x), absf(sb.x)) < ALONG and sa.y * sb.y < 0.0


static func zone_box(zone: Area3D) -> Array:
	var shape: CollisionShape3D = zone.get_node("Shape")
	return [shape.global_transform, (shape.shape as BoxShape3D).size]


static func contains(zone: Area3D, point: Vector3, margin := 0.0) -> bool:
	var box := zone_box(zone)
	var local: Vector3 = (box[0] as Transform3D).affine_inverse() * point
	var half: Vector3 = box[1] / 2.0 + Vector3.ONE * margin
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


static func zones_of(room: Node) -> Array:
	var holder := room.get_node_or_null("CameraZones")
	return [] if holder == null else holder.get_children()


## Strefa, której kamera pokaże gracza w tym punkcie (najwyższy priorytet).
static func zone_at(room: Node, point: Vector3) -> Area3D:
	var best: Area3D = null
	for zone in zones_of(room):
		if contains(zone, point) and (best == null or zone.camera_priority > best.camera_priority):
			best = zone
	return best


func _check_rooms() -> void:
	for room in main.rooms:
		var zones := zones_of(room)
		for i in zones.size():
			for j in range(i + 1, zones.size()):
				var a: Area3D = zones[i]
				var b: Area3D = zones[j]
				if not _touch(a, b):
					continue
				var motion := crossing(room, a, b)
				if motion == Vector3.ZERO:
					continue
				var key := "%s: %s↔%s" % [room.scene_file_path.get_file().get_basename(), a.name, b.name]
				if not key in KNOWN and flips(a.get_node("Camera"), b.get_node("Camera"), motion):
					room_flips[key] = true


## Kierunek przejścia ze strefy a do b: w poprzek najwęższego nakładania, liczony w układzie
## pokoju (strefy są tam prostokątami wzdłuż osi). Dla równoległych alejek to ruch w bok, a nie
## wzdłuż, jak dałby wektor między środkami. Zwraca kierunek globalny (po obrocie i odbiciu pokoju).
static func crossing(room: Node3D, a: Area3D, b: Area3D) -> Vector3:
	var to_room := room.global_transform.affine_inverse()
	var boxes := []
	for zone in [a, b]:
		var box := zone_box(zone)
		var center: Vector3 = to_room * (box[0] as Transform3D).origin
		var half: Vector3 = (to_room.basis * (box[0] as Transform3D).basis * (box[1] / 2.0)).abs()
		boxes.append([center, half])
	var ca: Vector3 = boxes[0][0]
	var cb: Vector3 = boxes[1][0]
	var ha: Vector3 = boxes[0][1]
	var hb: Vector3 = boxes[1][1]
	var ox := minf(ca.x + ha.x, cb.x + hb.x) - maxf(ca.x - ha.x, cb.x - hb.x)
	var oz := minf(ca.z + ha.z, cb.z + hb.z) - maxf(ca.z - ha.z, cb.z - hb.z)
	var d := cb - ca
	var local := Vector3(signf(d.x), 0, 0) if ox < oz else Vector3(0, 0, signf(d.z))
	var motion := room.global_transform.basis * local
	motion.y = 0.0
	return motion.normalized()


## Czy dwie strefy na siebie nachodzą albo się stykają (próbki środka i rogów jednej w drugiej).
func _touch(a: Area3D, b: Area3D) -> bool:
	for pair in [[a, b], [b, a]]:
		var box := zone_box(pair[0])
		var tf: Transform3D = box[0]
		var half: Vector3 = box[1] / 2.0
		for sx in [-1.0, 0.0, 1.0]:
			for sz in [-1.0, 0.0, 1.0]:
				if contains(pair[1], tf * Vector3(half.x * sx, 0.0, half.z * sz), 0.3):
					return true
	return false


func _check_doors() -> void:
	for connection in main.map_connections:
		var da: Marker3D = connection.a
		var db: Marker3D = connection.b
		var ra: Node = _room_of(da)
		var rb: Node = _room_of(db)
		if ra == null or rb == null:
			continue
		# Punkty 1,2 m w głąb każdego pokoju od środka przejścia.
		var center := (da.global_position + db.global_position) / 2.0 + Vector3.UP * 0.1
		var za := zone_at(ra, center + _inward(ra, center) * 1.2)
		var zb := zone_at(rb, center + _inward(rb, center) * 1.2)
		if za == null or zb == null:
			continue
		door_pairs += 1
		if flips(za.get_node("Camera"), zb.get_node("Camera"), _inward(rb, center)):
			door_flips += 1
			var key := "%s/%s → %s/%s" % [_type(ra), za.name, _type(rb), zb.name]
			door_by_type[key] = door_by_type.get(key, 0) + 1


func _room_of(node: Node) -> Node:
	while node and not node is Room:
		node = node.get_parent()
	return node


func _type(room: Node) -> String:
	return room.scene_file_path.get_file().get_basename()


## Kierunek w głąb pokoju od punktu na jego ścianie (do środka bryły, rzutowany na oś przejścia).
func _inward(room: Node3D, point: Vector3) -> Vector3:
	var to_center: Vector3 = (room.transform * room.bounds).get_center() - point
	to_center.y = 0.0
	return (Vector3(signf(to_center.x), 0, 0) if absf(to_center.x) > absf(to_center.z) else Vector3(0, 0, signf(to_center.z)))


func _physics_process(_d: float) -> bool:
	f += 1
	if f < 30:
		return false
	var idx := f - 30
	if idx < seeds.size():
		main._build_map(seeds[idx], count)
		_check_rooms()
		_check_doors()
		return false
	print("W pokojach: %d par stref z odwróceniem (poza znanymi: %s)" % [room_flips.size(), ", ".join(KNOWN)])
	for key in room_flips:
		print("  ", key)
	print("Przez drzwi: %d z %d przejść (%.0f%%) z odwróceniem" % [door_flips, door_pairs, 100.0 * door_flips / maxi(door_pairs, 1)])
	if list:
		var keys := door_by_type.keys()
		keys.sort_custom(func(x, y): return door_by_type[x] > door_by_type[y])
		for key in keys.slice(0, 25):
			print("  %3d  %s" % [door_by_type[key], key])
	print("OK" if room_flips.is_empty() else "ZLE: odwrócenia w pokojach")
	return true
