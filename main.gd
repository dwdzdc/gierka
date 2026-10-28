extends Node3D
## Scena gry: mapa składana z modułów + gracze po sieci + pętla rundy.
## Gracze, potwory i monety są spawnowane TYLKO przez hosta. MultiplayerSpawner
## sam odtwarza je u klientów.
##
## Dołączanie: host składa mapę z (seed, liczba pokoi) i wysyła te dwie liczby nowemu
## klientowi. Klient składa identyczną mapę i dopiero wtedy prosi o swoją postać.
##
## Runda: zbierasz monety i wychodzisz windą w hali. Runda kończy się, gdy nikogo nie ma
## już na mapie (każdy zginął albo wyszedł). Potem podsumowanie i host startuje następną.
##
## Start z terminala bez menu:  godot --path . -- --host [--rooms=10] [--seed=1234]
##                              godot --path . -- --join=192.168.1.20

signal navigation_ready

const PLAYER_SCENE := preload("res://player/player.tscn")
const COIN_SCENE := preload("res://loot/coin_pile.tscn")
const KEY_SCENE := preload("res://loot/key_pickup.tscn")
const BATTERY_SCENE := preload("res://loot/battery_pickup.tscn")
## Łup (33c). Kupka na meblu najwyżej tyle nad podłogą, z której się ją zbiera (gracz ma 1,7 m,
## więc wchodzi w walec kupki jeszcze na 0,35 m). PICKUP_REACH: promień walca kupki 0,6
## + promień gracza 0,35, minus zapas.
const LOOT_REACH_HEIGHT := 1.35
const PICKUP_REACH := 0.85
const LOOT_VALUE_MIN := 20
const LOOT_VALUE_MAX := 55
const LOOT_WALL_SEARCH := 3.0  # tak daleko szuka się ściany, do której dosunąć łup
const LOOT_CORNER_SEARCH := 2.0  # a tak daleko drugiej, żeby wejść w kąt
const LOOT_WALL_GAP := 0.35  # odstęp od ściany: kupka ma promień ok. 0,27 m
const LOOT_DOOR_CLEARANCE := 1.8  # nie w przejściu ani pod skrzydłem drzwi
## Kolizje świata, z którymi zderza się gracz (świat + kraty).
const WORLD_MASK := 9
const NAV_SYNC_MAX_FRAMES := 600
## Baterie do latarki: jedna na tyle pokoi mapy (co najmniej jedna).
const ROOMS_PER_BATTERY := 4

@onready var navigation: NavigationRegion3D = $Navigation
@onready var players: Node3D = $Players
@onready var monsters: Node3D = $Monsters
@onready var loot: Node3D = $Loot
@onready var room_parent: Node3D = $Navigation/Rooms
@onready var game_state: GameState = $GameState
@onready var director: MonsterDirector = $MonsterDirector
@onready var fake_alarms: FakeAlarms = $FakeAlarms
@onready var blood_trail: BloodTrail = $BloodTrail
@onready var camera_director: CameraDirector = $CameraDirector
@onready var listener: AudioListener3D = $Listener
@onready var info_label: Label = $HUD/Info
@onready var menu: CanvasLayer = $Menu
@onready var address_input: LineEdit = %Address
@onready var status_label: Label = %Status

var _show_debug := true  # F1 chowa/pokazuje debug w panelu statystyk (ujęcie, potwory, reżyser)
var _stage := 0  # znany etap trudności (klienci dostają go z ogłoszeń reżysera)

## Mapa. Host ustawia seed i liczbę pokoi; klient dostaje je od hosta.
var map_seed := 0
var room_count := 8
## Stały układ zamiast losowego (testy): [[ścieżka pokoju, przejście poprzedniego, przejście nowego], ...]
var map_layout: Array = []
var rooms: Array[Room] = []
var map_connections: Array[Dictionary] = []
var map_loops := 0
## Z planu drzwi (host kładzie tyle kluczy, ile jest zakluczonych drzwi).
var key_rooms: Array[Room] = []
var locked_doors := 0
## Ilu monet szukać na mapie (na pokój, poza halą), oprócz znaczników LootSpawns.
var coins_per_room := 1

var _spectate_index := 0
var _threat_text := ""
# Krwawienie na ekranie: czerwona winieta pulsuje przy każdym ubytku HP.
var _bleed_vignette: TextureRect
var _bleed_pulse := 0.0
var _last_hp := -1
var _last_hit_time := 0.0
var _threat_until := 0


