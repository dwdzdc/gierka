class_name Monster
extends CharacterBody3D
## Potwór. AI działa wyłącznie u hosta; klienci dostają pozycję, obrót i `state`
## przez MultiplayerSynchronizer (np. do dźwięków i efektów po ich stronie).
## Typy potworów (niewidzialny itd.) będą dziedziczyć z tej klasy i zmieniać
## parametry albo nadpisywać reakcje.

enum State { PATROL, INVESTIGATE, HUNT, ATTACK, RETREAT }

signal state_changed(new_state: State)
signal heard(position: Vector3)

@export var patrol_speed := 1.5
@export var turn_speed := 8.0
@export var patrol_pause := Vector2(1.0, 3.0)  # losowa pauza między punktami patrolu (s)

@export_group("Percepcja")
## Mnożnik promienia hałasu: 1.0 = słyszy dokładnie tak daleko, jak "niesie" hałas.
@export var hearing := 1.0
@export var sight_range_dark := 6.0
## Gracz z włączoną latarką jest widoczny z dużo dalszej odległości.
@export var sight_range_flashlight := 14.0
@export_range(0.0, 360.0) var sight_angle_deg := 120.0
@export var eye_height := 1.8
@export_flags_3d_physics var sight_blockers := 1

var state := State.PATROL:
	set(value):
		if state != value:
			state = value
			state_changed.emit(value)

@onready var agent: NavigationAgent3D = $Agent

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pause_left := 0.0
var _stuck_time := 0.0

## Wynik percepcji (tylko u hosta). Stan potwora decyduje, co z tym zrobić.
var seen_player: Player
var last_seen_position := Vector3.ZERO
var heard_position := Vector3.ZERO
var _sight_timer := 0.0


func _ready() -> void:
	if multiplayer.is_server():
		NoiseBus.noise_made.connect(_on_noise)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_sight(delta)
	var speed := _think(delta)
	_steer(speed, delta)
	var before := global_position
	move_and_slide()
	_check_stuck(speed, before, delta)


## Decyduje, co robić w tej klatce. Zwraca prędkość, z jaką iść po ścieżce agenta.
func _think(delta: float) -> float:
	match state:
		State.PATROL:
			return _patrol(delta)
	return 0.0


func _patrol(delta: float) -> float:
	if not agent.is_navigation_finished():
		return patrol_speed
	if _pause_left > 0.0:
		_pause_left -= delta
		return 0.0
	var point := random_floor_point()
	if point != Vector3.ZERO:
		agent.target_position = point
		_pause_left = randf_range(patrol_pause.x, patrol_pause.y)
	return 0.0


## Losowy punkt NavMeshu na poziomie podłogi. ZERO, jeśli mapa jeszcze niegotowa.
## Odrzuca "wyspy" (wierzchy skrzyń, regałów, dachy), na które nie da się wejść.
func random_floor_point() -> Vector3:
	var map := agent.get_navigation_map()
	for i in 10:
		var point := NavigationServer3D.map_get_random_point(map, agent.navigation_layers, false)
		if point != Vector3.ZERO and point.y < global_position.y + 0.8:
			return point
	return Vector3.ZERO


func _on_noise(position: Vector3, radius: float, _source: Node) -> void:
	if global_position.distance_to(position) <= radius * hearing:
		heard_position = position
		heard.emit(position)


## Wzrok liczony 10 razy na sekundę, a nie co klatkę: raycasty są tanie, ale bez sensu co klatkę.
func _update_sight(delta: float) -> void:
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = 0.1
	seen_player = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if can_see(player):
			var distance := global_position.distance_to(player.global_position)
			if distance < best_distance:
				best_distance = distance
				seen_player = player
	if seen_player:
		last_seen_position = seen_player.global_position


func can_see(player: Player) -> bool:
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	if game_state and not game_state.is_alive(player.get_multiplayer_authority()):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var target := player.global_position + Vector3.UP * 1.2
	var to_target := target - eye
	var max_range := sight_range_flashlight if player.flashlight.visible else sight_range_dark
	if to_target.length() > max_range:
		return false
	var forward := -global_transform.basis.z
	var flat := (to_target * Vector3(1, 0, 1)).normalized()
	if rad_to_deg(forward.angle_to(flat)) > sight_angle_deg / 2.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, sight_blockers)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _steer(speed: float, delta: float) -> void:
	var direction := Vector3.ZERO
	if speed > 0.0 and not agent.is_navigation_finished():
		direction = agent.get_next_path_position() - global_position
		direction.y = 0.0
		direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if direction != Vector3.ZERO:
		face(direction, delta)


## Zabezpieczenie: jeśli chcemy iść, a od 1.5 s stoimy w miejscu, porzuć cel.
## Stan sam wybierze nowy (patrol: kolejny losowy punkt).
func _check_stuck(speed: float, before: Vector3, delta: float) -> void:
	var moved := (global_position - before) * Vector3(1, 0, 1)
	if speed > 0.0 and moved.length() < speed * delta * 0.2:
		_stuck_time += delta
		if _stuck_time > 1.5:
			_stuck_time = 0.0
			agent.target_position = global_position
	else:
		_stuck_time = 0.0


func face(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
