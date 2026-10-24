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
signal player_hid(peer_id: int, spot_path: String)
## Zmienił się stan drzwi (u każdego peera).
signal doors_changed
## Promień hałasu otwierania/zamykania drzwi przez gracza.
const DOOR_NOISE_RADIUS := 5.0
## Zatrzaśnięcie w biegu: głośniej, a gracz zdążył już odbiec od drzwi.
const DOOR_SLAM_NOISE_RADIUS := 9.0
const DOOR_SLAM_DISTANCE := 3.5
## Promień hałasu przy wchodzeniu do szafki (skrzypnięcie drzwi).
const HIDE_NOISE_RADIUS := 5.0

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
## Punktacja zero-sum: tyle wyniesionych monet idzie do wspólnej puli,
## reszta zostaje temu, kto je wyniósł. Twoja część puli dzieli się między ciebie
## i tych, którzy wyszli PO tobie: wcześniejsze wyjście nie korzysta z ryzyka reszty.
const SHARED_FRACTION := 0.5

## peer_id -> {"name", "hp", "life", "bleeding", "bleed_out", "bandages",
##             "coins" (niesione), "banked" (wyniesione w tej rundzie), "session" (suma sesji)}
var players := {}
## Nazwa węzła drzwi -> Door.State. Zmienia tylko host, rozsyła całość (jak `players`).
var doors := {}
## Gdzie jest wyjście z mapy (ustawia main po złożeniu mapy). Tylko host.
var exit_position := Vector3.INF
var round_over := false
var _extract_counter := 0  # kolejność wyjść w rundzie (1 = pierwszy)
## Menu testowe: gracze, którym nic nie robią potwory ani krwawienie (tylko host).
var invulnerable := {}

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


## Ścieżka kryjówki (HidingSpot), w której siedzi gracz; "" = nie chowa się.
func hiding_spot(peer_id: int) -> String:
	return players.get(peer_id, {}).get("hidden_in", "")


func is_hidden(peer_id: int) -> bool:
	return hiding_spot(peer_id) != ""


## Kto siedzi w danej kryjówce (0 = nikt).
func occupant(spot_path: String) -> int:
	for peer_id in players:
		if players[peer_id].get("hidden_in", "") == spot_path:
			return peer_id
	return 0


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


func keys(peer_id: int) -> int:
	return players.get(peer_id, {}).get("keys", 0)


func door_state(door_name: String) -> Door.State:
	return doors.get(door_name, Door.State.OPEN)


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
	_broadcast_doors()  # nowy gracz dostaje bieżący stan drzwi


func remove_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players.erase(peer_id)
	_broadcast()
	_check_round_end()


## Sprawnego rani (i może otworzyć krwawienie), powalonego dobija.
func damage(peer_id: int, amount: int) -> void:
	assert(multiplayer.is_server())
	if invulnerable.get(peer_id, false):
		return
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
	if invulnerable.get(peer_id, false):
		return
	if is_alive(peer_id):
		_notify_hit.rpc(peer_id, MAX_HP)
		_kill(peer_id)


## Porwanie: gracz jest niesiony przez potwora `monster_name` i traci `damage_per_second` HP.
func abduct(peer_id: int, monster_name: String, damage_per_second: int) -> void:
	assert(multiplayer.is_server())
	if not is_alive(peer_id) or invulnerable.get(peer_id, false):
		return
	var entry: Dictionary = players[peer_id]
	entry.life = Life.CARRIED
	entry.hidden_in = ""
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


func set_invulnerable(peer_id: int, value: bool) -> void:
	assert(multiplayer.is_server())
	invulnerable[peer_id] = value


