class_name Player
extends CharacterBody3D
## Postać gracza. Wejście czyta tylko instancja, którą steruje ten klient
## (is_multiplayer_authority). Offline zawsze true, a po dodaniu sieci
## kopie innych graczy po prostu nie będą reagować na klawiaturę.
## Sterowanie tank: przód/tył wzdłuż kierunku postaci, lewo/prawo obraca,
## więc cięcie kamery nigdy nie zmienia kierunku ruchu.

@export var walk_speed := 2.2
@export var run_speed := 4.6
@export var backward_speed_factor := 0.6
@export var turn_speed := 2.8  # rad/s
@export var acceleration := 14.0
@export var quick_turn_time := 0.28
@export var walk_step_interval := 0.5
@export var run_step_interval := 0.32
@export var walk_noise_radius := 4.0
@export var run_noise_radius := 10.0
## Ile sekund trzeba trzymać klawisz, żeby podnieść kolegę / założyć bandaż.
@export var revive_time := 3.0
@export var bandage_time := 2.0

@onready var flashlight: SpotLight3D = $Flashlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _quick_turning := false
var _last_position := Vector3.ZERO
var _step_timer := 0.0
var _smoothed_speed := 0.0

@onready var _footstep_player: AudioStreamPlayer3D = $Footsteps

enum Help { NONE, REVIVE, BANDAGE }

## Bieżąca akcja "trzymaj klawisz" (tylko u właściciela postaci, do HUD-a).
var help_kind := Help.NONE
var help_target: Player
var help_progress := 0.0


func _enter_tree() -> void:
	# Host nazywa węzeł gracza jego peer id. Właściciel steruje postacią i wysyła jej
	# pozycję (MultiplayerSynchronizer), reszta tylko odbiera.
	if name.is_valid_int():
		set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group(&"players")
	_tint_body()
	if is_multiplayer_authority():
		get_tree().call_group(&"camera_director", &"set_target", self)


func _game_state() -> GameState:
	return get_tree().get_first_node_in_group(&"game_state")


## Sprawny = może chodzić i działać (nie powalony, nie martwy). Bez GameState (testy) zawsze.
func is_up() -> bool:
	var game_state := _game_state()
	return game_state == null or game_state.is_up(get_multiplayer_authority())


## Powalony albo martwy leży na ziemi. Liczone u każdego z GameState, bez dodatkowej synchronizacji.
func _process(_delta: float) -> void:
	var game_state := _game_state()
	var life := GameState.Life.OK if game_state == null else game_state.life(get_multiplayer_authority())
	var lying := life != GameState.Life.OK
	$Body.rotation.x = PI / 2.0 if lying else 0.0
	$Body.position.y = 0.35 if lying else 0.85
	$Visor.visible = life != GameState.Life.DEAD


## Host przenosi gracza (np. respawn). Pozycją steruje właściciel, więc host musi go poprosić.
@rpc("any_peer", "call_local", "reliable")
func respawn_at(spawn: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_transform = spawn
	velocity = Vector3.ZERO


## Każdy gracz w innym kolorze, deterministycznie z peer id (u wszystkich ten sam).
func _tint_body() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fmod(get_multiplayer_authority() * 0.618, 1.0), 0.45, 0.7)
	material.roughness = 0.9
	$Body.material_override = material


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not is_up():
		return
	if event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("quick_turn"):
		_quick_turn()


func _physics_process(delta: float) -> void:
	_footsteps(delta)
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var helping := _update_help(delta)
	var desired := Vector3.ZERO if _quick_turning or helping or not is_up() else _tank_movement(delta)
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()


## Akcje "trzymaj klawisz": E przy powalonym koledze = podnieś, E przy krwawiącym
## koledze = bandaż dla niego, H = bandaż dla siebie. Po upływie czasu prosimy hosta
## o wykonanie. Licznik jest lokalny (to tylko czekanie), decyzję podejmuje host.
## Zwraca true, gdy właśnie coś robimy (wtedy stoimy w miejscu).
func _update_help(delta: float) -> bool:
	var kind := Help.NONE
	var target: Player = null
	var game_state := _game_state()
	if game_state and is_up():
		var me := get_multiplayer_authority()
		if Input.is_action_pressed("interact"):
			target = _nearest_teammate(func(id: int) -> bool: return game_state.is_downed(id))
			kind = Help.REVIVE
			if target == null and game_state.bandages(me) > 0:
				target = _nearest_teammate(func(id: int) -> bool: return game_state.is_up(id) and game_state.is_bleeding(id))
				kind = Help.BANDAGE
		elif Input.is_action_pressed("bandage_self") and game_state.is_bleeding(me) and game_state.bandages(me) > 0:
			target = self
			kind = Help.BANDAGE
	if target == null or target != help_target or kind != help_kind:
		help_progress = 0.0
	help_target = target
	help_kind = kind if target else Help.NONE
	if help_target == null:
		return false
	help_progress += delta / (revive_time if kind == Help.REVIVE else bandage_time)
	if help_progress >= 1.0:
		help_progress = 0.0
		var target_id := help_target.get_multiplayer_authority()
		if kind == Help.REVIVE:
			game_state.request_revive.rpc_id(1, target_id)
		else:
			game_state.request_bandage.rpc_id(1, target_id)
	return true


func _nearest_teammate(matches: Callable) -> Player:
	var best: Player = null
	for node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == self or not matches.call(other.get_multiplayer_authority()):
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance <= GameState.HELP_DISTANCE and (best == null or distance < global_position.distance_to(best.global_position)):
			best = other
	return best


func _tank_movement(delta: float) -> Vector3:
	rotate_y(Input.get_axis("move_right", "move_left") * turn_speed * delta)
	var throttle := Input.get_axis("move_back", "move_forward")
	var speed := walk_speed
	if throttle < 0.0:
		speed *= backward_speed_factor
	elif Input.is_action_pressed("run"):
		speed = run_speed
	# W Godocie "przód" węzła to -Z.
	return -global_transform.basis.z * throttle * speed


## Kroki liczone u KAŻDEGO peera z (replikowanej) pozycji: każdy słyszy kroki każdego,
## bez RPC. U hosta te same kroki są hałasem dla potwora, więc klient nie może go "oszukać".
func _footsteps(delta: float) -> void:
	var measured := ((global_position - _last_position) * Vector3(1, 0, 1)).length() / delta
	_last_position = global_position
	if measured > run_speed * 3.0:  # teleport/spawn, nie ruch
		measured = 0.0
	# Wygładzenie: pozycje z sieci przychodzą nierówno, więc surowa prędkość skacze.
	_smoothed_speed = lerpf(_smoothed_speed, measured, 1.0 - exp(-10.0 * delta))
	if _smoothed_speed < 0.5 or not is_up():
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		var running := _smoothed_speed > walk_speed * 1.3
		_step_timer = run_step_interval if running else walk_step_interval
		_footstep_player.volume_db = -4.0 if running else -10.0
		_footstep_player.play()
		if multiplayer.is_server():
			NoiseBus.emit_noise(global_position, run_noise_radius if running else walk_noise_radius, self)


func _quick_turn() -> void:
	if _quick_turning:
		return
	_quick_turning = true
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + PI, quick_turn_time).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func() -> void: _quick_turning = false)
