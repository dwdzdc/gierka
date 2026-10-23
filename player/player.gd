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
var _air_time := 0.0

## Synchronizowane do innych (wygląd, hałas i wzrok potwora liczone u hosta).
var crouching := false:
	set(value):
		crouching = value
		_apply_crouch_shape()

@onready var _footstep_player: AudioStreamPlayer3D = $Footsteps

enum Help { NONE, REVIVE, BANDAGE, EXTRACT, RESCUE }
const HELP_NAMES := {Help.NONE: "", Help.REVIVE: "PODNOSZENIE", Help.BANDAGE: "BANDAŻ", Help.EXTRACT: "WYJŚCIE", Help.RESCUE: "ODBIJANIE"}
const RESCUE_TIME := 1.5
## Pełna kieszeń hałasuje: przy tylu monetach kroki są słyszalne 2x dalej.
const COINS_FOR_DOUBLE_NOISE := 300.0
const EXTRACT_TIME := 2.0
const STAND_HEIGHT := 1.7
const CROUCH_HEIGHT := 1.0
## Kucanie: wolniej, kroki słychać z ~1/3 odległości, potwór widzi z ~60% zasięgu.
const CROUCH_SPEED := 1.1
const CROUCH_NOISE_FACTOR := 0.35
const CROUCH_SIGHT_FACTOR := 0.6
const JUMP_VELOCITY := 4.5  # ~1 m w górę
const LANDING_NOISE_RADIUS := 7.0

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
	# Kształt kolizji jest wspólnym zasobem sceny: każdy gracz potrzebuje własnej kopii,
	# bo kucanie zmienia jego wysokość.
	$Shape.shape = $Shape.shape.duplicate()
	_tint_body()
	if is_multiplayer_authority():
		get_tree().call_group(&"camera_director", &"set_target", self)


func _game_state() -> GameState:
	return get_tree().get_first_node_in_group(&"game_state")


## Sprawny = może chodzić i działać (nie powalony, nie martwy). Bez GameState (testy) zawsze.
func is_up() -> bool:
	var game_state := _game_state()
	return game_state == null or game_state.is_up(get_multiplayer_authority())


## Powalony albo martwy leży na ziemi, wydostany znika z mapy. Liczone u każdego z GameState,
## bez dodatkowej synchronizacji.
func _process(_delta: float) -> void:
	var game_state := _game_state()
	var life := GameState.Life.OK if game_state == null else game_state.life(get_multiplayer_authority())
	var lying := life in [GameState.Life.DOWNED, GameState.Life.DEAD, GameState.Life.CARRIED]
	$Body.rotation.x = PI / 2.0 if lying else 0.0
	$Body.position.y = 0.35 if lying else 0.85
	$Visor.visible = life != GameState.Life.DEAD
	var gone := life == GameState.Life.EXTRACTED
	visible = not gone
	collision_layer = 0 if gone else 2


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

	if _follow_carrier():
		return
	_update_crouch()
	var helping := _update_help(delta)
	if Input.is_action_just_pressed("jump") and is_on_floor() and is_up() and not crouching and not helping:
		velocity.y = JUMP_VELOCITY
	var desired := Vector3.ZERO if _quick_turning or helping or not is_up() else _tank_movement(delta)
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	var was_airborne := _air_time
	move_and_slide()
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	if is_on_floor() and was_airborne > 0.35:
		_on_landed()


## Kucanie trzyma się klawiszem. Wstać można tylko, gdy nad głową jest miejsce (np. pod stołem nie).
func _update_crouch() -> void:
	var wants := Input.is_action_pressed("crouch") and is_up()
	if wants == crouching:
		return
	if not wants and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		return  # coś nad głową: zostajemy w kucki
	crouching = wants


func _apply_crouch_shape() -> void:
	if not is_node_ready():
		await ready
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var capsule := $Shape.shape as CapsuleShape3D
	capsule.height = height
	$Shape.position.y = height / 2.0
	$Body.scale.y = height / STAND_HEIGHT
	$Body.position.y = height / 2.0
	$Visor.position.y = height - 0.25


