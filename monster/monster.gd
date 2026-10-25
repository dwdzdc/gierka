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
##   VENT_CLIMB  – widocznie wspina się pod kratkę i wciska do szybu (potem VENT)
##   RECOVER     – po ciosie stoi i dochodzi do siebie (styl HIT_AND_RECOVER); trafiony ma okno na reakcję

# Nowe stany dopisujemy na końcu: wartość enum leci przez sieć jako liczba.
enum State { PATROL, INVESTIGATE, HUNT, ATTACK, RETREAT, TRACK, CARRY, FEED, VENT, VENT_CLIMB, RECOVER }

signal state_changed(new_state: State)
signal heard(position: Vector3)

const SCREAM_RADIUS := 28.0
const VENT_SPEED := 6.0  # m/s w szybie
const VENT_ENTER_DISTANCE := 1.3  # jak blisko pod kratką trzeba stanąć, żeby wejść
const VENT_CLIMB_TIME := 1.2  # ile trwa widoczne wspinanie się do kratki
## Z bliska potwór rozpoznaje po dźwięku, KTO hałasuje, i goni go jak widzianego
## (ślepy potwór poluje tylko tak). Ile metrów (przy słuchu 1.0) i jak długo pamięta.
const HEAR_HUNT_DISTANCE := 7.0
## Anty-kiting: ślad gracza co TRAIL_STEP s z ostatnich TRAIL_SIZE * TRAIL_STEP s. Pętla = gracz
## wrócił na LOOP_MATCH_DISTANCE do punktu sprzed co najmniej LOOP_MIN_AGE s.
const TRAIL_STEP := 0.25
const TRAIL_SIZE := 48
const LOOP_MIN_AGE := 3.0
const LOOP_MATCH_DISTANCE := 1.5
const RUN_SPEED_ESTIMATE := 4.6  # bieg gracza; z zapasem, żeby potwór zdążył
const HEAR_MEMORY := 1.2
const SCREAM_INTERVAL := 3.0
const SIGHT_INTERVAL := 0.1
## Drzwi (15n): otwieranie długie (szarpie klamkę), wyważanie krótsze i głośne.
const DOOR_OPEN_TIME := 3.5
const DOOR_BREAK_TIME := 1.2
const DOOR_REACH := 2.2
const DOOR_RATTLE_NOISE := 7.0
const DOOR_BREAK_NOISE := 16.0
## Wyważanie to seria łomotów (co tyle sekund, przy 1,2 s: trzy), każdy słychać daleko.
const DOOR_POUND_INTERVAL := 0.4
const DOOR_POUND_NOISE := 12.0
## Zamknięte drzwi między potworem a źródłem hałasu: tyle z zasięgu hałasu zostaje.
const DOOR_MUFFLE := 0.5
const BASE_HEIGHT := 2.1  # wysokość kapsuły kolizji przy height_scale = 1
const MAX_COLLISION_HEIGHT := Room.DOOR_SIZE.y - 0.2
## Tyle sekund potwór musi widzieć gracza na granicy zasięgu, żeby go zauważyć (bliżej krócej).
const NOTICE_TIME_MAX := 0.8
## Wysokości punktów ciała, w które celuje wzrok (stojąc i kucając).
const SIGHT_POINTS := [1.55, 1.15, 0.5]
const CROUCH_SIGHT_POINTS := [0.85, 0.5]

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
var _door: Door  # drzwi, które właśnie otwiera albo wyważa
var _door_timer := 0.0
var _door_breaking := false
var _rattle_timer := 0.0
var _notice := {}  # Player -> ile sekund z rzędu go widzi (stopniowe zauważanie)
var _stuck_time := 0.0
var _state_time := 0.0  # ile sekund trwa bieżący stan
var _timer := 0.0  # licznik do dyspozycji bieżącego stanu
var _prey: Player  # cel polowania/ataku
var _victim: Player  # porwany (CARRY/FEED)
# Przejście wentylacją: {"entry": Vector3, "exit": Vector3} (kratki), czas w szybie.
var _check_spot: HidingSpot  # szafka do sprawdzenia (INVESTIGATE)
var _checked_this_search := false
var _vent_plan := {}
var _vent_progress := 0.0
var _climb_from := Vector3.ZERO
var _slowed_until := 0.0  # po odzyskiwaniu: do tej chwili (s) goni wolniej
var _burst_until := 0.0  # zryw na początku pościgu: do tej chwili (s)
var _next_burst := 0.0
# Anty-kiting: ślad gracza w pościgu i punkt, w którym potwór chce go przeciąć.
var anti_kiting := true  # do porównań w testach
var _prey_trail: Array[Vector3] = []
var _trail_timer := 0.0
var _intercept := Vector3.INF
var _vent_bang_timer := 0.0
var _heard_new := false
var _smell_timer := 0.0
var _track_time := -INF  # czas najświeższej kropli, do której już doszedł
# Dźwięk kroków liczony u każdego peera z (replikowanej) pozycji, jak u graczy.
var _last_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _step_timer := 0.0