## Menu testowe: pełne HP, bez krwawienia, bandaże na start, z powrotem na nogi.
func debug_heal(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if not players.has(peer_id) or life(peer_id) in [Life.DEAD, Life.EXTRACTED]:
		return
	var entry: Dictionary = players[peer_id]
	entry.hp = MAX_HP
	entry.bleeding = false
	entry.bleed_out = 0
	entry.bandages = maxi(entry.bandages, START_BANDAGES)
	entry.life = Life.OK
	entry.carried_by = ""
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
	_extract_counter = 0
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
	entry.hidden_in = ""
	_broadcast()
	var body := _player_node(peer_id)
	player_died.emit(peer_id)
	if dropped > 0 and body:
		coins_dropped.emit(peer_id, dropped, body.global_position)
	_check_round_end()


func _fresh_entry(keep: Dictionary) -> Dictionary:
	return {"name": keep.get("name", "?"), "session": keep.get("session", 0),
		"hp": MAX_HP, "life": Life.OK, "bleeding": false, "bleed_out": 0,
		"bandages": START_BANDAGES, "coins": 0, "banked": 0, "carried_by": "", "carry_dps": 0, "hidden_in": "", "extract_order": 0, "keys": 0}


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


## Zero-sum: każdy ocalały oddaje SHARED_FRACTION wyniesionych monet, a ta część dzieli się
## po równo między niego i ocalałych, którzy wyszli PO nim. Reszta zostaje temu, kto ją wyniósł.
## Zmarli dostają 0. Suma wyników = suma wyniesionych monet.
## Przykład: A wychodzi pierwszy ze 100, B później ze 100 -> A: 50 + 25 = 75, B: 50 + 25 + 50 = 125.
func compute_results() -> Array:
	var survivors := []
	for peer_id in players:
		if life(peer_id) == Life.EXTRACTED:
			survivors.append(peer_id)
	var shares := {}
	for peer_id in survivors:
		shares[peer_id] = players[peer_id].banked * (1.0 - SHARED_FRACTION)
	for giver in survivors:
		var order: int = players[giver].extract_order
		var receivers := survivors.filter(func(id: int) -> bool: return players[id].extract_order >= order)
		for receiver in receivers:
			shares[receiver] += players[giver].banked * SHARED_FRACTION / receivers.size()
	var scores := _round_preserving_total(shares, survivors)
	var results := []
	for peer_id in players:
		var entry: Dictionary = players[peer_id]
		var score := 0
		if peer_id in survivors:
			score = scores[peer_id]
		results.append({"peer_id": peer_id, "name": entry.name, "survived": peer_id in survivors,
			"banked": entry.banked, "score": score, "session": entry.session + score})
	return results


## Zaokrąglanie, które nie gubi ani nie dodaje monet: w dół, a brakujące jednostki
## dostają ci z największą częścią ułamkową (przy remisie: kto wcześniej na liście).
func _round_preserving_total(shares: Dictionary, ids: Array) -> Dictionary:
	var result := {}
	var total := 0.0
	var floored := 0
	for id in ids:
		total += shares[id]
		result[id] = floori(shares[id])
		floored += result[id]
	var by_fraction := ids.duplicate()
	by_fraction.sort_custom(func(a: int, b: int) -> bool:
		return shares[a] - floori(shares[a]) > shares[b] - floori(shares[b]))
	for i in roundi(total) - floored:
		result[by_fraction[i % by_fraction.size()]] += 1
	return result


func _broadcast() -> void:
	_apply_state.rpc(players)


func _broadcast_doors() -> void:
	_apply_doors.rpc(doors)


## Nowa mapa: stan wszystkich drzwi z planu generatora.
func init_doors(states: Dictionary) -> void:
	assert(multiplayer.is_server())
	doors = states
	_broadcast_doors()


## Gracz podniósł klucz.
func add_key(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if players.has(peer_id):
		players[peer_id].keys = keys(peer_id) + 1
		_broadcast()


## Potwór otworzył (`broken` = false) albo wyważył drzwi.
func monster_door(door_name: String, broken: bool) -> void:
	assert(multiplayer.is_server())
	if not doors.has(door_name):
		return
	doors[door_name] = Door.State.BROKEN if broken else Door.State.OPEN
	_broadcast_doors()


## Potwór szarpie za klamkę albo (`pound`) łomocze w drzwi: dźwięk u wszystkich.
func monster_rattle(door_name: String, pound := false) -> void:
	_door_rattle.rpc(door_name, pound)


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


## Potwór otwiera szafkę i wyciąga gracza.
func force_unhide(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if is_hidden(peer_id):
		players[peer_id].hidden_in = ""
		_broadcast()


@rpc("any_peer", "call_local", "reliable")
func request_hide(spot_path: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _caller()
	var spot := get_node_or_null(NodePath(spot_path)) as HidingSpot
	var body := _player_node(peer_id)
	if spot == null or body == null or not is_up(peer_id) or is_hidden(peer_id) or occupant(spot_path) != 0:
		return
	if not spot.can_use_from(body.global_position):
		return
	players[peer_id].hidden_in = spot_path
	_broadcast()
	NoiseBus.emit_noise(spot.global_position, HIDE_NOISE_RADIUS, body)
	player_hid.emit(peer_id, spot_path)


@rpc("any_peer", "call_local", "reliable")
func request_unhide() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _caller()
	if is_hidden(peer_id):
		players[peer_id].hidden_in = ""
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
	_extract_counter += 1
	entry.extract_order = _extract_counter
	entry.bleeding = false
	_broadcast()
	player_extracted.emit(peer_id)
	_check_round_end()


## Gracz otwiera/zamyka drzwi (E). Zakluczone otwiera kluczem (zużywa go).
@rpc("any_peer", "call_local", "reliable")
func request_door(door_name: String, slam: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := _caller()
	var body := _player_node(peer_id)
	var door := _door_node(door_name)
	var reach := DOOR_SLAM_DISTANCE if slam else Door.USE_DISTANCE + 0.5
	if body == null or door == null or not is_up(peer_id) or door.flat_distance(body.global_position) > reach:
		return
	if slam and door_state(door_name) != Door.State.OPEN:
		return  # zatrzaśnięcie tylko zamyka
	match door_state(door_name):
		Door.State.OPEN:
			doors[door_name] = Door.State.CLOSED
		Door.State.CLOSED:
			doors[door_name] = Door.State.OPEN
		Door.State.LOCKED:
			if keys(peer_id) <= 0:
				return
			players[peer_id].keys -= 1
			doors[door_name] = Door.State.OPEN
			_broadcast()
		_:
			return
	_broadcast_doors()
	NoiseBus.emit_noise(door.global_position, DOOR_SLAM_NOISE_RADIUS if slam else DOOR_NOISE_RADIUS, body)


func _door_node(door_name: String) -> Door:
	for node in get_tree().get_nodes_in_group(&"doors"):
		if node.name == door_name:
			return node
	return null


# --- Wszyscy (wywoływane przez hosta) -----------------------------------------

# "authority": tylko właściciel węzła (host) może to wywołać; "call_local": u hosta też się wykona.
@rpc("authority", "call_local", "reliable")
func _apply_state(state: Dictionary) -> void:
	players = state
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _apply_doors(state: Dictionary) -> void:
	doors = state
	doors_changed.emit()


@rpc("authority", "call_local", "reliable")
func _door_rattle(door_name: String, pound: bool) -> void:
	var door := _door_node(door_name)
	if door:
		door.rattle(pound)


@rpc("authority", "call_local", "reliable")
func _notify_hit(peer_id: int, amount: int) -> void:
	player_hit.emit(peer_id, amount)


@rpc("authority", "call_local", "reliable")
func _notify_pickup(peer_id: int, position: Vector3) -> void:
	coins_picked.emit(peer_id, position)


@rpc("authority", "call_local", "reliable")
func _announce_results(results: Array) -> void:
	round_finished.emit(results)