## Lądowanie po skoku/upadku robi hałas. Hałas liczy host, więc klient go zgłasza.
func _on_landed() -> void:
	_footstep_player.volume_db = 0.0
	_footstep_player.play()
	if multiplayer.is_server():
		NoiseBus.emit_noise(global_position, LANDING_NOISE_RADIUS, self)
	else:
		_report_landing.rpc_id(1, global_position)


@rpc("authority", "call_remote", "reliable")
func _report_landing(position: Vector3) -> void:
	# Host ufa zgłoszeniu tylko, gdy zgadza się z pozycją, którą zna.
	if position.distance_to(global_position) < 3.0:
		NoiseBus.emit_noise(position, LANDING_NOISE_RADIUS, self)


## Porwany: pozycją steruje właściciel postaci, więc to on "przykleja" ją do potwora.
## Zwraca true, gdy postać jest niesiona (wtedy nie ma zwykłego ruchu).
func _follow_carrier() -> bool:
	var game_state := _game_state()
	if game_state == null or not game_state.is_carried(get_multiplayer_authority()):
		return false
	var monsters := get_tree().get_first_node_in_group(&"main").get_node_or_null(^"Monsters") if get_tree().get_first_node_in_group(&"main") else null
	var carrier: Node3D = monsters.get_node_or_null(game_state.carrier(get_multiplayer_authority())) if monsters else null
	if carrier:
		global_position = carrier.global_position - carrier.global_transform.basis.z * 0.8 + Vector3.UP * 0.4
		rotation.y = carrier.rotation.y
	velocity = Vector3.ZERO
	return true


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
			target = _nearest_teammate(func(id: int) -> bool: return game_state.is_carried(id))
			kind = Help.RESCUE
			if target == null:
				target = _nearest_teammate(func(id: int) -> bool: return game_state.is_downed(id))
				kind = Help.REVIVE
			if target == null and game_state.bandages(me) > 0:
				target = _nearest_teammate(func(id: int) -> bool: return game_state.is_up(id) and game_state.is_bleeding(id))
				kind = Help.BANDAGE
			if target == null and global_position.distance_to(game_state.exit_position) <= GameState.EXIT_DISTANCE:
				target = self
				kind = Help.EXTRACT
		elif Input.is_action_pressed("bandage_self") and game_state.is_bleeding(me) and game_state.bandages(me) > 0:
			target = self
			kind = Help.BANDAGE
	if target == null or target != help_target or kind != help_kind:
		help_progress = 0.0
	help_target = target
	help_kind = kind if target else Help.NONE
	if help_target == null:
		return false
	var duration: float = {Help.REVIVE: revive_time, Help.BANDAGE: bandage_time, Help.EXTRACT: EXTRACT_TIME, Help.RESCUE: RESCUE_TIME}[kind]
	help_progress += delta / duration
	if help_progress >= 1.0:
		help_progress = 0.0
		var target_id := help_target.get_multiplayer_authority()
		match kind:
			Help.REVIVE:
				game_state.request_revive.rpc_id(1, target_id)
			Help.BANDAGE:
				game_state.request_bandage.rpc_id(1, target_id)
			Help.EXTRACT:
				game_state.request_extract.rpc_id(1)
			Help.RESCUE:
				game_state.request_rescue.rpc_id(1, target_id)
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
	if crouching:
		speed = CROUCH_SPEED
	elif throttle < 0.0:
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
		_footstep_player.volume_db = -20.0 if crouching else (-4.0 if running else -10.0)
		_footstep_player.play()
		if multiplayer.is_server():
			var radius := run_noise_radius if running else walk_noise_radius
			if crouching:
				radius *= CROUCH_NOISE_FACTOR
			var game_state := _game_state()
			if game_state:
				radius *= 1.0 + minf(game_state.coins(get_multiplayer_authority()) / COINS_FOR_DOUBLE_NOISE, 1.0)
			NoiseBus.emit_noise(global_position, radius, self)


func _quick_turn() -> void:
	if _quick_turning:
		return
	_quick_turning = true
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + PI, quick_turn_time).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func() -> void: _quick_turning = false)