func _ready() -> void:
	add_to_group(&"main")
	camera_director.camera_changed.connect(_on_camera_changed)
	game_state.changed.connect(_on_game_state_changed)
	game_state.doors_changed.connect(_on_doors_changed)
	game_state.player_hit.connect(_on_player_hit)
	game_state.coins_picked.connect(_on_coins_picked)
	game_state.round_finished.connect(_on_round_finished)
	director.new_threat.connect(_on_new_threat)
	director.monster_spawned.connect(func(m: Monster) -> void: m.state_changed.connect(func(_s: Monster.State) -> void: _update_hud()))
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	%NextRoundButton.pressed.connect(request_next_round)
	$HUD.visible = false
	$Summary.visible = false
	_build_bleed_vignette()
	listener.make_current()
	status_label.text = Net.last_disconnect_reason
	players.child_entered_tree.connect(func(_n: Node) -> void: _update_hud.call_deferred())
	players.child_exiting_tree.connect(func(_n: Node) -> void: _update_hud.call_deferred())

	map_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rooms="):
			%RoomCount.value = arg.trim_prefix("--rooms=").to_int()
		elif arg.begins_with("--seed="):
			map_seed = arg.trim_prefix("--seed=").to_int()
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host_pressed()
		elif arg.begins_with("--join="):
			address_input.text = arg.trim_prefix("--join=")
			_on_join_pressed()


## "Uszy" są przy postaci, ale obrócone jak bieżąca kamera: dźwięk z lewej strony
## ekranu słychać z lewej. Domyślnie słuchałaby kamera, czyli z drugiego końca pokoju.
func _process(_delta: float) -> void:
	if $HUD.visible:
		_update_hud()  # postęp akcji "trzymaj klawisz" zmienia się co klatkę
		_update_bleed_vignette(_delta)
		var stats_open := Input.is_action_pressed("show_stats")
		$HUD/StatsPanel.visible = stats_open
		if stats_open:
			%StatsText.text = _stats_text()
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(camera_director.target):
		return
	listener.global_transform = Transform3D(cam.global_transform.basis, camera_director.target.global_position + Vector3.UP * 1.6)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_debug"):
		_show_debug = not _show_debug
	elif event.is_action_pressed("spectate_next"):
		_spectate_index += 1
		_update_spectating()
	elif event.is_action_pressed("next_round"):
		request_next_round()


func _on_host_pressed() -> void:
	room_count = int(%RoomCount.value)
	var err := Net.host()
	if err != OK:
		status_label.text = "Nie można hostować (port %d zajęty?)" % Net.DEFAULT_PORT


func _on_join_pressed() -> void:
	var err := Net.join(address_input.text.strip_edges())
	status_label.text = "Łączenie z %s..." % address_input.text if err == OK else "Zły adres"


func _on_connected() -> void:
	menu.visible = false
	$HUD.visible = true
	if multiplayer.is_server():
		game_state.coins_dropped.connect(_drop_coins)
		game_state.rescued.connect(_on_rescued)
		game_state.player_hid.connect(director.on_player_hid)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_despawn_player)
		_build_map(map_seed, room_count)
		_spawn_player(multiplayer.get_unique_id())
		_populate_round()
	_update_hud()


# --- Mapa ----------------------------------------------------------------------

## Składa mapę i wypieka NavMesh. Ten sam seed i liczba pokoi = ta sama mapa u każdego.
func _build_map(seed_value: int, count: int) -> void:
	map_seed = seed_value
	room_count = count
	camera_director.set_target(camera_director.target)  # zapomnij strefy starej mapy
	for child in room_parent.get_children():
		child.free()
	var generator := MapGenerator.new()
	if map_layout.is_empty():
		rooms = generator.generate(room_parent, map_seed, room_count)
	else:
		rooms = generator.build_chain(room_parent, map_layout)
	map_connections = generator.connections
	map_loops = generator.loops + generator.closed_loops
	game_state.exit_position = generator.exit.global_position if generator.exit else Vector3.INF
	_place_doors(generator)
	# NavMesh potrzebny tylko hostowi (AI potwora). Na dachach i regałach powstają
	# "wyspy" NavMeshu; potwór losuje punkty tylko na poziomie podłogi (Monster.random_floor_point).
	if multiplayer.is_server():
		_bake_navigation()


