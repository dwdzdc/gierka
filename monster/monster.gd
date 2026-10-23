class_name Monster
extends CharacterBody3D
## Potwór. AI działa wyłącznie u hosta; klienci dostają pozycję, obrót, `state` i `profile_id`
## przez MultiplayerSynchronizer (wygląd i dźwięki liczą lokalnie).
##
## Dwie warstwy AI:
##   - reżyser (MonsterDirector) decyduje zgrubnie, dokąd iść: `director_goal`, gniazdo `home`;
##   - zmysły potwora (wzrok, słuch, węch) szukają gracza lokalnie.
## Typ potwora = MonsterProfile (dane), nie osobna klasa.
##
## Stany:
##   PATROL      – chodzi (cel od reżysera, losowo albo po rewirze); obserwator stoi i się rozgląda
##   INVESTIGATE – sprawdza hałas albo miejsce, gdzie zgubił gracza, rozgląda się
##   HUNT        – widzi gracza i goni (obserwator: stoi, patrzy i krzyczy)
##   ATTACK      – zamach (telegrafowany), potem cios / egzekucja / porwanie
##   RETREAT     – po ataku odchodzi daleko; daje graczom szansę na reakcję
##   TRACK       – idzie śladem krwi od kropli do kropli, w stronę najświeższych
##   CARRY       – niesie porwanego gracza do gniazda (porwany powoli traci życie)
##   FEED        – w gnieździe zjada porwanego (szybciej traci życie); koledzy mogą go odbić
##   VENT        – przemieszcza się szybem wentylacyjnym: niewidoczny, słychać dudnienie nad głową

# Nowe stany dopisujemy na końcu: wartość enum leci przez sieć jako liczba.
enum State { PATROL, INVESTIGATE, HUNT, ATTACK, RETREAT, TRACK, CARRY, FEED, VENT }

signal state_changed(new_state: State)
signal heard(position: Vector3)

const SCREAM_RADIUS := 28.0
const VENT_SPEED := 6.0  # m/s w szybie
const VENT_ENTER_DISTANCE := 1.3  # jak blisko pod kratką trzeba stanąć, żeby wejść
## Z bliska potwór rozpoznaje po dźwięku, KTO hałasuje, i goni go jak widzianego
## (ślepy potwór poluje tylko tak). Ile metrów (przy słuchu 1.0) i jak długo pamięta.
const HEAR_HUNT_DISTANCE := 7.0
const HEAR_MEMORY := 1.2
const SCREAM_INTERVAL := 3.0

## Typ potwora (ustawiany przed dodaniem do drzewa; replikowany przy spawnie).
@export var profile_id := "hunter"

@export var turn_speed := 8.0
@export var patrol_pause := Vector2(1.0, 3.0)  # losowa pauza między punktami patrolu (s)
@export var investigate_linger := 3.0  # ile się rozgląda na miejscu (s)
@export var lose_sight_time := 1.5  # po tylu sekundach bez kontaktu przestaje gonić
@export var retreat_time := 5.0
@export var retreat_min_distance := 10.0
@export var blood_memory := 90.0
@export var eye_height := 1.8
@export_flags_3d_physics var sight_blockers := 1

var profile: MonsterProfile
# Parametry z profilu (kopiowane w _ready, żeby dało się je stroić w trakcie, np. w testach).
var patrol_speed: float
var investigate_speed: float
var hunt_speed: float
var retreat_speed: float
var sight_range_dark: float
var sight_range_flashlight: float
var sight_angle_deg: float
var hearing: float
var smell_radius: float
var attack_range: float
var attack_windup: float
var attack_damage: int
var attack_reach: float

## Ustawiane przez reżysera (tylko host).
var director_goal := Vector3.INF  # dokąd iść w patrolu; INF = brak polecenia
var home := Vector3.ZERO  # gniazdo / środek rewiru
var sense_boost := 1.0  # narastająca trudność: mnożnik zasięgu zmysłów

var state := State.PATROL:
	set(value):
		if state != value:
			state = value
			state_changed.emit(value)

@onready var agent: NavigationAgent3D = $Agent
@onready var _steps_player: AudioStreamPlayer3D = $Steps
@onready var _breath_player: AudioStreamPlayer3D = $Breath