func _ready() -> void:
	add_to_group(&"monsters")
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
	for part in [$Body, $EyeL, $EyeR]:
		part.scale = Vector3.ONE * profile.height_scale
		part.position.y *= profile.height_scale
	# Kolizja rośnie najwyżej do wysokości drzwi: wyższy potwór (strażnik) inaczej nie mieści się
	# w przejściu i utyka w progu własnego pokoju. Wygląd może być wyższy (pochyla się w drzwiach).
	var shape_scale := minf(profile.height_scale, MAX_COLLISION_HEIGHT / BASE_HEIGHT)
	$Shape.scale = Vector3.ONE * shape_scale
	$Shape.position.y *= shape_scale
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
	# W szybie potwora nie widać i nie da się w niego wpaść. Przy wspinaczce widać,
	# ale przenika przez sufit (wciska się w kratkę).
	var in_vent := new_state == State.VENT
	var passing := new_state in [State.VENT, State.VENT_CLIMB]
	for part in [$Body, $EyeL, $EyeR]:
		part.visible = not in_vent
	collision_layer = 0 if passing else 4
	collision_mask = 0 if passing else 9  # świat + kraty (kraty nie zasłaniają wzroku)
	# Podczas pościgu oddech jest głośniejszy i szybszy.
	var hunting := new_state in [State.HUNT, State.ATTACK]
	_breath_player.volume_db = 4.0 if hunting else -2.0
	_breath_player.pitch_scale = 1.35 if hunting else 1.0