## Drzwi według planu generatora, u każdego peera tak samo (nazwa = identyfikator w sieci).
## Poza węzłem nawigacji: NavMesh ich nie widzi, potwór sam otwiera albo wyważa drzwi.
func _place_doors(generator: MapGenerator) -> void:
	var holder := get_node_or_null(^"Doors")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Doors"
		add_child(holder)
	for child in holder.get_children():
		child.free()
	var states := {}
	for i in generator.door_plan.size():
		var plan: Dictionary = generator.door_plan[i]
		var door := Door.new()
		door.name = "Door%02d" % i
		door.state = plan.state
		holder.add_child(door)
		door.global_transform = plan.a.global_transform
		states[door.name] = plan.state
	key_rooms = generator.key_rooms
	locked_doors = generator.locked_door_count()
	if multiplayer.is_server():
		game_state.init_doors(states)


func _on_doors_changed() -> void:
	for door in get_tree().get_nodes_in_group(&"doors"):
		door.apply_state(game_state.door_state(door.name))


func _bake_navigation() -> void:
	# Dwie klatki przerwy: CSG musi zbudować geometrię nowych pokoi, a region nawigacji
	# musi się raz zsynchronizować z mapą. Przy wcześniejszym wypiekaniu (sprawdzone
	# testem) siatka miała polygony, ale mapa nawigacji jej nie widziała.
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation.bake_navigation_mesh(false)
	# Mapa nawigacji synchronizuje się z wypieczoną siatką z opóźnieniem, a przy dużych mapach
	# (20+ pokoi) stała liczba klatek nie wystarczała: łup spawnowany za wcześnie dostawał
	# z `map_get_closest_point` punkty spoza mapy i wszystko było odrzucane. Czekamy, aż mapa
	# zna już region z podłogą hali (z limitem, żeby nigdy nie zawisnąć).
	var map := navigation.get_navigation_map()
	var probe := rooms[0].global_position if not rooms.is_empty() else Vector3.ZERO
	# Przy kolejnej rundzie region ma jeszcze starą siatkę, więc sam właściciel punktu nie
	# wystarcza: czekamy też, aż mapa przeliczy się po tym wypiekaniu (nowa iteracja).
	var baked_iteration := NavigationServer3D.map_get_iteration_id(map)
	for i in NAV_SYNC_MAX_FRAMES:
		await get_tree().physics_frame
		# Pusta mapa zwraca (0, 0, 0), a hala stoi w (0, 0, 0): sprawdzamy więc, czy punkt ma
		# właściciela (region nawigacji), a nie samą odległość.
		if i >= 4 and NavigationServer3D.map_get_iteration_id(map) > baked_iteration \
				and NavigationServer3D.map_get_closest_point_owner(map, probe).is_valid():
			break
	navigation_ready.emit()


func _on_peer_connected(peer_id: int) -> void:
	_receive_map.rpc_id(peer_id, map_seed, room_count)


## Klient: dostaje parametry mapy od hosta, składa ją i zgłasza gotowość.
@rpc("authority", "call_remote", "reliable")
func _receive_map(seed_value: int, count: int) -> void:
	_build_map(seed_value, count)
	_client_ready.rpc_id(1)
	_update_hud()


## Host: klient ma już mapę, więc można mu dać postać i dotychczasowe ślady.
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_remote_sender_id())


func _on_disconnected(_reason: String) -> void:
	# Najprościej: wróć do świeżej sceny z menu. Gracze znikną razem z nią.
	get_tree().reload_current_scene.call_deferred()


# --- Runda (host) ----------------------------------------------------------------

## Potwory (przez reżysera) i monety na świeżo złożonej mapie.
func _populate_round() -> void:
	director.start_round(rooms, monsters)
	fake_alarms.start()
	await navigation_ready
	_spawn_loot()


func request_next_round() -> void:
	if not multiplayer.is_server() or not game_state.round_over:
		return
	_start_next_round.rpc(randi(), room_count)


@rpc("authority", "call_local", "reliable")
func _start_next_round(seed_value: int, count: int) -> void:
	$Summary.visible = false
	if multiplayer.is_server():
		director.stop()
		fake_alarms.stop()
		for node in monsters.get_children() + loot.get_children():
			node.queue_free()
		blood_trail.clear_all()
	_build_map(seed_value, count)
	if multiplayer.is_server():
		game_state.reset_for_round()
		var i := 0
		for player in players.get_children():
			player.respawn_at.rpc_id(player.get_multiplayer_authority(), _spawn_transform(i))
			i += 1
		_populate_round()
	_update_spectating()


func _spawn_player(peer_id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)  # nazwa = peer id; Player ustawia z niej autorytet
	player.transform = _spawn_transform(players.get_child_count())
	players.add_child(player, true)
	game_state.add_player(peer_id)
	if peer_id != multiplayer.get_unique_id():
		blood_trail.send_all_to(peer_id)


func _spawn_transform(index: int) -> Transform3D:
	var spawns := rooms[0].get_player_spawns()
	return spawns[index % spawns.size()].global_transform