## Wynik percepcji (tylko u hosta). Stan potwora decyduje, co z tym zrobić.
var seen_player: Player
var last_seen_position := Vector3.ZERO
var heard_position := Vector3.ZERO
var heard_player: Player  # kto ostatnio hałasował blisko (polowanie na słuch)
var _heard_player_time := -INF

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _sight_timer := 0.0
var _stuck_time := 0.0
var _state_time := 0.0  # ile sekund trwa bieżący stan
var _timer := 0.0  # licznik do dyspozycji bieżącego stanu
var _prey: Player  # cel polowania/ataku
var _victim: Player  # porwany (CARRY/FEED)
# Przejście wentylacją: {"entry": Vector3, "exit": Vector3} (kratki), czas w szybie.
var _vent_plan := {}
var _vent_progress := 0.0
var _vent_bang_timer := 0.0
var _heard_new := false
var _smell_timer := 0.0
var _track_time := -INF  # czas najświeższej kropli, do której już doszedł
# Dźwięk kroków liczony u każdego peera z (replikowanej) pozycji, jak u graczy.
var _last_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _step_timer := 0.0


func _ready() -> void:
	_apply_profile(MonsterProfile.load_by_id(profile_id))
	home = global_position
	# Stan jest replikowany, więc setter (i sygnał) odpala się też u klientów: efekty są lokalne.
	state_changed.connect(_on_state_visual)
	_last_position = global_position
	# Oddech w pętli. Słychać go tylko z bliska (max_distance w scenie): to główna poszlaka.
	_breath_player.finished.connect(_breath_player.play)
	_breath_player.play(randf() * 3.0)
	if multiplayer.is_server():
		NoiseBus.noise_made.connect(_on_noise)


func _apply_profile(new_profile: MonsterProfile) -> void:
	profile = new_profile
	patrol_speed = profile.patrol_speed
	investigate_speed = profile.investigate_speed
	hunt_speed = profile.hunt_speed
	retreat_speed = profile.retreat_speed
	sight_range_dark = profile.sight_range_dark
	sight_range_flashlight = profile.sight_range_flashlight
	sight_angle_deg = profile.sight_angle_deg
	hearing = profile.hearing
	smell_radius = profile.smell_radius
	attack_range = profile.attack_range
	attack_windup = profile.attack_windup
	attack_damage = profile.attack_damage
	attack_reach = profile.attack_reach
	# Wygląd: kolor ciała i oczu, wzrost.
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = profile.body_color
	body_material.roughness = 1.0
	$Body.material_override = body_material
	var eye_material := StandardMaterial3D.new()
	eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_material.albedo_color = profile.eye_color
	for eye in [$EyeL, $EyeR]:
		eye.material_override = eye_material
	for part in [$Body, $EyeL, $EyeR, $Shape]:
		part.scale = Vector3.ONE * profile.height_scale
		part.position.y *= profile.height_scale
	eye_height = 1.8 * profile.height_scale


func is_watcher() -> bool:
	return profile.behavior == MonsterProfile.Behavior.WATCHER


## Zamach widać i u hosta, i u klientów: oczy rozbłyskują i rosną.
func _on_state_visual(new_state: State) -> void:
	var attacking := new_state == State.ATTACK
	var tween := create_tween().set_parallel()
	for eye in [$EyeL, $EyeR]:
		tween.tween_property(eye, "scale", Vector3.ONE * profile.height_scale * (3.0 if attacking else 1.0), 0.15)
	match new_state:
		State.HUNT:
			$Voice.play()
		State.ATTACK:
			$Swing.play()
	# W szybie potwora nie widać i nie da się w niego wpaść.
	var in_vent := new_state == State.VENT
	for part in [$Body, $EyeL, $EyeR]:
		part.visible = not in_vent
	collision_layer = 0 if in_vent else 4
	collision_mask = 0 if in_vent else 1
	# Podczas pościgu oddech jest głośniejszy i szybszy.
	var hunting := new_state in [State.HUNT, State.ATTACK]
	_breath_player.volume_db = 4.0 if hunting else -2.0
	_breath_player.pitch_scale = 1.35 if hunting else 1.0


