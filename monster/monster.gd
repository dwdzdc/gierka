class_name Monster
extends CharacterBody3D
## Potwór. AI działa wyłącznie u hosta; klienci dostają pozycję, obrót i `state`
## przez MultiplayerSynchronizer (np. do dźwięków i efektów po ich stronie).
## Typy potworów (niewidzialny itd.) będą dziedziczyć z tej klasy i zmieniać
## parametry albo nadpisywać reakcje.
##
## Stany:
##   PATROL      – chodzi między losowymi punktami
##   INVESTIGATE – idzie sprawdzić hałas albo miejsce, gdzie zgubił gracza, rozgląda się
##   HUNT        – widzi gracza i goni
##   ATTACK      – zamach (telegrafowany), potem cios
##   RETREAT     – po ataku odchodzi daleko; daje graczom szansę na reakcję

enum State { PATROL, INVESTIGATE, HUNT, ATTACK, RETREAT }

signal state_changed(new_state: State)
signal heard(position: Vector3)

@export var turn_speed := 8.0

@export_group("Prędkości")
@export var patrol_speed := 1.5
@export var investigate_speed := 2.4
## Szybciej niż chód gracza (2.2), wolniej niż bieg (4.6): ucieczka jest możliwa, ale kosztuje hałas.
@export var hunt_speed := 3.8
@export var retreat_speed := 3.4

@export_group("Zachowanie")
@export var patrol_pause := Vector2(1.0, 3.0)  # losowa pauza między punktami patrolu (s)
@export var investigate_linger := 3.0  # ile się rozgląda na miejscu (s)
@export var lose_sight_time := 1.5  # po tylu sekundach bez kontaktu przestaje gonić
@export var attack_range := 1.4
@export var attack_windup := 0.6
@export var retreat_time := 5.0
@export var retreat_min_distance := 10.0

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

## Wynik percepcji (tylko u hosta). Stan potwora decyduje, co z tym zrobić.
var seen_player: Player
var last_seen_position := Vector3.ZERO
var heard_position := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _sight_timer := 0.0
var _stuck_time := 0.0
var _state_time := 0.0  # ile sekund trwa bieżący stan
var _timer := 0.0  # licznik do dyspozycji bieżącego stanu
var _prey: Player  # cel polowania/ataku
var _heard_new := false


func _ready() -> void:
	if multiplayer.is_server():
		NoiseBus.noise_made.connect(_on_noise)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_sight(delta)
	_state_time += delta
	var speed := _think(delta)
	_heard_new = false
	_steer(speed, delta)
	var before := global_position
	move_and_slide()
	_check_stuck(speed, before, delta)


# --- Maszyna stanów ------------------------------------------------------------

func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_timer = 0.0
	_stuck_time = 0.0
	agent.target_position = global_position  # każdy stan sam ustawia sobie cel


## Decyduje, co robić w tej klatce. Zwraca prędkość, z jaką iść po ścieżce agenta.
func _think(delta: float) -> float:
	# Przejścia wspólne: zobaczenie gracza przerywa patrol i sprawdzanie tropu,
	# a hałas przerywa patrol albo przekierowuje sprawdzanie.
	if seen_player and state in [State.PATROL, State.INVESTIGATE]:
		_prey = seen_player
		_enter(State.HUNT)
	elif _heard_new and state in [State.PATROL, State.INVESTIGATE]:
		_enter(State.INVESTIGATE)
		agent.target_position = heard_position

	match state:
		State.PATROL:
			return _patrol(delta)
		State.INVESTIGATE:
			return _investigate(delta)
		State.HUNT:
			return _hunt(delta)
		State.ATTACK:
			return _attack(delta)
		State.RETREAT:
			return _retreat()
	return 0.0


func _patrol(delta: float) -> float:
	if not agent.is_navigation_finished():
		return patrol_speed
	_timer -= delta
	if _timer > 0.0:
		return 0.0
	var point := random_floor_point()
	if point != Vector3.ZERO:
		agent.target_position = point
		_timer = randf_range(patrol_pause.x, patrol_pause.y)
	return 0.0


func _investigate(delta: float) -> float:
	if not agent.is_navigation_finished():
		return investigate_speed
	# Na miejscu: rozgląda się, obracając się w kółko.
	_timer += delta
	rotate_y(1.5 * delta)
	if _timer >= investigate_linger:
		_enter(State.PATROL)
	return 0.0


func _hunt(delta: float) -> float:
	if seen_player:
		_prey = seen_player
		_timer = 0.0
	else:
		_timer += delta
		if _timer >= lose_sight_time:
			# Zgubił gracza: idzie sprawdzić, gdzie go ostatnio widział.
			_enter(State.INVESTIGATE)
			agent.target_position = last_seen_position
			return investigate_speed
	agent.target_position = last_seen_position
	if seen_player and global_position.distance_to(seen_player.global_position) <= attack_range:
		_enter(State.ATTACK)
		return 0.0
	return hunt_speed


func _attack(delta: float) -> float:
	if is_instance_valid(_prey):
		face(_prey.global_position - global_position, delta)
	if _state_time >= attack_windup:
		_on_attack_land()
		_start_retreat()
	return 0.0


## Moment trafienia. Obrażenia dochodzą w kroku 25.
func _on_attack_land() -> void:
	pass


func _start_retreat() -> void:
	var from := _prey.global_position if is_instance_valid(_prey) else global_position
	_enter(State.RETREAT)
	for i in 10:
		var point := random_floor_point()
		if point != Vector3.ZERO and point.distance_to(from) >= retreat_min_distance:
			agent.target_position = point
			return


func _retreat() -> float:
	if _state_time >= retreat_time or agent.is_navigation_finished():
		_enter(State.PATROL)
		return 0.0
	return retreat_speed


# --- Percepcja -----------------------------------------------------------------

func _on_noise(position: Vector3, radius: float, _source: Node) -> void:
	if global_position.distance_to(position) <= radius * hearing:
		heard_position = position
		_heard_new = true
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


# --- Ruch ----------------------------------------------------------------------

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
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