## Łup (33c): leży tam, gdzie się go szuka – na meblach (znaczniki LootSpawns) albo w kącie
## i pod ścianą, nigdy na środku przejścia. Każde miejsce musi przejść `_loot_reachable`.
## Wartość losowa, niezależna od odległości od hali (34b: wyjście jest gdzie indziej).
func _spawn_loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	for room in rooms.slice(1):
		for marker in room.get_loot_spawns():
			if rng.randf() < 0.7:
				var spot := _furniture_spot(room, marker.global_position)
				if spot.is_finite():
					_spawn_coin_pile(spot, rng.randi_range(LOOT_VALUE_MIN, LOOT_VALUE_MAX))
		for i in coins_per_room:
			var spot := _wall_spot(rng, room)
			if spot.is_finite():
				_spawn_coin_pile(spot, rng.randi_range(LOOT_VALUE_MIN, LOOT_VALUE_MAX))
	_spawn_keys(rng)
	_spawn_batteries(rng)


## Miejsce na meblu ze znacznika (albo bliżej krawędzi, gdy ze środka szerokiego blatu nie
## sięgnie się z ziemi); gdy mebel jest poza zasięgiem, na podłodze w pobliżu, przy ścianie.
func _furniture_spot(room: Room, marker: Vector3) -> Vector3:
	for shift in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var top := _surface_below(marker + shift * 0.35 + Vector3.UP * 0.1, 0.3)
		if top.is_finite() and _loot_reachable(room, top):
			return top
	# Najbliższy NavMesh bywa wysepką na blacie albo w celi za kratą, więc szukamy wokół.
	var map := navigation.get_navigation_map()
	var floor_y := room.global_position.y + 0.2
	for radius in [0.0, 1.0, 2.0]:
		for i in 6:
			var angle := TAU * i / 6.0
			var probe := Vector3(marker.x + cos(angle) * radius, floor_y, marker.z + sin(angle) * radius)
			var spot := _snug(NavigationServer3D.map_get_closest_point(map, probe))
			if spot.is_finite() and _loot_reachable(room, spot):
				return spot
	return Vector3.INF


## Losowe miejsce w pokoju dosunięte do ściany albo mebla (najchętniej w kąt).
func _wall_spot(rng: RandomNumberGenerator, room: Room) -> Vector3:
	var map := navigation.get_navigation_map()
	for attempt in 8:
		var local := Vector3(
			rng.randf_range(room.bounds.position.x + 1.0, room.bounds.end.x - 1.0), 0.2,
			rng.randf_range(room.bounds.position.z + 1.0, room.bounds.end.z - 1.0))
		var point := NavigationServer3D.map_get_closest_point(map, room.to_global(local))
		if point.distance_to(room.to_global(local)) > 1.5:
			continue
		var spot := _snug(point)
		if spot.is_finite() and _loot_reachable(room, spot):
			return spot
	return Vector3.INF


## Przesuwa punkt na podłodze do najbliższej przeszkody (ściana, bok mebla), a jeśli w poprzek
## też coś jest blisko, w kąt. Promienie nisko (0,3 m), więc meble z prześwitem łapią łup pod siebie.
func _snug(point: Vector3) -> Vector3:
	var spot := _surface_below(point + Vector3.UP * 0.3, 1.0)  # NavMesh wisi ok. 0,3 m nad podłogą
	if not spot.is_finite():
		return Vector3.INF
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	var first := _nearest_obstacle(spot, dirs, LOOT_WALL_SEARCH)
	if first.is_empty():
		return Vector3.INF
	spot += first.dir * (first.distance - LOOT_WALL_GAP)
	var across: Array[Vector3] = [first.dir.cross(Vector3.UP), -first.dir.cross(Vector3.UP)]
	var second := _nearest_obstacle(spot, across, LOOT_CORNER_SEARCH)
	if not second.is_empty():
		spot += second.dir * (second.distance - LOOT_WALL_GAP)
	return _surface_below(spot + Vector3.UP * 0.3, 1.0)


## {dir, distance} do najbliższej przeszkody na wysokości 0,3 m w jednym z kierunków, albo {}.
func _nearest_obstacle(floor_point: Vector3, dirs: Array[Vector3], reach: float) -> Dictionary:
	var from := floor_point + Vector3.UP * 0.3
	var best := {}
	for dir in dirs:
		var hit := _ray(from, from + dir * reach)
		if not hit.is_empty() and (best.is_empty() or from.distance_to(hit.position) < best.distance):
			best = {dir = dir, distance = from.distance_to(hit.position)}
	return best


