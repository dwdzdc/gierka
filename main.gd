extends Node3D
## Scena gry: mapa składana z modułów + gracze po sieci.
## Gracze są spawnowani TYLKO przez hosta. MultiplayerSpawner sam odtwarza ich u klientów.
##
## Dołączanie: host składa mapę z (seed, liczba pokoi) i wysyła te dwie liczby nowemu
## klientowi. Klient składa identyczną mapę i dopiero wtedy prosi o swoją postać.
##
## Start z terminala bez menu:  godot --path . -- --host [--rooms=10] [--seed=1234]
##                              godot --path . -- --join=192.168.1.20

const PLAYER_SCENE := preload("res://player/player.tscn")
const MONSTER_SCENE := preload("res://monster/monster.tscn")
## Tymczasowe, do czasu pętli rundy (faza 6): gdy zginą wszyscy, wszyscy wracają na start.
const WIPE_RESET_DELAY := 5.0

@onready var navigation: NavigationRegion3D = $Navigation
@onready var players: Node3D = $Players
@onready var monsters: Node3D = $Monsters
@onready var room_parent: Node3D = $Navigation/Rooms
@onready var game_state: GameState = $GameState
@onready var blood_trail: BloodTrail = $BloodTrail
@onready var camera_director: CameraDirector = $CameraDirector
@onready var listener: AudioListener3D = $Listener
@onready var info_label: Label = $HUD/Info
@onready var menu: CanvasLayer = $Menu
@onready var address_input: LineEdit = %Address
@onready var status_label: Label = %Status

var _show_debug := true

## Mapa. Host ustawia seed i liczbę pokoi; klient dostaje je od hosta.
var map_seed := 0
var room_count := 8
## Stały układ zamiast losowego (testy): [[ścieżka pokoju, przejście poprzedniego, przejście nowego], ...]
var map_layout: Array = []
var rooms: Array[Room] = []
var map_connections: Array[Dictionary] = []


func _ready() -> void:
	camera_director.camera_changed.connect(_on_camera_changed)
	game_state.changed.connect(_update_hud)
	game_state.player_hit.connect(_on_player_hit)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	$HUD.visible = false
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
		_update_hud()  # postęp podnoszenia zmienia się co klatkę
	var cam := get_viewport().get_camera_3d()
	if camera_director.target == null or cam == null:
		return
	listener.global_transform = Transform3D(cam.global_transform.basis, camera_director.target.global_position + Vector3.UP * 1.6)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_debug"):
		_show_debug = not _show_debug
		info_label.visible = _show_debug


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
		game_state.player_died.connect(_on_player_died)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_despawn_player)
		_build_map(map_seed, room_count)
		_spawn_player(multiplayer.get_unique_id())
		_spawn_monster()
	_update_hud()


## Składa mapę i wypieka NavMesh. Ten sam seed i liczba pokoi = ta sama mapa u każdego.
func _build_map(seed_value: int, count: int) -> void:
	map_seed = seed_value
	room_count = count
	for child in room_parent.get_children():
		child.free()
	var generator := MapGenerator.new()
	if map_layout.is_empty():
		rooms = generator.generate(room_parent, map_seed, room_count)
	else:
		rooms = generator.build_chain(room_parent, map_layout)
	map_connections = generator.connections
	# NavMesh potrzebny tylko hostowi (AI potwora). Deferred, bo CSG buduje geometrię
	# dopiero po wejściu do drzewa. Na dachach i regałach powstają "wyspy" NavMeshu;
	# potwór losuje punkty tylko na poziomie podłogi (Monster.random_floor_point).
	if multiplayer.is_server():
		_bake_navigation()


func _bake_navigation() -> void:
	# Dwie klatki przerwy: CSG musi zbudować geometrię nowych pokoi, a region nawigacji
	# musi się raz zsynchronizować z mapą. Przy wcześniejszym wypiekaniu (sprawdzone
	# testem) siatka miała polygony, ale mapa nawigacji jej nie widziała.
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation.bake_navigation_mesh(false)


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


## Potwór startuje w środku najdalszego płaskiego pokoju (bez ramp i schodów, które mają 2 piętra).
func _spawn_monster() -> void:
	var start := rooms[0].global_position
	var lair := rooms[0]
	for room in rooms:
		var flat := room.bounds.size.y < 8.0
		if flat and room.global_position.distance_to(start) > lair.global_position.distance_to(start):
			lair = room
	var monster: Monster = MONSTER_SCENE.instantiate()
	monster.transform = Transform3D(Basis(), lair.global_position + Vector3.UP * 0.05)
	monsters.add_child(monster, true)
	monster.state_changed.connect(func(_s: Monster.State) -> void: _update_hud())


func _on_player_died(_peer_id: int) -> void:
	for peer_id in game_state.players:
		if game_state.is_alive(peer_id):
			return
	await get_tree().create_timer(WIPE_RESET_DELAY).timeout
	blood_trail.clear_all()
	var i := 0
	for player in players.get_children():
		var peer_id: int = player.get_multiplayer_authority()
		game_state.reset_player(peer_id)
		player.respawn_at.rpc_id(peer_id, _spawn_transform(i))
		i += 1


func _on_player_hit(peer_id: int, _amount: int) -> void:
	var victim := players.get_node_or_null(str(peer_id))
	if victim:
		$HitSound.global_position = victim.global_position + Vector3.UP
		$HitSound.play()
		if multiplayer.is_server():
			blood_trail.add_drop(victim.global_position, 1.4)  # rozbryzg przy trafieniu
	if peer_id != multiplayer.get_unique_id():
		return
	var cam := get_viewport().get_camera_3d() as FixedCamera
	if cam:
		cam.shake(0.25)
	var flash: ColorRect = $HUD/HitFlash
	flash.modulate.a = 0.6
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.6)


func _despawn_player(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	game_state.remove_player(peer_id)


func _on_camera_changed(_zone: CameraZone) -> void:
	_update_hud()


func _update_hud() -> void:
	var zone := camera_director.current_zone
	var shot := "-" if zone == null else "%s/%s" % [zone.owner.name, zone.name]
	var role := "host, adres: %s" % ", ".join(Net.local_addresses()) if multiplayer.is_server() else "klient"
	role += "  mapa: seed %d, pokoi %d" % [map_seed, rooms.size()]
	var me := multiplayer.get_unique_id()
	if multiplayer.is_server() and monsters.get_child_count() > 0:
		role += "  potwor: %s" % Monster.State.keys()[monsters.get_child(0).state]
	var status := ""
	match game_state.life(me):
		GameState.Life.OK:
			status = "HP %d  bandaze: %d" % [game_state.hp(me), game_state.bandages(me)]
			if game_state.is_bleeding(me):
				status += "  KRWAWISZ (H - bandaz)"
		GameState.Life.DOWNED:
			status = "POWALONY - wykrwawisz sie za %d s. Czekaj na pomoc" % game_state.bleed_out_left(me)
		GameState.Life.DEAD:
			status = "NIE ZYJESZ"
	var me_node: Player = players.get_node_or_null(str(me))
	if me_node and me_node.help_target:
		var what := "PODNOSZENIE" if me_node.help_kind == Player.Help.REVIVE else "BANDAZ"
		status += "  %s %d%%" % [what, int(me_node.help_progress * 100)]
	info_label.text = "%s\nWASD ruch  SHIFT bieg  Q obrot  F latarka  E (trzymaj) pomoz koledze  F1 ukryj\nujecie: %s\n%s  graczy: %d" % [
		status, shot, role, players.get_child_count()]
