extends SceneTree
# Łup dostępny (33c): każda kupka, bateria i klucz na dużych losowych mapach
# (1) nie wchodzi w żadną bryłę, (2) leży na czymś, (3) na podłodze stoi pod ścianą/meblem,
# a nie na środku, (4) da się go zebrać: kapsuła gracza ustawiona na NavMeshu połączonym z halą
# i dosunięta fizyką w stronę łupu wchodzi w jego obszar. Sprawdza prawdziwą fizyką, a nie tą
# samą funkcją, którą `main` wybiera miejsca.
#   godot --headless --path . -s tests/loot_reach_test.gd [-- --seeds=1,2,3]

const WORLD_MASK := 9
var seeds: Array = [11, 22, 33]
var main: Node3D
var f := 0
var ok := true
var seed_index := 0
var ready_frame := -1
var bodies := {}  # łup -> kapsuły testowe
var planted := {}  # podrzucony zły łup -> czego test ma się dopatrzyć


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = Array(arg.trim_prefix("--seeds=").split(",")).map(func(s): return int(s))
	main = load("res://main.tscn").instantiate()
	main.room_count = 20
	root.add_child.call_deferred(main)


func _check(cond: bool, what: String) -> void:
	ok = ok and cond
	if not cond:
		print("ZLE  ", what)


## Kolejne seedy jak kolejna runda w tej samej scenie (mapa składana od nowa w tym samym
## regionie nawigacji – tu łup kiedyś liczył się jeszcze na starej siatce).
func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main.map_seed = seeds[0]
		main.navigation_ready.connect(func(): ready_frame = f)
		main._on_connected()
	for m in main.get_node("Monsters").get_children():
		m.set_physics_process(false)
	if ready_frame < 0:
		return f > 3000 and _fail("mapa się nie wypiekła")
	if f == ready_frame + 3:
		if seed_index == 0:
			_plant_bad_loot()
		_place_bodies()
	if f == ready_frame + 6:
		_verify()
		for list in bodies.values():
			for body in list:
				body.queue_free()
		bodies.clear()
		seed_index += 1
		if seed_index >= seeds.size():
			print("WYNIK: ", "OK" if ok else "BŁĄD")
			return true
		ready_frame = -1
		main._start_next_round(seeds[seed_index], 20)
	return false


func _fail(what: String) -> bool:
	_check(false, what)
	print("WYNIK: BŁĄD")
	return true


func _items() -> Array:
	return main.loot.get_children()


## Gracz zbiera, stojąc na NavMeshu: kapsuły na kilku punktach wokół łupu osiągalnych z hali,
## każda pchnięta fizyką w stronę łupu (zatrzyma ją ściana albo mebel). Wystarczy jedna.
func _place_bodies() -> void:
	var map: RID = main.navigation.get_navigation_map()
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var hall := NavigationServer3D.map_get_closest_point(map, main.rooms[0].global_position)
	for item in _items():
		var pos: Vector3 = item.global_position
		bodies[item] = []
		for drop in [0.0, 0.7, 1.4]:
			for i in 9:
				var offset := Vector3.ZERO if i == 8 else Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * 0.7
				var stand := NavigationServer3D.map_get_closest_point(map, pos + offset + Vector3.DOWN * drop)
				if (stand - pos).length() > 2.5:
					continue
				var path := NavigationServer3D.map_get_path(map, hall, stand, true)
				if path.is_empty() or path[-1].distance_to(stand) > 0.3:
					continue
				var body := CharacterBody3D.new()
				body.collision_layer = 2
				body.collision_mask = WORLD_MASK
				var shape := CollisionShape3D.new()
				shape.shape = CapsuleShape3D.new()
				shape.shape.radius = 0.35
				shape.shape.height = 1.7
				shape.position.y = 0.85
				body.add_child(shape)
				main.add_child(body)
				# NavMesh wisi ok. 0,3 m nad podłogą: kapsuła staje na prawdziwej podłodze.
				var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.3, stand + Vector3.DOWN, WORLD_MASK))
				body.global_position = (floor_hit.position if floor_hit else stand) + Vector3.UP * 0.02
				body.move_and_collide((pos - stand) * Vector3(1, 0, 1))
				bodies[item].append(body)


