class_name GameState
extends Node
## Stan gry, którego jedynym właścicielem jest host. Tylko host zmienia dane
## (damage, revive...) i po każdej zmianie rozsyła pełną kopię do klientów przez RPC.
## Klienci tylko czytają, reagują na sygnały i mogą PROSIĆ hosta o akcje (request_*).
##
## Pełna kopia zamiast różnic, bo stan jest mały, a tak nowy gracz od razu dostaje całość.

signal changed
signal player_hit(peer_id: int, amount: int)
signal coins_picked(peer_id: int, position: Vector3)
## Koniec rundy: wyniki dla wszystkich (u każdego peera).
signal round_finished(results: Array)
## Tylko u hosta.
signal player_downed(peer_id: int)
signal player_died(peer_id: int)
signal coins_dropped(peer_id: int, amount: int, position: Vector3)
signal player_extracted(peer_id: int)

## OK = sprawny; DOWNED = powalony; DEAD = koniec; EXTRACTED = wydostał się z mapy;
## CARRIED = porwany przez potwora (żywy, ale nic nie może zrobić).
## Nowe stany tylko na końcu: wartość leci przez sieć jako liczba.
enum Life { OK, DOWNED, DEAD, EXTRACTED, CARRIED }

const MAX_HP := 100
## Szansa, że trafienie otworzy krwawienie, i ile HP na sekundę zabiera krwawienie.
const BLEED_CHANCE := 0.6
const BLEED_DAMAGE_PER_SECOND := 2
const BLEED_OUT_SECONDS := 30
const REVIVE_HP := 30
const START_BANDAGES := 2
## Jak blisko trzeba stać, żeby pomóc koledze / wyjść (host to sprawdza).
const HELP_DISTANCE := 2.0
const EXIT_DISTANCE := 2.5
## Punktacja zero-sum: tyle wyniesionych monet idzie do wspólnej puli ocalałych,
## reszta zostaje temu, kto je wyniósł.
const SHARED_FRACTION := 0.5

## peer_id -> {"name", "hp", "life", "bleeding", "bleed_out", "bandages",
##             "coins" (niesione), "banked" (wyniesione w tej rundzie), "session" (suma sesji)}
var players := {}
## Gdzie jest wyjście z mapy (ustawia main po złożeniu mapy). Tylko host.
var exit_position := Vector3.INF
var round_over := false

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


## Na mapie i żywy = sprawny, powalony (potwór może go jeszcze dobić) albo porwany.
func is_alive(peer_id: int) -> bool:
	return life(peer_id) in [Life.OK, Life.DOWNED, Life.CARRIED]


func is_carried(peer_id: int) -> bool:
	return life(peer_id) == Life.CARRIED


## Nazwa węzła potwora, który niesie gracza ("" = nikt).
func carrier(peer_id: int) -> String:
	return players.get(peer_id, {}).get("carried_by", "")


func hp(peer_id: int) -> int:
	return players.get(peer_id, {}).get("hp", 0)


