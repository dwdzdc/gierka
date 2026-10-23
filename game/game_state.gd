class_name GameState
extends Node
## Stan gry, którego jedynym właścicielem jest host. Tylko host zmienia dane
## (damage, revive...) i po każdej zmianie rozsyła pełną kopię do klientów przez RPC.
## Klienci tylko czytają i reagują na sygnały.
##
## Pełna kopia zamiast różnic, bo stan jest mały, a tak nowy gracz od razu dostaje całość.

signal changed
signal player_hit(peer_id: int, amount: int)
## Tylko u hosta.
signal player_died(peer_id: int)

const MAX_HP := 100
## Szansa, że trafienie otworzy krwawienie, i ile HP na sekundę zabiera krwawienie.
const BLEED_CHANCE := 0.6
const BLEED_DAMAGE_PER_SECOND := 2

## peer_id -> {"hp": int, "alive": bool, "bleeding": bool}
var players := {}

var _bleed_tick := 0.0


func _ready() -> void:
	add_to_group(&"game_state")


func is_alive(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("alive", false)


func hp(peer_id: int) -> int:
	return players.get(peer_id, {}).get("hp", 0)


func is_bleeding(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("bleeding", false)


## Krwawienie zabiera HP raz na sekundę. Jeden broadcast na sekundę zamiast co klatkę.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_bleed_tick += delta
	if _bleed_tick < 1.0:
		return
	_bleed_tick -= 1.0
	for peer_id in players:
		if is_alive(peer_id) and is_bleeding(peer_id):
			_lose_hp(peer_id, BLEED_DAMAGE_PER_SECOND)


# --- Tylko host ---------------------------------------------------------------

func add_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players[peer_id] = _fresh_entry()
	_broadcast()


func remove_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players.erase(peer_id)
	_broadcast()


func damage(peer_id: int, amount: int) -> void:
	assert(multiplayer.is_server())
	if not is_alive(peer_id):
		return
	if randf() < BLEED_CHANCE:
		players[peer_id].bleeding = true
	_notify_hit.rpc(peer_id, amount)
	_lose_hp(peer_id, amount)


func _lose_hp(peer_id: int, amount: int) -> void:
	var entry: Dictionary = players[peer_id]
	entry.hp = maxi(entry.hp - amount, 0)
	entry.alive = entry.hp > 0
	if not entry.alive:
		entry.bleeding = false
	_broadcast()
	if not entry.alive:
		player_died.emit(peer_id)


func revive(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if players.has(peer_id):
		players[peer_id] = _fresh_entry()
		_broadcast()


func _fresh_entry() -> Dictionary:
	return {"hp": MAX_HP, "alive": true, "bleeding": false}


func _broadcast() -> void:
	_apply_state.rpc(players)


# --- Wszyscy (wywoływane przez hosta) -----------------------------------------

# "authority": tylko właściciel węzła (host) może to wywołać; "call_local": u hosta też się wykona.
@rpc("authority", "call_local", "reliable")
func _apply_state(state: Dictionary) -> void:
	players = state
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _notify_hit(peer_id: int, amount: int) -> void:
	player_hit.emit(peer_id, amount)
