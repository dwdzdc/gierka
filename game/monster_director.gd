class_name MonsterDirector
extends Node
## Reżyser potworów. Logikę wykonuje tylko host; węzeł istnieje u wszystkich, żeby móc
## ogłaszać zdarzenia (RPC).
##
## Zgrubna nawigacja, wzorowana na Alien: Isolation: reżyser zawsze wie, gdzie są gracze,
## ale nie mówi tego potworom. Łowcę tylko kieruje w okolicę graczy, a resztę potwór musi
## znaleźć zmysłami. Wskaźnik zagrożenia rośnie, gdy łowca długo jest blisko graczy;
## po progu reżyser odsyła go daleko (oddech dla graczy).
##
## Narastająca trudność zamiast limitu czasu: co etap nowy potwór z gniazdem daleko od graczy,
## a dotychczasowe mają ostrzejsze zmysły.

signal monster_spawned(monster: Monster)
## U wszystkich: ogłoszenie nowego potwora (np. ryk i napis w HUD).
signal new_threat(stage: int, name: String)

const MONSTER_SCENE := preload("res://monster/monster.tscn")
## Kolejność pojawiania się typów (pierwszy startuje z rundą).
const SPAWN_ORDER := ["hunter", "guard", "butcher", "abductor", "watcher"]
const GOAL_INTERVAL := 12.0  # co ile sekund reżyser wydaje polecenia łowcom
const NEAR_DISTANCE := 12.0  # "blisko graczy" dla wskaźnika zagrożenia
const MENACE_LIMIT := 30.0  # po przekroczeniu łowca jest odsyłany daleko
const MENACE_COOLDOWN := 35.0  # tyle sekund łowca nie jest przybliżany po odesłaniu
const SENSE_BOOST_PER_STAGE := 0.1

## Czas etapu: bazowo + na każdy pokój (większa mapa = więcej czasu na eksplorację).
var stage_base_seconds := 180.0
var stage_seconds_per_room := 15.0
var max_monsters := 4

var stage := 0
var rooms: Array[Room] = []
var monsters_parent: Node3D

var _stage_timer := 0.0
var _goal_timer := 0.0
var _menace := {}  # Monster -> float
var _cooldown := {}  # Monster -> sekundy do końca "oddechu"
var _active := false


func _ready() -> void:
	add_to_group(&"monster_director")


func stage_seconds() -> float:
	return stage_base_seconds + stage_seconds_per_room * rooms.size()


func monsters() -> Array[Monster]:
	var result: Array[Monster] = []
	if monsters_parent:
		for child in monsters_parent.get_children():
			if child is Monster and not child.is_queued_for_deletion():
				result.append(child)
	return result


## Host: nowa runda na świeżej mapie. Pierwszy potwór od razu, kolejne co etap.
func start_round(round_rooms: Array[Room], parent: Node3D) -> void:
	rooms = round_rooms
	monsters_parent = parent
	stage = 0
	_stage_timer = 0.0
	_goal_timer = GOAL_INTERVAL
	_menace.clear()
	_cooldown.clear()
	_active = true
	spawn(SPAWN_ORDER[0], _farthest_room_from_players())


func stop() -> void:
	_active = false


func spawn(profile_id: String, room: Room) -> Monster:
	var monster: Monster = MONSTER_SCENE.instantiate()
	monster.profile_id = profile_id
	monster.transform = Transform3D(Basis(), room.global_position + Vector3.UP * 0.05)
	monster.sense_boost = 1.0 + SENSE_BOOST_PER_STAGE * stage
	monsters_parent.add_child(monster, true)
	monster.home = monster.global_position
	monster_spawned.emit(monster)
	return monster


func _physics_process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
	_stage_timer += delta
	if _stage_timer >= stage_seconds():
		_stage_timer = 0.0
		_next_stage()
	for monster in monsters():
		_update_menace(monster, delta)
	_goal_timer -= delta
	if _goal_timer <= 0.0:
		_goal_timer = GOAL_INTERVAL
		for monster in monsters():
			_give_goal(monster)


## Nowy etap: wszystkie potwory ostrzejsze, a jeśli jest miejsce, dochodzi nowy.
func _next_stage() -> void:
	stage += 1
	for monster in monsters():
		monster.sense_boost = 1.0 + SENSE_BOOST_PER_STAGE * stage
	var name := ""
	if monsters().size() < max_monsters:
		var profile_id: String = SPAWN_ORDER[stage % SPAWN_ORDER.size()]
		var monster := spawn(profile_id, _farthest_room_from_players())
		name = monster.profile.display_name
	_announce.rpc(stage, name)


@rpc("authority", "call_local", "reliable")
func _announce(new_stage: int, name: String) -> void:
	new_threat.emit(new_stage, name)


## Wskaźnik zagrożenia łowcy: rośnie przy graczach (szybciej, gdy kogoś widzi), opada z dala.
func _update_menace(monster: Monster, delta: float) -> void:
	if monster.profile.behavior != MonsterProfile.Behavior.HUNTER:
		return
	if _cooldown.get(monster, 0.0) > 0.0:
		_cooldown[monster] -= delta
		return
	var near := _distance_to_nearest_player(monster.global_position) < NEAR_DISTANCE
	var rate := (2.0 if monster.seen_player else 1.0) if near else -0.5
	_menace[monster] = maxf(_menace.get(monster, 0.0) + rate * delta, 0.0)
	if _menace[monster] >= MENACE_LIMIT and monster.state != Monster.State.ATTACK:
		# Dość nacisku: odeślij daleko i daj graczom odetchnąć.
		_menace[monster] = 0.0
		_cooldown[monster] = MENACE_COOLDOWN
		monster._enter(Monster.State.PATROL)
		monster.director_goal = _farthest_room_from_players().global_position
		monster.agent.target_position = monster.director_goal


## Łowca w patrolu dostaje okolicę graczy (pokój obok, nie dokładną pozycję).
func _give_goal(monster: Monster) -> void:
	if monster.profile.behavior != MonsterProfile.Behavior.HUNTER:
		return
	if monster.state != Monster.State.PATROL or _cooldown.get(monster, 0.0) > 0.0:
		return
	var target := _random_alive_player()
	if target == null:
		return
	var room := _room_near(target.global_position, 8.0, 22.0)
	if room:
		monster.director_goal = room.global_position


func _farthest_room_from_players() -> Room:
	var best: Room = rooms[0]
	var best_distance := -1.0
	for room in rooms:
		if room.bounds.size.y >= 8.0:
			continue  # bez ramp i schodów (dwa piętra)
		var distance := _distance_to_nearest_player(room.global_position)
		if distance > best_distance:
			best_distance = distance
			best = room
	return best


## Losowy pokój w odległości [min, max] od punktu; brak = najbliższy powyżej min.
func _room_near(point: Vector3, min_distance: float, max_distance: float) -> Room:
	var candidates: Array[Room] = []
	for room in rooms:
		var distance := room.global_position.distance_to(point)
		if distance >= min_distance and distance <= max_distance:
			candidates.append(room)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _alive_players() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	for node in get_tree().get_nodes_in_group(&"players"):
		if game_state == null or game_state.is_alive(node.get_multiplayer_authority()):
			result.append(node)
	return result


func _random_alive_player() -> Node3D:
	var alive := _alive_players()
	return null if alive.is_empty() else alive[randi() % alive.size()]


func _distance_to_nearest_player(point: Vector3) -> float:
	var best := INF
	for player in _alive_players():
		best = minf(best, player.global_position.distance_to(point))
	return best
