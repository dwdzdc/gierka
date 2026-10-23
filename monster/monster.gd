class_name Monster
extends CharacterBody3D
## Potwór. AI działa wyłącznie u hosta; klienci dostają pozycję, obrót i `state`
## przez MultiplayerSynchronizer (np. do dźwięków i efektów po ich stronie).
## Typy potworów (niewidzialny itd.) będą dziedziczyć z tej klasy i zmieniać
## parametry albo nadpisywać reakcje.

enum State { PATROL, INVESTIGATE, HUNT, ATTACK, RETREAT }

signal state_changed(new_state: State)

@export var patrol_speed := 1.5
@export var turn_speed := 8.0
@export var patrol_pause := Vector2(1.0, 3.0)  # losowa pauza między punktami patrolu (s)

var state := State.PATROL:
	set(value):
		if state != value:
			state = value
			state_changed.emit(value)

@onready var agent: NavigationAgent3D = $Agent

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pause_left := 0.0
var _stuck_time := 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
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