func _process(delta: float) -> void:
	if state == State.VENT:
		# Dudnienie w szybie: nieregularne, metaliczne, słychać je przez sufit.
		_vent_bang_timer -= delta
		if _vent_bang_timer <= 0.0:
			_vent_bang_timer = randf_range(0.25, 0.6)
			$VentSound.play()
		return
	var measured := ((global_position - _last_position) * Vector3(1, 0, 1)).length() / maxf(delta, 0.0001)
	_last_position = global_position
	if measured > 20.0:
		measured = 0.0
	_smoothed_speed = lerpf(_smoothed_speed, measured, 1.0 - exp(-10.0 * delta))
	if _smoothed_speed < 0.4:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = clampf(1.4 / _smoothed_speed, 0.3, 0.9)  # szybciej idzie = częstsze kroki
		_steps_player.play()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state == State.VENT:
		_move_in_vent(delta)
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
	# Przejścia wspólne: zobaczenie gracza przerywa patrol, sprawdzanie i tropienie,
	# a hałas przerywa patrol albo przekierowuje sprawdzanie.
	var sensed := sensed_prey()
	if sensed and state in [State.PATROL, State.INVESTIGATE, State.TRACK]:
		_prey = sensed
		_enter(State.HUNT)
	elif _heard_new and state in [State.PATROL, State.INVESTIGATE] and not is_watcher():
		_enter(State.INVESTIGATE)
		agent.target_position = heard_position
	elif state in [State.PATROL, State.INVESTIGATE] and smell_radius > 0.0:
		_smell_timer -= delta
		if _smell_timer <= 0.0:
			_smell_timer = 0.5
			var drop := _smell_blood()
			if not drop.is_empty():
				_enter(State.TRACK)
				_follow_drop(drop)

	match state:
		State.PATROL:
			return _watch(delta) if is_watcher() else _patrol(delta)
		State.INVESTIGATE:
			return _investigate(delta)
		State.HUNT:
			return _hunt(delta)
		State.ATTACK:
			return _attack(delta)
		State.RETREAT:
			return _retreat()
		State.TRACK:
			return _track()
		State.CARRY:
			return _carry()
		State.FEED:
			return _feed(delta)
	return 0.0


## Niesie porwanego do gniazda. Ofiara, która zginęła albo została odbita, kończy porwanie.
func _carry() -> float:
	if not _victim_still_held():
		_start_retreat()
		return 0.0
	agent.target_position = home
	if agent.is_navigation_finished() or global_position.distance_to(home) < 1.5:
		_enter(State.FEED)
		var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
		game_state.set_carry_damage(_victim.get_multiplayer_authority(), profile.feed_damage_per_second)
		return 0.0
	return retreat_speed * 0.85


func _feed(delta: float) -> float:
	if not _victim_still_held():
		_enter(State.PATROL)
		return 0.0
	face(_victim.global_position - global_position, delta)
	return 0.0


func _victim_still_held() -> bool:
	if not is_instance_valid(_victim):
		return false
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	return game_state.carrier(_victim.get_multiplayer_authority()) == name


# --- Wentylacja ----------------------------------------------------------------

## Polecenie reżysera: dostań się do `target_room` szybami. False, jeśli potwór nie umie
## albo nie ma kratek (wtedy reżyser każe iść normalnie).
func vent_travel_to(target_room: Room) -> bool:
	if not profile.can_use_vents or target_room.get_vents().is_empty():
		return false
	var entry := _nearest_vent()
	if entry == Vector3.INF:
		return false
	_vent_plan = {"entry": entry, "exit": target_room.get_vents()[0].global_position}
	_enter(State.PATROL)
	agent.target_position = _floor_below(entry)
	return true


func _approach_vent() -> float:
	var entry: Vector3 = _vent_plan.entry
	var flat := (entry - global_position) * Vector3(1, 0, 1)
	if flat.length() <= VENT_ENTER_DISTANCE or agent.is_navigation_finished():
		_vent_progress = 0.0
		_enter(State.VENT)
		global_position = entry
		velocity = Vector3.ZERO
		return 0.0
	return investigate_speed


func _move_in_vent(delta: float) -> void:
	var entry: Vector3 = _vent_plan.entry
	var exit: Vector3 = _vent_plan.exit
	var length := maxf(entry.distance_to(exit), 0.1)
	_vent_progress = minf(_vent_progress + delta * VENT_SPEED / length, 1.0)
	global_position = entry.lerp(exit, _vent_progress)
	if _vent_progress >= 1.0:
		# Wyjście: zeskok z kratki w suficie. Grawitacja zrobi resztę.
		_vent_plan = {}
		# Cały potwór (z głową) musi zmieścić się pod sufitem, inaczej fizyka wypchnie go na dach.
		global_position = exit - Vector3.UP * (2.1 * profile.height_scale + 0.1)
		velocity = Vector3.ZERO
		_enter(State.INVESTIGATE)
		agent.target_position = _floor_below(exit)
		$Steps.play()


