extends SceneTree
# Generator mapy dla wielu seedów:
#  - ile pokoi udało się postawić (cel: room_count)
#  - czy bryły pokoi się nie przecinają
#  - deterministyczność: drugi build z tym samym seedem daje te same transformacje
#  - spójność: ścieżka NavMesh z hali do środka każdego pokoju (poza "wyspami")
#  - piętra: zakres wysokości podłóg

var main: Node3D
var frames := 0
var seeds := [1, 2, 3, 42, 1234, 99999, 7, 8, 9, 10]
var idx := -1
var count := 10
var phase := 0
var first_transforms := []
var problems := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rooms="):
			count = a.trim_prefix("--rooms=").to_int()
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames < 3 or (idx == -1 and frames < 30):  # rozgrzewka serwera nawigacji
		return false
	if phase == 0:
		idx += 1
		if idx >= seeds.size():
			print("PROBLEMY: %d" % problems)
			return true
		main._build_map(seeds[idx], count)
		first_transforms = main.rooms.map(func(r): return r.transform)
		main._build_map(seeds[idx], count)
		var same: bool = first_transforms == main.rooms.map(func(r): return r.transform)
		phase = 1
		frames = 0
		if not same:
			problems += 1
			print("seed %d: NIEDETERMINISTYCZNE" % seeds[idx])
		return false
	# CSG buduje geometrię klatkę po wejściu do drzewa, dopiero potem można wypiec NavMesh.
	if phase == 1 and frames == 2:
		main.navigation.bake_navigation_mesh(false)
	if phase == 1 and frames >= 40:  # duże mapy synchronizują się z serwerem nawigacji dłużej
		phase = 0
		var rooms: Array = main.rooms
		var overlaps := 0
		for i in rooms.size():
			for j in range(i + 1, rooms.size()):
				var a: AABB = (rooms[i].transform * rooms[i].bounds).grow(-0.05)
				if a.intersects(rooms[j].transform * rooms[j].bounds):
					overlaps += 1
		var map: RID = main.navigation.get_navigation_map()
		var start: Vector3 = NavigationServer3D.map_get_closest_point(map, rooms[0].global_position)
		var unreachable := []
		var ys := {}
		# Pokój jest dostępny, jeśli da się dojść do punktu 1.2 m za którymś z jego przejść
		# (środek pokoju bywa na skrzyni albo pod rampą, więc się nie nadaje).
		start = NavigationServer3D.map_get_closest_point(map, rooms[0].get_player_spawns()[0].global_position)
		for r in rooms:
			ys[snappedf(r.global_position.y, 0.1)] = true
			var reachable := false
			for door in r.get_doorways():
				var inside: Vector3 = door.global_position + door.global_transform.basis.z * 1.2 + Vector3.UP * 0.3
				var target: Vector3 = NavigationServer3D.map_get_closest_point(map, inside)
				var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, target, true)
				if not path.is_empty() and path[-1].distance_to(target) < 0.5 and target.distance_to(inside) < 1.0:
					reachable = true
			if not reachable:
				unreachable.append(r.name)
		var names: String = ", ".join(rooms.map(func(r): return r.name))
		if overlaps > 0 or not unreachable.is_empty():
			problems += 1
		if count >= 12 and main.map_loops == 0:
			problems += 1
			print("ZLE seed %d: brak pętli" % seeds[idx])
		var corridors := rooms.filter(func(r): return r.name.contains("Corridor") or r.name.contains("Link") or r.name.contains("Bend")).size()
		print("   korytarze: %d%% (%d z %d)" % [100 * corridors / rooms.size(), corridors, rooms.size()])
		var doors: Array = main.get_tree().get_nodes_in_group(&"doors")
		var locked := doors.filter(func(d): return d.state == d.State.LOCKED).size()
		print("   drzwi: %d na %d przejść (%d%%), zakluczone %d, kluczy do położenia %d, pokoi z kluczami %d" % [doors.size(), main.map_connections.size(), 100 * doors.size() / maxi(main.map_connections.size(), 1), locked, main.locked_doors, main.key_rooms.size()])
		if locked > doors.size() / 10:
			problems += 1
			print("ZLE za dużo zakluczonych drzwi")
		var dead_ends := rooms.filter(func(r): return r.get_doorways().size() - r.find_children("Cap_*", "", true, false).size() <= 1).size()
		print("seed %d: pokoi %d/%d, kolizje %d, niedostępne %s, pętle %d, ślepe zaułki %d, poziomy y %s\n   %s" % [seeds[idx], rooms.size(), count, overlaps, unreachable, main.map_loops, dead_ends, ys.keys(), names])
	return false