## Łup jest dostępny, gdy: nie wchodzi w żadną bryłę, leży na czymś, nie stoi w przejściu drzwi
## i jest miejsce na NavMeshu połączone z halą, z którego gracz go zbierze (kupka zbiera się,
## gdy kapsuła gracza wejdzie w jej walec) i go widzi (nie przez ścianę ani półkę).
func _loot_reachable(room: Room, spot: Vector3) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.2, 0.5)  # kupka ma ok. 0,45 m średnicy i do 0,2 m wysokości
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(), spot + Vector3.UP * 0.13)
	query.collision_mask = WORLD_MASK
	# Kolizje CSG są puste w środku: kupka całkiem w meblu nie przecina żadnego trójkąta.
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty() \
			or _inside_solid(spot + Vector3.UP * 0.05) or _inside_solid(spot + Vector3.UP * 0.18):
		return false
	if not _surface_below(spot + Vector3.UP * 0.1, 0.2).is_finite():
		return false
	for doorway in room.get_doorways():
		if (doorway.global_position - spot).length() < LOOT_DOOR_CLEARANCE:
			return false
	for item in loot.get_children():
		if (item as Node3D).position.distance_to(spot) < 1.0:
			return false
	var map := navigation.get_navigation_map()
	var hall := NavigationServer3D.map_get_closest_point(map, rooms[0].global_position)
	for drop in [0.0, 0.7, 1.4]:
		for i in 8:
			var angle := TAU * i / 8.0
			var stand := NavigationServer3D.map_get_closest_point(
				map, spot + Vector3(cos(angle) * 0.6, -drop, sin(angle) * 0.6))
			if Vector2(stand.x - spot.x, stand.z - spot.z).length() > PICKUP_REACH + 0.6:
				continue
			var feet := _surface_below(stand + Vector3.UP * 0.3, 1.0)  # NavMesh wisi nad podłogą
			if not feet.is_finite():
				continue
			feet = _step_towards(feet, spot)
			if Vector2(feet.x - spot.x, feet.z - spot.z).length() > PICKUP_REACH:
				continue
			var rise := spot.y - feet.y
			if rise < -0.9 or rise > LOOT_REACH_HEIGHT:
				continue
			var target := spot + Vector3.UP * 0.1
			if not _ray(feet + Vector3.UP * 1.4, target).is_empty() and not _ray(feet + Vector3.UP * 0.6, target).is_empty():
				continue
			var path := NavigationServer3D.map_get_path(map, hall, stand, true)
			if not path.is_empty() and path[-1].distance_to(stand) < 0.3:
				return true
	return false


## NavMesh trzyma się 0,5 m od przeszkód (promień potwora), a gracz ma 0,35 m: z punktu na
## NavMeshu podchodzi bliżej łupu, dopóki jego kapsuła się mieści (sprawdzane fizyką).
func _step_towards(feet: Vector3, spot: Vector3) -> Vector3:
	var flat := (spot - feet) * Vector3(1, 0, 1)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), feet + Vector3.UP * (0.85 + 0.1))
	query.motion = flat.limit_length(0.6)
	query.collision_mask = WORLD_MASK
	var safe := get_world_3d().direct_space_state.cast_motion(query)
	return feet + query.motion * safe[0]


## Czy punkt jest wewnątrz bryły świata.
func _inside_solid(point: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
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


func _surface_below(from: Vector3, depth: float) -> Vector3:
	var hit := _ray(from, from + Vector3.DOWN * depth)
	return Vector3.INF if hit.is_empty() else hit.position


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK))


## Baterie w losowych pokojach poza halą, w kątach i pod ścianą jak łup.
func _spawn_batteries(rng: RandomNumberGenerator) -> void:
	var candidates := rooms.slice(1)
	if candidates.is_empty():
		return
	for i in maxi(1, candidates.size() / ROOMS_PER_BATTERY):
		for attempt in 4:
			var spot := _wall_spot(rng, candidates[rng.randi_range(0, candidates.size() - 1)])
			if spot.is_finite():
				var battery: BatteryPickup = BATTERY_SCENE.instantiate()
				battery.position = spot
				loot.add_child(battery, true)
				break


## Tyle kluczy, ile zakluczonych drzwi, w pokojach osiągalnych bez przechodzenia przez nie.
func _spawn_keys(rng: RandomNumberGenerator) -> void:
	if key_rooms.is_empty():
		return
	var map := navigation.get_navigation_map()
	for i in locked_doors:
		var spot := Vector3.INF
		var room: Room
		for attempt in 4:
			room = key_rooms[rng.randi_range(0, key_rooms.size() - 1)]
			spot = _wall_spot(rng, room)
			if spot.is_finite():
				break
		# Winda może stać za zakluczonymi drzwiami (34b): klucza nie może zabraknąć.
		_spawn_key(spot if spot.is_finite() else NavigationServer3D.map_get_closest_point(map, room.global_position))