func is_bleeding(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("bleeding", false)


func bleed_out_left(peer_id: int) -> int:
	return players.get(peer_id, {}).get("bleed_out", 0)


func bandages(peer_id: int) -> int:
	return players.get(peer_id, {}).get("bandages", 0)


func coins(peer_id: int) -> int:
	return players.get(peer_id, {}).get("coins", 0)


func player_name(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", "?")


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
		elif entry.life == Life.CARRIED:
			entry.hp = maxi(entry.hp - entry.carry_dps, 0)
			dirty = true
			if entry.hp == 0:
				_kill(peer_id)  # porwany nie ma powalenia: zjedzony to zjedzony
	if dirty:
		_broadcast()


func add_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players[peer_id] = _fresh_entry({"name": "Gracz %d" % (players.size() + 1), "session": 0})
	_broadcast()


func remove_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players.erase(peer_id)
	_broadcast()
	_check_round_end()


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


## Natychmiastowa śmierć bez powalenia (np. egzekucja potwora).
func execute(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if is_alive(peer_id):
		_notify_hit.rpc(peer_id, MAX_HP)
		_kill(peer_id)


## Porwanie: gracz jest niesiony przez potwora `monster_name` i traci `damage_per_second` HP.
func abduct(peer_id: int, monster_name: String, damage_per_second: int) -> void:
	assert(multiplayer.is_server())
	if not is_alive(peer_id):
		return
	var entry: Dictionary = players[peer_id]
	entry.life = Life.CARRIED
	entry.carried_by = monster_name
	entry.carry_dps = damage_per_second
	entry.bleeding = true
	_notify_hit.rpc(peer_id, 0)
	_broadcast()


func set_carry_damage(peer_id: int, damage_per_second: int) -> void:
	if is_carried(peer_id):
		players[peer_id].carry_dps = damage_per_second
		_broadcast()


## Potwór puszcza porwanego (odbity przez kolegę albo potwór zginął/odszedł).
func release(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if not is_carried(peer_id):
		return
	var entry: Dictionary = players[peer_id]
	entry.life = Life.OK if entry.hp > 0 else Life.DEAD
	entry.carried_by = ""
	entry.carry_dps = 0
	_broadcast()


func add_coins(peer_id: int, amount: int, position: Vector3) -> void:
	assert(multiplayer.is_server())
	if not is_up(peer_id):
		return
	players[peer_id].coins += amount
	_broadcast()
	_notify_pickup.rpc(peer_id, position)


## Nowa runda: wszyscy wracają sprawni, bez monet; suma sesji zostaje.
func reset_for_round() -> void:
	assert(multiplayer.is_server())
	round_over = false
	for peer_id in players:
		players[peer_id] = _fresh_entry(players[peer_id])
	_broadcast()


## Pełne przywrócenie jednego gracza (np. reset po wybiciu wszystkich).
func reset_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if players.has(peer_id):
		players[peer_id] = _fresh_entry(players[peer_id])
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
	var dropped: int = entry.coins
	entry.life = Life.DEAD
	entry.hp = 0
	entry.bleed_out = 0
	entry.coins = 0
	entry.carried_by = ""
	entry.carry_dps = 0
	_broadcast()
	var body := _player_node(peer_id)
	player_died.emit(peer_id)
	if dropped > 0 and body:
		coins_dropped.emit(peer_id, dropped, body.global_position)
	_check_round_end()


func _fresh_entry(keep: Dictionary) -> Dictionary:
	return {"name": keep.get("name", "?"), "session": keep.get("session", 0),
		"hp": MAX_HP, "life": Life.OK, "bleeding": false, "bleed_out": 0,
		"bandages": START_BANDAGES, "coins": 0, "banked": 0, "carried_by": "", "carry_dps": 0}


## Runda się kończy, gdy nikt nie został na mapie (każdy zginął albo wyszedł).
func _check_round_end() -> void:
	if round_over or players.is_empty():
		return
	for peer_id in players:
		if is_alive(peer_id):
			return
	round_over = true
	var results := compute_results()
	for result in results:
		players[result.peer_id].session += result.score
	_broadcast()
	_announce_results.rpc(results)


## Zero-sum: część wyniesionych monet trafia do wspólnej puli i jest dzielona po równo
## między ocalałych; reszta zostaje temu, kto ją wyniósł. Zmarli dostają 0.
func compute_results() -> Array:
	var survivors := []
	var pool := 0.0
	for peer_id in players:
		if life(peer_id) == Life.EXTRACTED:
			survivors.append(peer_id)
			pool += players[peer_id].banked * SHARED_FRACTION
	var results := []
	for peer_id in players:
		var entry: Dictionary = players[peer_id]
		var score := 0
		if peer_id in survivors:
			score = roundi(entry.banked * (1.0 - SHARED_FRACTION) + pool / survivors.size())
		results.append({"peer_id": peer_id, "name": entry.name, "survived": peer_id in survivors,
			"banked": entry.banked, "score": score, "session": entry.session + score})
	return results


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


## Odbicie porwanego: kolega trzyma E przy porwanym. Potwór puszcza ofiarę i ucieka.
signal rescued(peer_id: int, monster_name: String)


@rpc("any_peer", "call_local", "reliable")
func request_rescue(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var helper_id := _caller()
	if not is_up(helper_id) or not is_carried(target_id) or not _close_enough(helper_id, target_id):
		return
	var monster_name := carrier(target_id)
	release(target_id)
	rescued.emit(target_id, monster_name)


## Wyjście z mapy przy wyjściu w hali: niesione monety stają się wyniesionymi.
@rpc("any_peer", "call_local", "reliable")
func request_extract() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _caller()
	var body := _player_node(peer_id)
	if not is_up(peer_id) or body == null or body.global_position.distance_to(exit_position) > EXIT_DISTANCE + 0.5:
		return
	var entry: Dictionary = players[peer_id]
	entry.banked += entry.coins
	entry.coins = 0
	entry.life = Life.EXTRACTED
	entry.bleeding = false
	_broadcast()
	player_extracted.emit(peer_id)
	_check_round_end()


# --- Wszyscy (wywoływane przez hosta) -----------------------------------------

# "authority": tylko właściciel węzła (host) może to wywołać; "call_local": u hosta też się wykona.
@rpc("authority", "call_local", "reliable")
func _apply_state(state: Dictionary) -> void:
	players = state
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _notify_hit(peer_id: int, amount: int) -> void:
	player_hit.emit(peer_id, amount)


@rpc("authority", "call_local", "reliable")
func _notify_pickup(peer_id: int, position: Vector3) -> void:
	coins_picked.emit(peer_id, position)


@rpc("authority", "call_local", "reliable")
func _announce_results(results: Array) -> void:
	round_finished.emit(results)