func _process(delta: float) -> void:
	if state in [State.VENT, State.VENT_CLIMB]:
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
	if state == State.VENT_CLIMB:
		_climb_into_vent(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_sight(delta)
	_state_time += delta
	var speed := _handle_doors(_think(delta), delta)
	_heard_new = false
	_steer(speed, delta)
	var before := global_position
	move_and_slide()
	_check_stuck(speed, before, delta)


# --- Maszyna stanów ------------------------------------------------------------

func _enter(new_state: State) -> void:
	if new_state != State.INVESTIGATE:
		_check_spot = null
	if new_state != state:
		_checked_this_search = false
		_prey_trail.clear()
		_intercept = Vector3.INF
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
		_start_burst()
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
		State.RECOVER:
			return _recover(delta)
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
	var entry := _vent_in_current_room()
	if entry == Vector3.INF:
		return false
	_vent_plan = {"entry": entry, "exit": target_room.get_vents()[0].global_position}
	_enter(State.PATROL)
	agent.target_position = _floor_below(entry)
	return true


func _approach_vent() -> float:
	var entry: Vector3 = _vent_plan.entry
	var flat := (entry - global_position) * Vector3(1, 0, 1)
	# Wchodzi tylko spod samej kratki. Jeśli nie da się do niej dojść (koniec ścieżki daleko,
	# utknięcie), rezygnuje z szybu i idzie do celu normalnie.
	if flat.length() <= VENT_ENTER_DISTANCE and entry.y - global_position.y < 10.0:
		_vent_progress = 0.0
		_climb_from = global_position
		velocity = Vector3.ZERO
		_enter(State.VENT_CLIMB)
		return 0.0
	if agent.is_navigation_finished() or _stuck_time > 1.0:
		director_goal = _floor_below(_vent_plan.exit)
		_vent_plan = {}
		return 0.0
	return investigate_speed


## Wspinaczka: potwór sunie pod kratkę i podnosi się, aż cały zniknie w suficie.
## Pozycja idzie do klientów zwykłą synchronizacją, więc wszyscy to widzą.
func _climb_into_vent(delta: float) -> void:
	var entry: Vector3 = _vent_plan.entry
	_vent_progress = minf(_vent_progress + delta / VENT_CLIMB_TIME, 1.0)
	# Najpierw dosuwa się pod kratkę, potem w górę, aż stopy znajdą się nad sufitem.
	var under := Vector3(entry.x, _climb_from.y, entry.z)
	var inside := entry + Vector3.UP * 0.3
	var t := _vent_progress
	global_position = _climb_from.lerp(under, minf(t * 3.0, 1.0)).lerp(inside, clampf((t - 0.25) / 0.75, 0.0, 1.0))
	face(entry - global_position, delta)
	if _vent_progress >= 1.0:
		_vent_progress = 0.0
		global_position = entry
		_enter(State.VENT)


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


## Kratka pokoju, w którym potwór stoi (każdy pokój ma swoją). Nie bierzemy "najbliższej
## w linii prostej", bo ta bywa za ścianą, w sąsiednim pokoju.
func _vent_in_current_room() -> Vector3:
	for room in get_tree().get_first_node_in_group(&"main").rooms:
		if (room.transform * room.bounds).has_point(global_position + Vector3.UP * 0.5) and not room.get_vents().is_empty():
			return room.get_vents()[0].global_position
	return Vector3.INF


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


func _return_home() -> float:
	_enter(State.PATROL)
	agent.target_position = random_floor_point_near(home, profile.territory_radius * 0.5)
	return patrol_speed


## Obserwator: stoi w miejscu i powoli się rozgląda. Krzyk przy zobaczeniu gracza to jego "atak".
func _watch(delta: float) -> float:
	rotate_y(0.5 * delta)
	return 0.0


func _investigate(delta: float) -> float:
	if not agent.is_navigation_finished() and not is_watcher():
		return investigate_speed
	if _check_spot:
		_open_hiding_spot()
		return 0.0
	# Na miejscu: czasem zagląda do pobliskiej szafki (tym częściej, im częściej gracze się w nich
	# chowali przed potworami), potem rozgląda się, obracając się w kółko.
	if not _checked_this_search and not is_watcher():
		_checked_this_search = true
		var director := get_tree().get_first_node_in_group(&"monster_director") as MonsterDirector
		var spot := _nearest_hiding_spot(7.0)
		if spot and director and randf() < director.hiding_check_chance():
			check_hiding_spot(spot)
			return investigate_speed
	_timer += delta
	rotate_y(1.5 * delta)
	if _timer >= investigate_linger:
		_enter(State.PATROL)
	return 0.0


## Idź do szafki i zajrzyj do środka.
func check_hiding_spot(spot: HidingSpot) -> void:
	# Gracz zniknął w szafce: zapomnij stary obraz z oczu/uszu, inaczej od razu wróciłby pościg.
	seen_player = null
	heard_player = null
	_enter(State.INVESTIGATE)
	_check_spot = spot
	_checked_this_search = true
	agent.target_position = spot.front_transform().origin


## Otwiera szafkę: jeśli ktoś w niej siedzi, wyciąga go i od razu atakuje.
func _open_hiding_spot() -> void:
	var spot := _check_spot
	_check_spot = null
	$Swing.play()
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	var peer_id := game_state.occupant(str(spot.get_path()))
	if peer_id == 0:
		return
	game_state.force_unhide(peer_id)
	for node in get_tree().get_nodes_in_group(&"players"):
		if node.get_multiplayer_authority() == peer_id:
			_prey = node
			last_seen_position = node.global_position
	_enter(State.ATTACK)
	_state_time = attack_windup * 0.5  # zaskoczony gracz ma mniej czasu na reakcję


func _nearest_hiding_spot(max_distance: float) -> HidingSpot:
	var best: HidingSpot = null
	for node in get_tree().get_nodes_in_group(&"hiding_spots"):
		var spot := node as HidingSpot
		var distance := spot.global_position.distance_to(global_position)
		if distance <= max_distance and (best == null or distance < best.global_position.distance_to(global_position)):
			best = spot
	return best


func _hunt(delta: float) -> float:
	var sensed := sensed_prey()
	if sensed:
		_prey = sensed
		_timer = 0.0
	else:
		_timer += delta
		if _timer >= lose_sight_time:
			if profile.behavior == MonsterProfile.Behavior.GUARD:
				# Strażnik nie szuka zgubionego gracza: wraca pilnować gniazda.
				return _return_home()
			# Zgubił gracza: idzie sprawdzić, gdzie go ostatnio widział.
			_enter(State.INVESTIGATE)
			agent.target_position = last_seen_position
			return investigate_speed
	if is_watcher():
		return _scream(delta)
	# Strażnik goni gracza także poza rewir, ale nie przez całą mapę: za długą smyczą odpuszcza.
	if profile.behavior == MonsterProfile.Behavior.GUARD and global_position.distance_to(home) > profile.leash:
		return _return_home()
	agent.target_position = last_seen_position
	if sensed and global_position.distance_to(sensed.global_position) <= attack_range:
		_enter(State.ATTACK)
		return 0.0
	_cut_off_kiting(sensed, delta)
	var now := Time.get_ticks_msec() / 1000.0
	if now < _slowed_until:
		return hunt_speed * profile.slowed_factor
	if now < _burst_until:
		return maxf(profile.burst_speed, hunt_speed)
	return hunt_speed


func _start_burst() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if profile.burst_speed > 0.0 and now >= _next_burst:
		_burst_until = now + profile.burst_time
		_next_burst = now + profile.burst_cooldown


## Anty-kiting: gracz biega w kółko wokół przeszkody (fontanna, regał, pętla korytarzy), a potwór
## idzie za nim po NavMesh i nigdy go nie dogania. Potwór pamięta trasę gracza; gdy gracz wraca
## tam, gdzie już był (pętla), wybiera punkt na tej trasie, do którego zdąży przed graczem,
## i idzie tam (zwykle drugą stroną przeszkody, naprzeciw). Na miejscu czeka.
func _cut_off_kiting(sensed: Player, delta: float) -> void:
	# Chwilowa utrata kontaktu (np. trzon fontanny zasłania) nie kasuje śladu; nowy pościg tak (_enter).
	if sensed == null or not anti_kiting:
		return
	_trail_timer -= delta
	if _trail_timer > 0.0:
		if _intercept != Vector3.INF:
			agent.target_position = _intercept
		return
	_trail_timer = TRAIL_STEP
	var position := sensed.global_position
	_prey_trail.append(position)
	if _prey_trail.size() > TRAIL_SIZE:
		_prey_trail.remove_at(0)
	_intercept = _loop_intercept(position)
	if _intercept != Vector3.INF:
		agent.target_position = _intercept


## Szuka pętli w śladzie gracza: dawny punkt (sprzed co najmniej LOOP_MIN_AGE), w którym gracz
## znów jest. Jeśli jest, to punkty śladu po nim pokazują, którędy gracz zaraz pobiegnie.
## Zwraca pierwszy taki punkt, do którego potwór dojdzie szybciej niż gracz, albo INF.
func _loop_intercept(position: Vector3) -> Vector3:
	var newest := _prey_trail.size() - 1
	var loop_start := -1
	for i in range(newest - int(LOOP_MIN_AGE / TRAIL_STEP), -1, -1):
		if _prey_trail[i].distance_to(position) <= LOOP_MATCH_DISTANCE:
			loop_start = i
			break
	if loop_start < 0 or newest < 1:
		return Vector3.INF
	# Gracz zawrócił: ślad pętli prowadzi teraz w drugą stronę, więc nie pokazuje, dokąd pobiegnie.
	var heading := _prey_trail[newest] - _prey_trail[newest - 1]
	var loop_heading := _prey_trail[loop_start + 1] - _prey_trail[loop_start]
	if heading.dot(loop_heading) <= 0.0:
		return Vector3.INF
	var prey_distance := 0.0
	for i in range(loop_start + 1, newest):
		prey_distance += _prey_trail[i - 1].distance_to(_prey_trail[i])
		if i % 2 == 1:
			continue  # co drugi punkt wystarczy, liczenie drogi po NavMesh nie jest darmowe
		if _path_length_to(_prey_trail[i]) / hunt_speed < prey_distance / RUN_SPEED_ESTIMATE:
			return _prey_trail[i]
	return Vector3.INF


## Długość drogi po NavMesh do punktu (liczona osobno, bo cel agenta to może już być przewidywanie).
func _path_length_to(point: Vector3) -> float:
	var path := NavigationServer3D.map_get_path(agent.get_navigation_map(), global_position, point, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


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
		elif profile.attack_style == MonsterProfile.AttackStyle.HIT_AND_RECOVER:
			_enter(State.RECOVER)
		else:
			_start_retreat()
	return 0.0


## Po ciosie: stoi (otrząsa się), potem wraca do pościgu, ale przez chwilę wolniej.
func _recover(delta: float) -> float:
	if is_instance_valid(_prey):
		face(_prey.global_position - global_position, delta * 0.3)
	if _state_time >= profile.recover_time:
		_slowed_until = Time.get_ticks_msec() / 1000.0 + profile.slowed_time
		if sensed_prey():
			_enter(State.HUNT)
		else:
			_enter(State.INVESTIGATE)
			agent.target_position = last_seen_position
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


# --- Drzwi ---------------------------------------------------------------------

## Zamknięte drzwi na drodze: potwór staje i je otwiera (powoli, gdy tylko przechodzi) albo
## wyważa (szybko, gdy ma powód: goni, tropi, sprawdza hałas; albo drzwi są zakluczone).
## Patrolujący nie wyważa zakluczonych drzwi, tylko wybiera inny cel.
func _handle_doors(speed: float, delta: float) -> float:
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	if _door:
		if not is_instance_valid(_door) or not _door.blocks():
			_door = null  # ktoś otworzył albo drzwi zniknęły
			return speed
		face(_door.global_position - global_position, delta)
		_door_timer += delta
		_rattle_timer -= delta
		if _rattle_timer <= 0.0:
			_rattle_timer = DOOR_POUND_INTERVAL if _door_breaking else 1.0
			if game_state:
				game_state.monster_rattle(_door.name, _door_breaking)
			NoiseBus.emit_noise(_door.global_position, DOOR_POUND_NOISE if _door_breaking else DOOR_RATTLE_NOISE, self)
		if _door_timer >= (DOOR_BREAK_TIME if _door_breaking else DOOR_OPEN_TIME):
			if game_state:
				game_state.monster_door(_door.name, _door_breaking)
			if _door_breaking:
				NoiseBus.emit_noise(_door.global_position, DOOR_BREAK_NOISE, self)
			_door = null
		return 0.0
	if speed <= 0.0 or agent.is_navigation_finished():
		return speed
	var door := _door_ahead()
	if door == null:
		return speed
	var has_reason := state in [State.HUNT, State.INVESTIGATE, State.TRACK, State.CARRY, State.ATTACK]
	if door.state == Door.State.LOCKED and not has_reason:
		agent.target_position = global_position  # stan wybierze inny cel
		return 0.0
	_door = door
	_door_timer = 0.0
	_rattle_timer = 0.0
	_door_breaking = has_reason or door.state == Door.State.LOCKED
	velocity.x = 0.0
	velocity.z = 0.0
	return 0.0


## Zamknięte drzwi tuż przed potworem, przez które prowadzi jego ścieżka.
func _door_ahead() -> Door:
	var next := agent.get_next_path_position()
	for node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as Door
		if not door.blocks() or door.flat_distance(global_position) > DOOR_REACH or door.lateral(global_position) > 1.2:
			continue
		var here := door.side(global_position)
		if signf(here) != signf(door.side(next)) or signf(here) != signf(door.side(agent.target_position)):
			return door
	return null


## Ile zamkniętych drzwi stoi na odcinku a-b (hałas przez drzwi słychać słabiej).
func _closed_doors_between(a: Vector3, b: Vector3) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as Door
		if not door.blocks():
			continue
		var side_a := door.side(a)
		var side_b := door.side(b)
		if signf(side_a) == signf(side_b):
			continue
		var crossing := a.lerp(b, side_a / (side_a - side_b))
		if door.lateral(crossing) <= Door.SIZE.x / 2.0 + 0.3 and door.flat_distance(crossing) <= Door.SIZE.x:
			count += 1
	return count


# --- Percepcja -----------------------------------------------------------------

func _on_noise(position: Vector3, radius: float, source: Node) -> void:
	if source == self:
		return
	var distance := global_position.distance_to(position)
	radius *= pow(DOOR_MUFFLE, _closed_doors_between(global_position + Vector3.UP, position + Vector3.UP * 0.5))
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
		var peer_id := heard_player.get_multiplayer_authority()
		if game_state == null or (game_state.is_alive(peer_id) and not game_state.is_hidden(peer_id)):
			last_seen_position = heard_player.global_position
			return heard_player
	return null


## Wzrok liczony 10 razy na sekundę, a nie co klatkę: raycasty są tanie, ale bez sensu co klatkę.
## Gracza w bliskiej strefie potwór zauważa od razu; dalszego musi chwilę widzieć (im dalej, tym
## dłużej), chyba że już na niego poluje. Bez tego daleki zasięg działałby jak radar.
func _update_sight(delta: float) -> void:
	_sight_timer -= delta
	if _sight_timer > 0.0:
		return
	_sight_timer = SIGHT_INTERVAL
	seen_player = null
	if sight_range_dark <= 0.0 and sight_range_flashlight <= 0.0:
		return  # ślepy
	var best_distance := INF
	var noticing := {}
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if not can_see(player):
			continue
		var distance := global_position.distance_to(player.global_position)
		var needed := notice_time(player, distance)
		var watched: float = _notice.get(player, 0.0) + SIGHT_INTERVAL
		noticing[player] = watched
		if watched < needed and not (state in [State.HUNT, State.ATTACK] and player == _prey):
			continue
		if distance < best_distance:
			best_distance = distance
			seen_player = player
	_notice = noticing  # kogo przestał widzieć, tego zapomina od zera
	if seen_player:
		last_seen_position = seen_player.global_position


## Ile sekund potwór musi widzieć gracza z tej odległości, żeby go zauważyć.
func notice_time(player: Player, distance: float) -> float:
	var close := sight_range_dark * sense_boost * (Player.CROUCH_SIGHT_FACTOR if player.crouching else 1.0)
	var far := sight_range(player)
	if distance <= close or far <= close:
		return 0.0
	return lerpf(SIGHT_INTERVAL, NOTICE_TIME_MAX, clampf((distance - close) / (far - close), 0.0, 1.0))


## Zasięg wzroku na tego gracza: daleko, gdy świeci latarką albo stoi w oświetlonym pokoju.
func sight_range(player: Player) -> float:
	var visible_far: bool = player.flashlight.visible or not _in_dark_room(player.global_position)
	var result := (sight_range_flashlight if visible_far else sight_range_dark) * sense_boost
	if player.crouching:
		result *= Player.CROUCH_SIGHT_FACTOR
	return result


func _in_dark_room(point: Vector3) -> bool:
	var main := get_tree().get_first_node_in_group(&"main")
	if main == null:
		return false
	for room in main.rooms:
		if is_instance_valid(room) and (room.transform * room.bounds).has_point(point + Vector3.UP * 0.5):
			return room.dark
	return false


func can_see(player: Player) -> bool:
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	if game_state and game_state.life(player.get_multiplayer_authority()) not in [GameState.Life.OK, GameState.Life.DOWNED]:
		return false
	if game_state and game_state.is_hidden(player.get_multiplayer_authority()):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var to_target := player.global_position + Vector3.UP * 1.0 - eye
	if to_target.length() > sight_range(player):
		return false
	var forward := -global_transform.basis.z
	var flat := (to_target * Vector3(1, 0, 1)).normalized()
	if rad_to_deg(forward.angle_to(flat)) > sight_angle_deg / 2.0:
		return false
	# Kilka punktów ciała: wystarczy, że widać którykolwiek (głowa nad skrzynią, nogi pod stołem).
	var space := get_world_3d().direct_space_state
	for height in (CROUCH_SIGHT_POINTS if player.crouching else SIGHT_POINTS):
		var target: Vector3 = player.global_position + Vector3.UP * height
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, sight_blockers))
		if hit.is_empty():
			return true
		if hit.collider is Door and _sees_through_grate(hit.collider, hit.position):
			var past_door := PhysicsRayQueryParameters3D.create(eye, target, sight_blockers, [hit.collider.get_rid()])
			if space.intersect_ray(past_door).is_empty():
				return true
	return false


## Przez kratkę w drzwiach potwór widzi tylko z bliska i patrząc prosto na drzwi.
func _sees_through_grate(door: Door, hit_position: Vector3) -> bool:
	if not door.in_grate(hit_position) or door.flat_distance(global_position) > Door.GRATE_SIGHT_DISTANCE:
		return false
	var to_door := (door.global_position - global_position) * Vector3(1, 0, 1)
	return rad_to_deg((-global_transform.basis.z).angle_to(to_door.normalized())) <= Door.GRATE_SIGHT_ANGLE


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
