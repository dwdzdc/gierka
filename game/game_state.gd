class_name GameState
extends Node
## Stan gry, którego jedynym właścicielem jest host. Tylko host zmienia dane
## (damage, revive...) i po każdej zmianie rozsyła pełną kopię do klientów przez RPC.
## Klienci tylko czytają i reagują na sygnały.
##
## Pełna kopia zamiast różnic, bo stan jest mały, a tak nowy gracz od razu dostaje całość.

signal changed
signal player_hit(peer_id: int, amount: int)

const MAX_HP := 100

## peer_id -> {"hp": int, "alive": bool}
var players := {}


func _ready() -> void:
	add_to_group(&"game_state")


func is_alive(peer_id: int) -> bool:
	return players.get(peer_id, {}).get("alive", false)


func hp(peer_id: int) -> int:
	return players.get(peer_id, {}).get("hp", 0)


# --- Tylko host ---------------------------------------------------------------

func add_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players[peer_id] = {"hp": MAX_HP, "alive": true}
	_broadcast()


func remove_player(peer_id: int) -> void:
	assert(multiplayer.is_server())
	players.erase(peer_id)
	_broadcast()


func damage(peer_id: int, amount: int) -> void:
	assert(multiplayer.is_server())
	if not is_alive(peer_id):
		return
	var entry: Dictionary = players[peer_id]
	entry.hp = maxi(entry.hp - amount, 0)
	entry.alive = entry.hp > 0
	_broadcast()
	_notify_hit.rpc(peer_id, amount)


func revive(peer_id: int) -> void:
	assert(multiplayer.is_server())
	if players.has(peer_id):
		players[peer_id] = {"hp": MAX_HP, "alive": true}
		_broadcast()


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