func _verify() -> void:
	var counts := {}
	for item in _items():
		var kind: String = item.scene_file_path.get_file().get_basename()
		var problems := _problems(item)
		if planted.has(item):
			_check(problems.any(func(p): return p.contains(planted[item])),
				"kontrola: podrzucony łup (%s) wykryty, problemy: %s" % [planted[item], problems])
			continue
		counts[kind] = counts.get(kind, 0) + 1
		for problem in problems:
			_check(false, "seed %d: %s %s %s" % [seeds[seed_index], kind, item.global_position, problem])
	print("seed %d: %s" % [seeds[seed_index], counts])
	planted.clear()


func _problems(item: Area3D) -> Array[String]:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var problems: Array[String] = []
	var pos := item.global_position
	# (1) Wygląd łupu nie wchodzi w świat.
	var box := AABB()
	for mesh in item.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		box = aabb if box.size == Vector3.ZERO else box.merge(aabb)
	var shape := BoxShape3D.new()
	shape.size = (box.size - Vector3.ONE * 0.02).max(Vector3.ONE * 0.01)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), box.get_center())
	query.collision_mask = WORLD_MASK
	# Kolizje CSG są puste w środku (siatka trójkątów): bryła łupu całkiem w meblu nie przecina
	# żadnego trójkąta, więc osobno: czy środek łupu jest wewnątrz bryły.
	if not space.intersect_shape(query, 1).is_empty() or _inside_solid(box.get_center()):
		problems.append("wtopiony w bryłę")
	# (2) Leży na czymś.
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.05, pos + Vector3.DOWN * 0.1, WORLD_MASK)).is_empty():
		problems.append("wisi w powietrzu")
	# (3) Na podłodze: blisko ściany albo mebla.
	var room = _room_at(pos)
	if room and absf(pos.y - room.global_position.y) < 0.3:
		var near := _nearest_obstacle(pos)
		if near > 0.8:
			problems.append("na środku (najbliższa przeszkoda %.1f m)" % near)
	# (4) Da się zebrać.
	var candidates: Array = bodies[item]
	if candidates.is_empty():
		problems.append("nie do zebrania: brak NavMeshu z drogą z hali obok")
	elif not candidates.any(func(b): return item.overlaps_body(b)):
		problems.append("nie do zebrania (%d prób)" % candidates.size())
	return problems


## Czy punkt jest wewnątrz bryły świata.
func _inside_solid(point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	# Promienie nie trafiają w tylne ścianki, więc: najniższy wierzch bryły nad punktem (promień
	# z góry, krok po kroku) i najbliższy spód nad punktem. Na zewnątrz między punktem a tym
	# wierzchem musi być spód (sam punkt jest pod bryłą); w środku bryły spodu nie ma.
	var lowest_top := INF
	var from := point + Vector3.UP * 6.0
	for i in 16:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, point, WORLD_MASK))
		if hit.is_empty():
			break
		lowest_top = hit.position.y
		from = hit.position + Vector3.DOWN * 0.001
	if lowest_top == INF:
		return false
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point + Vector3.UP * 6.0, WORLD_MASK))
	return up.is_empty() or up.position.y > lowest_top + 0.001


func _nearest_obstacle(pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var near := 99.0
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var from := pos + Vector3.UP * 0.3
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 3.0, WORLD_MASK))
		if not hit.is_empty():
			near = minf(near, from.distance_to(hit.position))
	return near


## Kontrola, że test w ogóle łapie złe miejsca: podrzucamy łup w powietrzu, w ścianie
## i na środku pokoju; każdy musi zostać wykryty.
func _plant_bad_loot() -> void:
	var floor_pile: Node3D
	for item in _items():
		var room = _room_at(item.global_position)
		if room and absf(item.global_position.y - room.global_position.y) < 0.3:
			floor_pile = item
			break
	var high: Vector3 = floor_pile.global_position + Vector3.UP * 2.5
	planted[_plant(high)] = "wisi"
	planted[_plant(floor_pile.global_position + Vector3.DOWN * 0.06)] = "wtopiony"  # 6 cm w podłodze
	var map: RID = main.navigation.get_navigation_map()
	for room in main.rooms:
		var center := NavigationServer3D.map_get_closest_point(map, room.global_position + Vector3.UP * 0.2)
		center.y = room.global_position.y
		if _nearest_obstacle(center) > 1.5:
			planted[_plant(center)] = "na środku"
			break
	_check(planted.size() == 3, "kontrola: podrzucone 3 złe miejsca (jest %d)" % planted.size())


func _plant(pos: Vector3) -> Node:
	main._spawn_coin_pile(pos, 10)
	return _items()[-1]


func _room_at(pos: Vector3):
	for room in main.rooms:
		if room.bounds.grow(0.1).has_point(room.to_local(pos)):
			return room
	return null
