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
const CONTAINER_SCENE := preload("res://loot/loot_container.tscn")
## Łup (33b): znacznik na meblu do tej wysokości zostaje na meblu (sięga się z ziemi albo skokiem),
## wyżej spada na podłogę. Część znaczników zamienia się w pojemnik do przeszukania.
const LOOT_REACH_HEIGHT := 1.1
const CONTAINER_CHANCE := 0.45
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
var _search_text := ""  # wynik przeszukania pojemnika, przez chwilę w HUD
var _search_until := 0


func _ready() -> void:
	add_to_group(&"main")
	camera_director.camera_changed.connect(_on_camera_changed)
	game_state.changed.connect(_on_game_state_changed)
	game_state.doors_changed.connect(_on_doors_changed)
	game_state.player_hit.connect(_on_player_hit)
	game_state.coins_picked.connect(_on_coins_picked)
	game_state.container_searched.connect(_on_container_searched)
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
	for i in NAV_SYNC_MAX_FRAMES:
		await get_tree().physics_frame
		# Pusta mapa zwraca (0, 0, 0), a hala stoi w (0, 0, 0): sprawdzamy więc, czy punkt ma
		# właściciela (region nawigacji), a nie samą odległość.
		if i >= 4 and NavigationServer3D.map_get_closest_point_owner(map, probe).is_valid():
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


## Łup: na znacznikach LootSpawns (część w pojemnikach do przeszukania, część na meblach)
## i w losowych miejscach pokoi. Wartość losowa, niezależna od odległości od hali (34b: wyjście
## jest gdzie indziej, więc „dalej = cenniej” nie ma już sensu).
func _spawn_loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var map := navigation.get_navigation_map()
	for room in rooms.slice(1):
		var spots: Array[Vector3] = []
		for marker in room.get_loot_spawns():
			if rng.randf() < 0.7:
				spots.append(marker.global_position)
		for i in coins_per_room:
			var local := Vector3(
				rng.randf_range(room.bounds.position.x + 1.5, room.bounds.end.x - 1.5), 0.3,
				rng.randf_range(room.bounds.position.z + 1.5, room.bounds.end.z - 1.5))
			spots.append(room.to_global(local))
		for spot in spots:
			# Na podłodze obok (do NavMesh), chyba że znacznik jest na meblu w zasięgu ręki/skoku.
			var floor_spot := Vector3(spot.x, room.global_position.y + 0.2, spot.z)
			var point := NavigationServer3D.map_get_closest_point(map, floor_spot)
			if point.distance_to(floor_spot) > 1.5:
				continue
			var value := rng.randi_range(13, 40)  # średnio tyle, ile dawało dawne 8–25 × mnożnik odległości
			if rng.randf() < CONTAINER_CHANCE:
				_spawn_container(rng, point, value * 2)
				continue
			var height: float = spot.y - room.global_position.y
			_spawn_coin_pile(spot if height > 0.4 and height <= LOOT_REACH_HEIGHT else point, value)
	_spawn_keys(rng, map)
	_spawn_batteries(rng, map)


## Baterie w losowych pokojach poza halą, na podłodze osiągalnej z NavMesh.
func _spawn_batteries(rng: RandomNumberGenerator, map: RID) -> void:
	var candidates := rooms.slice(1)
	if candidates.is_empty():
		return
	for i in maxi(1, candidates.size() / ROOMS_PER_BATTERY):
		for attempt in 10:
			var room: Room = candidates[rng.randi_range(0, candidates.size() - 1)]
			var local := Vector3(
				rng.randf_range(room.bounds.position.x + 1.5, room.bounds.end.x - 1.5), 0.2,
				rng.randf_range(room.bounds.position.z + 1.5, room.bounds.end.z - 1.5))
			var spot := room.to_global(local)
			var point := NavigationServer3D.map_get_closest_point(map, spot)
			if point.distance_to(spot) > 1.5:
				continue
			var battery: BatteryPickup = BATTERY_SCENE.instantiate()
			battery.position = point
			loot.add_child(battery, true)
			break


## Tyle kluczy, ile zakluczonych drzwi, w pokojach osiągalnych bez przechodzenia przez nie.
func _spawn_keys(rng: RandomNumberGenerator, map: RID) -> void:
	if key_rooms.is_empty():
		return
	for i in locked_doors:
		for attempt in 10:
			var room: Room = key_rooms[rng.randi_range(0, key_rooms.size() - 1)]
			var local := Vector3(
				rng.randf_range(room.bounds.position.x + 1.5, room.bounds.end.x - 1.5), 0.2,
				rng.randf_range(room.bounds.position.z + 1.5, room.bounds.end.z - 1.5))
			var spot := room.to_global(local)
			var point := NavigationServer3D.map_get_closest_point(map, spot)
			if point.distance_to(spot) > 1.5:
				if attempt == 9:
					# Winda może stać za zakluczonymi drzwiami (34b): klucza nie może zabraknąć.
					_spawn_key(NavigationServer3D.map_get_closest_point(map, room.global_position))
				continue
			_spawn_key(point)
			break


func _spawn_key(point: Vector3) -> void:
	var key: KeyPickup = KEY_SCENE.instantiate()
	key.position = point
	loot.add_child(key, true)


## Pojemnik: zwykle monety (więcej niż w kupce, bo trzeba poświęcić czas i hałasować),
## czasem bateria, czasem nic. Zawartość zna tylko host.
func _spawn_container(rng: RandomNumberGenerator, position: Vector3, value: int) -> void:
	var container: LootContainer = CONTAINER_SCENE.instantiate()
	container.position = position
	container.rotation.y = rng.randi_range(0, 3) * PI / 2.0
	var roll := rng.randf()
	if roll < 0.65:
		container.content = LootContainer.Content.COINS
		container.value = value
	elif roll < 0.75:
		container.content = LootContainer.Content.BATTERY
	loot.add_child(container, true)


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


func _on_container_searched(content: int, amount: int) -> void:
	match content:
		LootContainer.Content.COINS:
			_search_text = "Znalazłeś %d monet" % amount
		LootContainer.Content.BATTERY:
			_search_text = "Znalazłeś baterię do latarki"
		_:
			_search_text = "Pusto"
	_search_until = Time.get_ticks_msec() + 2500
	_update_hud()


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
	if Time.get_ticks_msec() < _search_until:
		lines.append(_search_text)
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
