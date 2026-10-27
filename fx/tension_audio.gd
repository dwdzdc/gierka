class_name TensionAudio
extends Node
## Lokalne (u każdego gracza) audio napięcia: im większe zagrożenie, tym ciszej ambient,
## a głośniej i szybciej bicie serca, potem przyspieszony oddech postaci.
##
## Zagrożenie liczymy z odległości do potworów, ale celowo rozmyte i z opóźnieniem,
## żeby nie działało jak radar (filar „niepewność”). Fałszywe alarmy też podbijają serce.

const DANGER_RADIUS := 18.0  # dalej potwór "nie istnieje" dla serca
const HUNT_RADIUS := 25.0  # goniący potwór niepokoi z dalszej odległości
const VENT_RADIUS := 12.0  # coś w szybie nad głową
const RISE_PER_SECOND := 0.7
const FALL_PER_SECOND := 0.2
## Akcent muzyczny (47g.6): potwór w tej odległości zaczyna pościg. Nie mówi, czy goni ciebie,
## czy kolegę obok, ani skąd idzie; przerwa, żeby pętla zgubił–znalazł nie grała co chwilę.
const STINGER_RADIUS := 20.0
const STINGER_COOLDOWN := 15.0

var threat := 0.0  # 0..1, wygładzone
var _spike := 0.0  # chwilowy skok po fałszywym alarmie albo trafieniu
var _time := 0.0
var _last_states := {}  # potwór -> stan z poprzedniej klatki
var _stinger_ready_at := -INF


func _ready() -> void:
	add_to_group(&"tension_audio")
	for player in [$Ambient, $Heartbeat, $Breath]:
		player.finished.connect(player.play)
	$Ambient.play()
	$Heartbeat.play()
	$Breath.play()
	_apply(0.0)


## Fałszywy alarm albo trafienie: serce na chwilę podskakuje.
func spike(amount: float) -> void:
	_spike = clampf(_spike + amount, 0.0, 0.8)


func _process(delta: float) -> void:
	_time += delta
	var target := _local_focus()
	var raw := 0.0
	if target:
		for node in get_tree().get_nodes_in_group(&"monsters"):
			raw = maxf(raw, _danger_from(node as Monster, target.global_position))
			_check_stinger(node as Monster, target.global_position)
		var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
		var me := multiplayer.get_unique_id()
		if game_state and game_state.is_alive(me) and game_state.hp(me) < 40:
			raw = maxf(raw, 0.35)
	# Rozmycie: wolno falujący mnożnik, żeby nie dało się z serca odczytać dokładnej odległości.
	raw *= 0.8 + 0.25 * sin(_time * 0.7) + 0.1 * sin(_time * 2.3)
	raw = clampf(raw + _spike, 0.0, 1.0)
	_spike = maxf(_spike - delta * 0.15, 0.0)
	var rate := RISE_PER_SECOND if raw > threat else FALL_PER_SECOND
	threat = move_toward(threat, raw, rate * delta)
	_apply(threat)


## Stan potwora jest replikowany, więc to działa u każdego gracza bez dodatkowego RPC.
func _check_stinger(monster: Monster, position: Vector3) -> void:
	var previous: int = _last_states.get(monster, monster.state)
	_last_states[monster] = monster.state
	if monster.state != Monster.State.HUNT or previous == Monster.State.HUNT or previous == Monster.State.ATTACK:
		return
	if _time < _stinger_ready_at or monster.global_position.distance_to(position) > STINGER_RADIUS:
		return
	_stinger_ready_at = _time + STINGER_COOLDOWN
	$Stinger.play()
	spike(0.3)


func _danger_from(monster: Monster, position: Vector3) -> float:
	if monster == null:
		return 0.0
	var distance := monster.global_position.distance_to(position)
	match monster.state:
		Monster.State.VENT, Monster.State.VENT_CLIMB:
			return 0.6 * (1.0 - clampf(distance / VENT_RADIUS, 0.0, 1.0))
		Monster.State.HUNT, Monster.State.ATTACK, Monster.State.CARRY:
			return minf(1.25 * (1.0 - clampf(distance / HUNT_RADIUS, 0.0, 1.0)), 1.0)
	return 0.8 * (1.0 - clampf(distance / DANGER_RADIUS, 0.0, 1.0))


func _local_focus() -> Node3D:
	var director := get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	return director.target if director and is_instance_valid(director.target) else null


func _apply(value: float) -> void:
	$Ambient.volume_db = lerpf(-14.0, -40.0, value)
	$Heartbeat.volume_db = lerpf(-50.0, -2.0, clampf(value * 1.3, 0.0, 1.0))
	$Heartbeat.pitch_scale = lerpf(0.85, 1.9, value)  # szybsze tętno
	$Breath.volume_db = lerpf(-50.0, -6.0, clampf((value - 0.35) * 2.0, 0.0, 1.0))
