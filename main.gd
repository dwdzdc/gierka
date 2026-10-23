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

var _show_debug := false  # F1: debug w panelu statystyk (ujęcie, stany potworów)
var _stage := 0  # znany etap trudności (klienci dostają go z ogłoszeń reżysera)

## Mapa. Host ustawia seed i liczbę pokoi; klient dostaje je od hosta.
var map_seed := 0
var room_count := 8
## Stały układ zamiast losowego (testy): [[ścieżka pokoju, przejście poprzedniego, przejście nowego], ...]
var map_layout: Array = []
var rooms: Array[Room] = []
var map_connections: Array[Dictionary] = []
var map_loops := 0
## Ilu monet szukać na mapie (na pokój, poza halą), oprócz znaczników LootSpawns.
var coins_per_room := 2

var _spectate_index := 0
var _threat_text := ""
var _threat_until := 0


func _ready() -> void:
	add_to_group(&"main")
	camera_director.camera_changed.connect(_on_camera_changed)
	game_state.changed.connect(_on_game_state_changed)
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
	map_loops = generator.loops
	game_state.exit_position = rooms[0].get_exit().global_position
	# NavMesh potrzebny tylko hostowi (AI potwora). Na dachach i regałach powstają
	# "wyspy" NavMeshu; potwór losuje punkty tylko na poziomie podłogi (Monster.random_floor_point).
	if multiplayer.is_server():
		_bake_navigation()


func _bake_navigation() -> void:
	# Dwie klatki przerwy: CSG musi zbudować geometrię nowych pokoi, a region nawigacji
	# musi się raz zsynchronizować z mapą. Przy wcześniejszym wypiekaniu (sprawdzone
	# testem) siatka miała polygony, ale mapa nawigacji jej nie widziała.
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation.bake_navigation_mesh(false)
	# Jeszcze chwila na synchronizację mapy nawigacji, zanim ktoś zacznie z niej korzystać.
	for i in 5:
		await get_tree().physics_frame
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


## Monety: na znacznikach LootSpawns i w losowych miejscach pokoi. Dalej od hali = cenniejsze
## (chciwość ma kosztować ryzyko). Wszystko kładziemy na podłodze, w zasięgu gracza.
func _spawn_loot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var map := navigation.get_navigation_map()
	var start := rooms[0].global_position
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
			# Na podłogę obok (znacznik może stać na skrzyni, a tam nie da się wejść).
			var floor_spot := Vector3(spot.x, room.global_position.y + 0.2, spot.z)
			var point := NavigationServer3D.map_get_closest_point(map, floor_spot)
			if point.distance_to(floor_spot) > 1.5:
				continue
			var distance := point.distance_to(start)
			var value := roundi(rng.randi_range(5, 20) * (1.0 + distance / 40.0))
			_spawn_coin_pile(point, value)


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
	lines.append("Zero-sum: %d%% wyniesionych monet idzie do puli dzielonej po równo między ocalałych." % int(GameState.SHARED_FRACTION * 100))
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
			lines.append("HP %d    monety %d    bandaże %d" % [game_state.hp(me), game_state.coins(me), game_state.bandages(me)])
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
		t += "\n[color=#777777]F1: debug (kamera, potwory, reżyser)[/color]"
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
