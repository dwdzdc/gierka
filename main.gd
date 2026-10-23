extends Node3D
## Scena gry: ręcznie złożone pokoje + gracze po sieci.
## Gracze są spawnowani TYLKO przez hosta. MultiplayerSpawner sam odtwarza ich u klientów.
##
## Start z terminala bez menu:  godot --path . -- --host
##                              godot --path . -- --join=192.168.1.20

const PLAYER_SCENE := preload("res://player/player.tscn")
const MONSTER_SCENE := preload("res://monster/monster.tscn")
## Tymczasowe, do czasu powalenia i podnoszenia (faza 5).
const RESPAWN_DELAY := 8.0

@onready var navigation: NavigationRegion3D = $Navigation
@onready var players: Node3D = $Players
@onready var monsters: Node3D = $Monsters
@onready var spawn_points: Node3D = $SpawnPoints
@onready var game_state: GameState = $GameState
@onready var camera_director: CameraDirector = $CameraDirector
@onready var info_label: Label = $HUD/Info
@onready var menu: CanvasLayer = $Menu
@onready var address_input: LineEdit = %Address
@onready var status_label: Label = %Status

var _show_debug := true


func _ready() -> void:
	camera_director.camera_changed.connect(_on_camera_changed)
	game_state.changed.connect(_update_hud)
	game_state.player_hit.connect(_on_player_hit)
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	%HostButton.pressed.connect(_on_host_pressed)
	%JoinButton.pressed.connect(_on_join_pressed)
	$HUD.visible = false
	# NavMesh liczony w runtime: generator mapy też będzie składał pokoje w locie.
	# Deferred, bo CSG buduje swoją geometrię dopiero po wejściu do drzewa.
	# Uwaga: na dachach i regałach powstają "wyspy" NavMeshu. Potwór losuje punkty
	# tylko na poziomie podłogi (Monster.random_floor_point).
	navigation.bake_navigation_mesh.call_deferred(false)
	status_label.text = Net.last_disconnect_reason
	players.child_entered_tree.connect(func(_n: Node) -> void: _update_hud.call_deferred())
	players.child_exiting_tree.connect(func(_n: Node) -> void: _update_hud.call_deferred())

	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host_pressed()
		elif arg.begins_with("--join="):
			address_input.text = arg.trim_prefix("--join=")
			_on_join_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_debug"):
		_show_debug = not _show_debug
		info_label.visible = _show_debug


func _on_host_pressed() -> void:
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
		game_state.player_died.connect(_respawn_later)
		multiplayer.peer_connected.connect(_spawn_player)
		multiplayer.peer_disconnected.connect(_despawn_player)
		_spawn_player(multiplayer.get_unique_id())
		_spawn_monster()
	_update_hud()


func _on_disconnected(_reason: String) -> void:
	# Najprościej: wróć do świeżej sceny z menu. Gracze znikną razem z nią.
	get_tree().reload_current_scene.call_deferred()


func _spawn_player(peer_id: int) -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)  # nazwa = peer id; Player ustawia z niej autorytet
	var marker := spawn_points.get_child(players.get_child_count() % spawn_points.get_child_count()) as Node3D
	player.transform = marker.transform
	players.add_child(player, true)
	game_state.add_player(peer_id)


func _spawn_monster() -> void:
	var monster: Monster = MONSTER_SCENE.instantiate()
	monster.transform = $MonsterSpawn.transform
	monsters.add_child(monster, true)
	monster.state_changed.connect(func(_s: Monster.State) -> void: _update_hud())


func _respawn_later(peer_id: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var player: Player = players.get_node_or_null(str(peer_id))
	if player == null:
		return  # gracz w międzyczasie wyszedł
	game_state.revive(peer_id)
	var marker := spawn_points.get_child(randi() % spawn_points.get_child_count()) as Node3D
	player.respawn_at.rpc_id(peer_id, marker.global_transform)


func _on_player_hit(peer_id: int, _amount: int) -> void:
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
	var me := multiplayer.get_unique_id()
	if multiplayer.is_server() and monsters.get_child_count() > 0:
		role += "  potwor: %s" % Monster.State.keys()[monsters.get_child(0).state]
	var status := "HP %d" % game_state.hp(me) if game_state.is_alive(me) else "NIE ZYJESZ - powrot za chwile"
	info_label.text = "%s\nWASD ruch  SHIFT bieg  Q obrot  F latarka  F1 ukryj\nujecie: %s\n%s  graczy: %d" % [
		status, shot, role, players.get_child_count()]
