class_name GameState
extends Node
## Stan gry, którego jedynym właścicielem jest host. Tylko host zmienia dane
## (damage, revive...) i po każdej zmianie rozsyła pełną kopię do klientów przez RPC.
## Klienci tylko czytają, reagują na sygnały i mogą PROSIĆ hosta o akcje (request_*).
##
## Pełna kopia zamiast różnic, bo stan jest mały, a tak nowy gracz od razu dostaje całość.

signal changed
signal player_hit(peer_id: int, amount: int)
## Tylko u hosta.
signal player_downed(peer_id: int)
signal player_died(peer_id: int)

## OK = sprawny; DOWNED = powalony, czeka na pomoc albo się wykrwawia; DEAD = koniec.
enum Life { OK, DOWNED, DEAD }

const MAX_HP := 100
## Szansa, że trafienie otworzy krwawienie, i ile HP na sekundę zabiera krwawienie.
const BLEED_CHANCE := 0.6
const BLEED_DAMAGE_PER_SECOND := 2
const BLEED_OUT_SECONDS := 30
const REVIVE_HP := 30
const START_BANDAGES := 2
## Jak blisko trzeba stać, żeby pomóc koledze (host to sprawdza).
const HELP_DISTANCE := 2.0

## peer_id -> {"hp": int, "life": Life, "bleeding": bool, "bleed_out": int, "bandages": int}
var players := {}

var _tick := 0.0


func _ready() -> void:
	add_to_group(&"game_state")


func life(peer_id: int) -> Life:
	return players.get(peer_id, {}).get("life", Life.DEAD)


## Sprawny: może chodzić i działać.
func is_up(peer_id: int) -> bool:
	return life(peer_id) == Life.OK


func is_downed(peer_id: int) -> bool:
	return life(peer_id) == Life.DOWNED


## Żywy = sprawny albo powalony (potwór może go jeszcze dobić).
func is_alive(peer_id: int) -> bool:
	return life(peer_id) != Life.DEAD


func hp(peer_id: int) -> int:
	return players.get(peer_id, {}).get("hp", 0)


func is_bleeding(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("bleeding", false)


func bleed_out_left(peer_id: int) -> int:
	return players.get(peer_id, {}).get("bleed_out", 0)


func bandages(peer_id: int) -> int:
	return players.get(peer_id, {}).get("bandages", 0)


# --- Tylko host ---------------------------------------------------------------

## Raz na sekundę: krwawienie i odliczanie wykrwawienia. Jeden broadcast na sekundę.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick -= 1.0
	var dirty := false
	for peer_id in players.keys():
		var entry: Dictionary = players[peer_id]
		if entry.life == Life.OK and entry.bleeding:
			_lose_hp(peer_id, BLEED_DAMAGE_PER_SECOND)
		elif entry.life == Life.DOWNED:
			entry.bleed_out -= 1
			dirty = true
			if entry.bleed_out <= 0:
				_kill(peer_id)
	if dirty:
		_broadcast()


func add_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players[peer_id] = _fresh_entry()
	_broadcast()


func remove_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players.erase(peer_id)
	_broadcast()


## Sprawnego rani (i może otworzyć krwawienie), powalonego dobija.
func damage(peer_id: int, amount: int) -> void:
	assert(multiplayer.is_server())
	match life(peer_id):
		Life.OK:
			if randf() < BLEED_CHANCE:
				players[peer_id].bleeding = true
			_notify_hit.rpc(peer_id, amount)
			_lose_hp(peer_id, amount)
		Life.DOWNED:
			_notify_hit.rpc(peer_id, amount)
			_kill(peer_id)


## Pełne przywrócenie (np. nowa runda).
func reset_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if players.has(peer_id):
		players[peer_id] = _fresh_entry()
		_broadcast()


func _lose_hp(peer_id: int, amount: int) -> void:
	var entry: Dictionary = players[peer_id]
	entry.hp = maxi(entry.hp - amount, 0)
	if entry.hp == 0:
		entry.life = Life.DOWNED
		entry.bleeding = false
		entry.bleed_out = BLEED_OUT_SECONDS
		player_downed.emit(peer_id)
	_broadcast()


func _kill(peer_id: int) -> void:
	var entry: Dictionary = players[peer_id]
	entry.life = Life.DEAD
	entry.hp = 0
	entry.bleed_out = 0
	_broadcast()
	player_died.emit(peer_id)


func _fresh_entry() -> Dictionary:
	return {"hp": MAX_HP, "life": Life.OK, "bleeding": false, "bleed_out": 0, "bandages": START_BANDAGES}


func _broadcast() -> void:
	_apply_state.rpc(players)


## Kto wywołał RPC. Lokalne wywołanie u hosta daje 0, więc zamieniamy je na 1 (host).
func _caller() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender


func _close_enough(helper_id: int, target_id: int) -> bool:
	var helper := _player_node(helper_id)
	var target := _player_node(target_id)
	return helper != null and target != null \
		and helper.global_position.distance_to(target.global_position) <= HELP_DISTANCE + 0.5


func _player_node(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"players"):
		if node.get_multiplayer_authority() == peer_id:
			return node
	return null


# --- Żądania od klientów (wykonywane u hosta) ----------------------------------

## "any_peer": każdy klient może poprosić. Host sprawdza, czy prośba ma sens.
@rpc("any_peer", "call_local", "reliable")
func request_revive(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var helper_id := _caller()
	if not is_up(helper_id) or not is_downed(target_id) or not _close_enough(helper_id, target_id):
		return
	var entry: Dictionary = players[target_id]
	entry.life = Life.OK
	entry.hp = REVIVE_HP
	entry.bleed_out = 0
	_broadcast()


## Opatrzenie siebie albo krwawiącego kolegi. Zużywa bandaż pomagającego.
@rpc("any_peer", "call_local", "reliable")
func request_bandage(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var helper_id := _caller()
	if not is_up(helper_id) or bandages(helper_id) <= 0 or not is_up(target_id) or not is_bleeding(target_id):
		return
	if helper_id != target_id and not _close_enough(helper_id, target_id):
		return
	players[helper_id].bandages -= 1
	players[target_id].bleeding = false
	_broadcast()


# --- Wszyscy (wywoływane przez hosta) -----------------------------------------

# "authority": tylko właściciel węzła (host) może to wywołać; "call_local": u hosta też się wykona.
@rpc("authority", "call_local", "reliable")
func _apply_state(state: Dictionary) -> void:
	players = state
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _notify_hit(peer_id: int, amount: int) -> void:
	player_hit.emit(peer_id, amount)
