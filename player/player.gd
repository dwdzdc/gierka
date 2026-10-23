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
@export var step_interval := 0.35
@export var walk_noise_radius := 4.0
@export var run_noise_radius := 10.0

@onready var flashlight: SpotLight3D = $Flashlight

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _quick_turning := false
var _last_position := Vector3.ZERO
var _step_timer := 0.0


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


func is_alive() -> bool:
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	return game_state == null or game_state.is_alive(get_multiplayer_authority())


## Martwy leży na ziemi. Liczone u każdego z GameState, nic dodatkowego nie trzeba synchronizować.
func _process(_delta: float) -> void:
	var dead := not is_alive()
	$Body.rotation.x = PI / 2.0 if dead else 0.0
	$Body.position.y = 0.35 if dead else 0.85
	$Visor.visible = not dead


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
	if not is_multiplayer_authority() or not is_alive():
		return
	if event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("quick_turn"):
		_quick_turn()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_emit_footsteps(delta)
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var desired := Vector3.ZERO if _quick_turning or not is_alive() else _tank_movement(delta)
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()


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


## Liczone u hosta dla KAŻDEGO gracza z replikowanej pozycji, więc klient nie może
## "oszukać" hałasu, a host nie potrzebuje żadnego RPC.
func _emit_footsteps(delta: float) -> void:
	var speed := ((global_position - _last_position) * Vector3(1, 0, 1)).length() / delta
	_last_position = global_position
	if speed < 0.5 or speed > run_speed * 3.0:  # stoi albo teleport/spawn
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = step_interval
		var running := speed > walk_speed * 1.3
		NoiseBus.emit_noise(global_position, run_noise_radius if running else walk_noise_radius, self)


func _quick_turn() -> void:
	if _quick_turning:
		return
	_quick_turning = true
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + PI, quick_turn_time).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func() -> void: _quick_turning = false)