func _spawn_key(point: Vector3) -> void:
	var key: KeyPickup = KEY_SCENE.instantiate()
	key.position = point
	loot.add_child(key, true)


func _spawn_coin_pile(position: Vector3, value: int) -> void:
	var pile: CoinPile = COIN_SCENE.instantiate()
	pile.value = value
	pile.position = position
	loot.add_child(pile, true)


func _on_rescued(_peer_id: int, monster_name: String) -> void:
	var monster := monsters.get_node_or_null(monster_name) as Monster
	if monster:
		monster.drop_victim()


func _drop_coins(_peer_id: int, amount: int, position: Vector3) -> void:
	_spawn_coin_pile(position + Vector3.UP * 0.05, amount)


func _despawn_player(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	game_state.remove_player(peer_id)


# --- Wszyscy -------------------------------------------------------------------

func _on_game_state_changed() -> void:
	_update_spectating()
	_update_hud()
	# Ubytek HP bez ciosu = krwawienie (albo zjadanie przez porywacza): puls + lekki wstrząs.
	var me := multiplayer.get_unique_id()
	var hp := game_state.hp(me)
	var recent_hit := Time.get_ticks_msec() / 1000.0 - _last_hit_time < 0.2
	if _last_hp >= 0 and hp < _last_hp and not recent_hit:
		_bleed_pulse = 1.0
		var cam := get_viewport().get_camera_3d() as FixedCamera
		if cam:
			cam.shake(0.05)  # wyraźnie słabiej niż cios (0.25)
	_last_hp = hp


func _build_bleed_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.5, 0, 0, 0), Color(0.5, 0, 0, 0.04), Color(0.6, 0, 0, 0.95)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_bleed_vignette = TextureRect.new()
	_bleed_vignette.texture = texture
	_bleed_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_bleed_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bleed_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bleed_vignette.modulate.a = 0.0
	$HUD.add_child(_bleed_vignette)
	$HUD.move_child(_bleed_vignette, 0)


## Winieta widoczna, póki tracisz krew (krwawienie, powalenie, porwanie). Im mniej HP, tym mocniej.
func _update_bleed_vignette(delta: float) -> void:
	var me := multiplayer.get_unique_id()
	var losing := (game_state.is_up(me) and game_state.is_bleeding(me)) or game_state.is_downed(me) or game_state.is_carried(me)
	_bleed_pulse = maxf(_bleed_pulse - delta * 1.4, 0.0)
	var target := 0.0
	if losing:
		var base := 0.25 + 0.4 * (1.0 - game_state.hp(me) / float(GameState.MAX_HP))
		target = base * (0.55 + 0.45 * _bleed_pulse)
	_bleed_vignette.modulate.a = move_toward(_bleed_vignette.modulate.a, target, delta * 2.0)


## Martwy albo wydostany gracz ogląda kamery żyjącego kolegi (Tab = następny).
func _update_spectating() -> void:
	var me := multiplayer.get_unique_id()
	var own: Player = players.get_node_or_null(str(me))
	if own == null:
		return
	var wanted: Node3D = own
	if not game_state.is_alive(me):
		var alive := players.get_children().filter(func(p: Node) -> bool:
			return game_state.is_alive(p.get_multiplayer_authority()))
		if not alive.is_empty():
			wanted = alive[_spectate_index % alive.size()]
	if camera_director.target != wanted:
		camera_director.set_target(wanted)


func _on_round_finished(results: Array) -> void:
	var lines := ["KONIEC RUNDY", ""]
	for r in results:
		lines.append("%s   %s   wyniesione: %d   wynik rundy: %d   suma: %d" % [
			r.name, "wydostał się" if r.survived else "zginął", r.banked, r.score, r.session])
	lines.append("")
	lines.append("Zero-sum: każdy oddaje %d%% wyniesionych monet; jego część dzielą po równo on i ci, którzy wyszli po nim." % int(GameState.SHARED_FRACTION * 100))
	lines.append("R albo przycisk: następna runda" if multiplayer.is_server() else "Czekaj, aż host zacznie następną rundę.")
	%SummaryText.text = "\n".join(lines)
	%NextRoundButton.visible = multiplayer.is_server()
	$Summary.visible = true