func _nearest_vent() -> Vector3:
	var best := Vector3.INF
	for room in get_tree().get_first_node_in_group(&"main").rooms:
		for vent in room.get_vents():
			var position: Vector3 = vent.global_position
			# Tylko kratki na naszym piętrze (zakres wysokości pokoju).
			if position.y < global_position.y or position.y > global_position.y + 10.0:
				continue
			if best == Vector3.INF or position.distance_to(global_position) < best.distance_to(global_position):
				best = position
	return best


func _floor_below(point: Vector3) -> Vector3:
	var map := agent.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(map, Vector3(point.x, global_position.y + 0.2, point.z))


## Kolega odbił porwanego: potwór puszcza ofiarę i ucieka.
func drop_victim() -> void:
	_victim = null
	_start_retreat()
	_state_time = -6.0  # spłoszony: ucieka dłużej niż po zwykłym ataku (5 + 6 s)


func _patrol(delta: float) -> float:
	if not _vent_plan.is_empty():
		return _approach_vent()
	if not agent.is_navigation_finished():
		return patrol_speed
	_timer -= delta
	if _timer > 0.0:
		return 0.0
	var point := _next_patrol_point()
	if point != Vector3.ZERO:
		agent.target_position = point
		_timer = randf_range(patrol_pause.x, patrol_pause.y)
	return 0.0


## Dokąd iść w patrolu: polecenie reżysera, rewir strażnika albo losowo po mapie.
func _next_patrol_point() -> Vector3:
	if director_goal != Vector3.INF:
		var goal := director_goal
		director_goal = Vector3.INF
		return goal
	if profile.behavior == MonsterProfile.Behavior.GUARD:
		return random_floor_point_near(home, profile.territory_radius)
	return random_floor_point()


## Obserwator: stoi w miejscu i powoli się rozgląda. Krzyk przy zobaczeniu gracza to jego "atak".
func _watch(delta: float) -> float:
	rotate_y(0.5 * delta)
	return 0.0


func _investigate(delta: float) -> float:
	if not agent.is_navigation_finished() and not is_watcher():
		return investigate_speed
	# Na miejscu: rozgląda się, obracając się w kółko.
	_timer += delta
	rotate_y(1.5 * delta)
	if _timer >= investigate_linger:
		_enter(State.PATROL)
	return 0.0


func _hunt(delta: float) -> float:
	var sensed := sensed_prey()
	if sensed:
		_prey = sensed
		_timer = 0.0
	else:
		_timer += delta
		if _timer >= lose_sight_time:
			# Zgubił gracza: idzie sprawdzić, gdzie go ostatnio widział.
			_enter(State.INVESTIGATE)
			agent.target_position = last_seen_position
			return investigate_speed
	if is_watcher():
		return _scream(delta)
	# Strażnik nie goni w nieskończoność: poza smyczą wraca do rewiru.
	if profile.behavior == MonsterProfile.Behavior.GUARD and global_position.distance_to(home) > profile.leash:
		_enter(State.PATROL)
		agent.target_position = random_floor_point_near(home, profile.territory_radius * 0.5)
		return patrol_speed
	agent.target_position = last_seen_position
	if sensed and global_position.distance_to(sensed.global_position) <= attack_range:
		_enter(State.ATTACK)
		return 0.0
	return hunt_speed


## Obserwator widzi gracza: patrzy na niego i co kilka sekund krzyczy. Krzyk to hałas,
## który ściąga inne potwory w miejsce gracza. Bliskiego gracza atakuje.
func _scream(delta: float) -> float:
	if is_instance_valid(_prey):
		face(_prey.global_position - global_position, delta)
		if global_position.distance_to(_prey.global_position) <= attack_range:
			_enter(State.ATTACK)
			return 0.0
	_timer -= delta
	if _state_time > 0.5 and fmod(_state_time, SCREAM_INTERVAL) < delta and is_instance_valid(_prey):
		$Voice.play()
		NoiseBus.emit_noise(_prey.global_position, SCREAM_RADIUS, self)
	return 0.0


func _track() -> float:
	if not agent.is_navigation_finished():
		return investigate_speed
	# Doszedł do kropli: szuka świeższej w pobliżu. Gdy ślad się urywa, rozgląda się.
	var drop := _smell_blood()
	if drop.is_empty():
		_enter(State.INVESTIGATE)
		return 0.0
	_follow_drop(drop)
	return investigate_speed