## Nowy etap trudności: ryk z daleka i napis na kilka sekund.
func _on_new_threat(stage: int, monster_name: String) -> void:
	_stage = stage
	_threat_text = "Coś się zmieniło w kompleksie... (etap %d%s)" % [stage, "" if monster_name == "" else ", nowy potwór: " + monster_name]
	_threat_until = Time.get_ticks_msec() + 6000
	$ThreatSound.play()


func _on_coins_picked(_peer_id: int, position: Vector3) -> void:
	$CoinSound.global_position = position + Vector3.UP * 0.5
	$CoinSound.play()


func _on_player_hit(peer_id: int, _amount: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_last_hit_time = Time.get_ticks_msec() / 1000.0
	var victim := players.get_node_or_null(str(peer_id))
	if victim:
		$HitSound.global_position = victim.global_position + Vector3.UP
		$HitSound.play()
		if multiplayer.is_server():
			blood_trail.add_drop(victim.global_position, 1.4)  # rozbryzg przy trafieniu
	if peer_id != multiplayer.get_unique_id():
		return
	$TensionAudio.spike(0.5)
	var cam := get_viewport().get_camera_3d() as FixedCamera
	if cam:
		cam.shake(0.25)
	var flash: ColorRect = $HUD/HitFlash
	flash.modulate.a = 0.6
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.6)


func _on_camera_changed(_zone: CameraZone) -> void:
	_update_hud()


const LIFE_NAMES := {GameState.Life.OK: "w grze", GameState.Life.DOWNED: "powalony",
	GameState.Life.DEAD: "nie żyje", GameState.Life.EXTRACTED: "wydostał się", GameState.Life.CARRIED: "porwany"}


## Stały status (lewy górny róg): tylko to, co potrzebne w tej chwili. Reszta pod Tab.
func _update_hud() -> void:
	var me := multiplayer.get_unique_id()
	var lines: Array[String] = []
	match game_state.life(me):
		GameState.Life.OK:
			var status := "HP %d    monety %d    bandaże %d" % [game_state.hp(me), game_state.coins(me), game_state.bandages(me)]
			var me_player: Player = players.get_node_or_null(str(me))
			if me_player:
				status += "    kondycja %d%%" % roundi(me_player.stamina / Player.STAMINA_MAX * 100.0)
			if game_state.keys(me) > 0:
				status += "    klucze %d" % game_state.keys(me)
			status += "    bateria %d%%" % roundi(100.0 * game_state.battery(me) / GameState.BATTERY_MAX)
			lines.append(status)
			if game_state.is_bleeding(me):
				lines.append("KRWAWISZ  (H - bandaż)")
			if game_state.is_hidden(me):
				lines.append("W SZAFCE  (E - wyjdź)")
		GameState.Life.DOWNED:
			lines.append("POWALONY - wykrwawisz się za %d s. Czekaj na pomoc" % game_state.bleed_out_left(me))
		GameState.Life.CARRIED:
			lines.append("PORWANY!  HP %d - koledzy mogą cię odbić (E przy tobie)" % game_state.hp(me))
		GameState.Life.DEAD:
			lines.append("NIE ŻYJESZ (monety przepadły)")
		GameState.Life.EXTRACTED:
			lines.append("WYDOSTAŁEŚ SIĘ (wyniesione: %d)" % game_state.players.get(me, {}).get("banked", 0))
	if is_instance_valid(camera_director.target) and camera_director.target.name != str(me):
		lines.append("Oglądasz: %s  (Spacja - następny)" % game_state.player_name(camera_director.target.get_multiplayer_authority()))
	var me_node: Player = players.get_node_or_null(str(me))
	if me_node and me_node.help_target:
		lines.append("%s %d%%" % [Player.HELP_NAMES[me_node.help_kind], int(me_node.help_progress * 100)])
	elif me_node and me_node.hint != "":
		lines.append(me_node.hint)
	if Time.get_ticks_msec() < _threat_until:
		lines.append(_threat_text)
	lines.append("[Tab] statystyki")
	info_label.text = "\n".join(lines)
	$HUD/Slats.visible = game_state.is_hidden(me)