func _smell_blood() -> Dictionary:
	var trail: BloodTrail = get_tree().get_first_node_in_group(&"blood_trail")
	if trail == null:
		return {}
	var newer_than := maxf(_track_time, trail.now() - blood_memory)
	return trail.freshest_near(global_position, smell_radius * sense_boost, newer_than)


func _follow_drop(drop: Dictionary) -> void:
	_track_time = drop.time
	agent.target_position = drop.position


func _attack(delta: float) -> float:
	if is_instance_valid(_prey):
		face(_prey.global_position - global_position, delta)
	if _state_time >= attack_windup:
		_on_attack_land()
		if state == State.CARRY:
			return 0.0  # porwał: niesie ofiarę zamiast odchodzić
		if is_watcher():
			_enter(State.PATROL)
		else:
			_start_retreat()
	return 0.0


## Moment trafienia. Gracz, który w czasie zamachu odskoczył albo zszedł z linii, unika ciosu.
func _on_attack_land() -> void:
	if not is_instance_valid(_prey):
		return
	var to_prey := (_prey.global_position - global_position) * Vector3(1, 0, 1)
	var forward := -global_transform.basis.z
	if to_prey.length() > attack_reach or rad_to_deg(forward.angle_to(to_prey.normalized())) >= 70.0:
		return
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	var peer_id := _prey.get_multiplayer_authority()
	match profile.attack_style:
		MonsterProfile.AttackStyle.ABDUCT:
			game_state.abduct(peer_id, name, profile.carry_damage_per_second)
			_victim = _prey
			_enter(State.CARRY)
		MonsterProfile.AttackStyle.EXECUTE:
			var trail: BloodTrail = get_tree().get_first_node_in_group(&"blood_trail")
			if trail:
				trail.add_splatter(_prey.global_position)
			game_state.execute(peer_id)
		_:
			game_state.damage(peer_id, attack_damage)


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

func _on_noise(position: Vector3, radius: float, source: Node) -> void:
	if source == self:
		return
	var distance := global_position.distance_to(position)
	if distance <= radius * hearing * sense_boost:
		heard_position = position
		_heard_new = true
		heard.emit(position)
		if source is Player and distance <= HEAR_HUNT_DISTANCE * hearing * sense_boost:
			heard_player = source
			_heard_player_time = Time.get_ticks_msec() / 1000.0


## Gracz, którego potwór teraz "czuje": widzi go albo przed chwilą słyszał z bliska.
func sensed_prey() -> Player:
	if seen_player:
		return seen_player
	if is_instance_valid(heard_player) and Time.get_ticks_msec() / 1000.0 - _heard_player_time <= HEAR_MEMORY:
		var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
		if game_state == null or game_state.is_alive(heard_player.get_multiplayer_authority()):
			last_seen_position = heard_player.global_position
			return heard_player
	return null


## Wzrok liczony 10 razy na sekundę, a nie co klatkę: raycasty są tanie, ale bez sensu co klatkę.
func _update_sight(delta: float) -> void:
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = 0.1
	seen_player = null
	if sight_range_dark <= 0.0 and sight_range_flashlight <= 0.0:
		return  # ślepy
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
	if game_state and game_state.life(player.get_multiplayer_authority()) not in [GameState.Life.OK, GameState.Life.DOWNED]:
		return false
	var eye := global_position + Vector3.UP * eye_height
	var target := player.global_position + Vector3.UP * (0.6 if player.crouching else 1.2)
	var to_target := target - eye
	var max_range := (sight_range_flashlight if player.flashlight.visible else sight_range_dark) * sense_boost
	if player.crouching:
		max_range *= Player.CROUCH_SIGHT_FACTOR
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
		if point != Vector3.ZERO and absf(point.y - global_position.y) < 0.8:
			return point
	# Na innym piętrze nie ma punktów na naszej wysokości: bierzemy dowolny poza dachami.
	for i in 10:
		var point := NavigationServer3D.map_get_random_point(map, agent.navigation_layers, false)
		if point != Vector3.ZERO:
			return point
	return Vector3.ZERO


## Losowy punkt podłogi w promieniu `radius` od `center` (rewir, okolica celu).
func random_floor_point_near(center: Vector3, radius: float) -> Vector3:
	var map := agent.get_navigation_map()
	for i in 10:
		var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
		var point := NavigationServer3D.map_get_closest_point(map, center + offset)
		if point != Vector3.ZERO and absf(point.y - center.y) < 1.0:
			return point
	return NavigationServer3D.map_get_closest_point(map, center)


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