## Panel pod Tab: sekcje zamiast jednej długiej linii.
func _stats_text() -> String:
	var me := multiplayer.get_unique_id()
	var t := "[b]GRACZE[/b]\n[table=5]"
	for header in ["Gracz", "Stan", "HP", "Monety", "Wyniesione"]:
		t += "[cell][color=#999999]%s[/color][/cell]" % header
	for peer_id in game_state.players:
		var entry: Dictionary = game_state.players[peer_id]
		var state: String = LIFE_NAMES.get(game_state.life(peer_id), "?")
		if game_state.is_hidden(peer_id):
			state = "w szafce"
		var name: String = entry.name + (" (ty)" if peer_id == me else "")
		for value in [name, state, str(entry.hp), str(entry.coins), str(entry.banked)]:
			t += "[cell]%s[/cell]" % value
	t += "[/table]\n\n"
	t += "[b]RUNDA[/b]\nmapa: seed %d, pokoi %d    etap trudności: %d\n\n" % [map_seed, rooms.size(), director.stage if multiplayer.is_server() else _stage]
	t += "[b]SIEĆ[/b]\n"
	if multiplayer.is_server():
		t += "host, adres do dołączenia: %s (port %d)\n\n" % [", ".join(Net.local_addresses()), Net.DEFAULT_PORT]
	else:
		t += "klient\n\n"
	t += "[b]STEROWANIE[/b]\n"
	t += "WASD ruch (tank)    Shift bieg    Ctrl/C kucanie    Spacja skok    Q obrót 180°    F latarka\n"
	t += "E (trzymaj): podnieś / odbij / bandaż kolegi / szafka / winda    H bandaż    F1 debug    R następna runda (host)\n"
	if _show_debug:
		t += _debug_text()
	else:
		t += "\n[color=#777777]F1: pokaż debug (kamera, potwory, reżyser)[/color]"
	return t


## Debug (F1, w panelu pod Tab). Celowo poza zwykłymi statystykami: pozycje i stany
## potworów zdradzałyby graczom za dużo. Część danych zna tylko host (reżyser, cele).
func _debug_text() -> String:
	var zone := camera_director.current_zone
	var t := "\n[b]DEBUG[/b]\nujęcie: %s\n" % ("-" if not is_instance_valid(zone) else "%s/%s" % [zone.owner.name, zone.name])
	var focus := camera_director.target as Node3D if is_instance_valid(camera_director.target) else null
	var host := multiplayer.is_server()
	t += "\n[b]POTWORY[/b]\n[table=8]"
	for header in ["Typ", "Stan", "Dystans", "Pokój", "Wzrok", "Słuch", "Zagrożenie", "Cel reżysera"]:
		t += "[cell][color=#999999]%s[/color][/cell]" % header
	for node in monsters.get_children():
		var monster := node as Monster
		if monster == null or monster.profile == null:
			continue
		var distance := "-" if focus == null else "%.0f m" % monster.global_position.distance_to(focus.global_position)
		var sight := "ślepy" if monster.sight_range_dark <= 0.0 else "%.0f/%.0f m" % [monster.sight_range_dark * monster.sense_boost, monster.sight_range_flashlight * monster.sense_boost]
		var hearing := "×%.1f" % (monster.hearing * monster.sense_boost)
		var menace := "-"
		var goal := "-"
		if host:
			if director._menace.has(monster):
				menace = "%.0f/%.0f" % [director._menace[monster], MonsterDirector.MENACE_LIMIT]
			if director._cooldown.get(monster, 0.0) > 0.0:
				menace += " (oddech %.0f s)" % director._cooldown[monster]
			if monster.director_goal != Vector3.INF:
				goal = _room_name_at(monster.director_goal)
			elif not monster._vent_plan.is_empty():
				goal = "szyb → " + _room_name_at(monster._vent_plan.exit)
		for value in [monster.profile.display_name, Monster.State.keys()[monster.state], distance, _room_name_at(monster.global_position), sight, hearing, menace, goal]:
			t += "[cell]%s[/cell]" % value
	t += "[/table]\n"
	if host:
		var left := director.stage_seconds() - director._stage_timer
		t += "\n[b]REŻYSER[/b]\netap %d, następny za %d:%02d    potworów %d/%d    szafki sprawdzane z szansą %d%% (ucieczek przez schowanie: %d)\n" % [
			director.stage, int(left) / 60, int(left) % 60, director.monsters().size(), director.max_monsters,
			int(director.hiding_check_chance() * 100), director.hiding_escapes]
		for node in monsters.get_children():
			var monster := node as Monster
			if monster and monster.profile and monster.profile.behavior == MonsterProfile.Behavior.GUARD:
				t += "gniazdo strażnika: %s, przenosiny za %d s\n" % [_room_name_at(monster.home), int(director._relocate.get(monster, 0.0))]
	return t


## Nazwa pokoju, w którego bryle leży punkt (do debugu).
func _room_name_at(point: Vector3) -> String:
	for room in rooms:
		if is_instance_valid(room) and (room.transform * room.bounds).has_point(point):
			return room.name
	return "?"
