class_name BloodTrail
extends Node3D
## Ślady krwi. Host decyduje, gdzie spada kropla (krwawiący gracz w ruchu, powalony,
## trafienie) i rozsyła ją wszystkim. Każdy peer rysuje ją lokalnie jako Decal na podłodze,
## więc ślad widać z każdej kamery. Ślady trwają do końca rundy.
## Host trzyma też listę kropli z czasem: po niej tropi potwór.

const DROP_TEXTURE := preload("res://fx/blood_drop.tres")
const MAX_DECALS := 400
## Krwawiący gracz zostawia kroplę co tyle metrów (albo co STILL_INTERVAL s, gdy stoi).
const DROP_SPACING := 0.7
const STILL_INTERVAL := 1.5
const DOWNED_INTERVAL := 3.0

## Tylko u hosta: [{"position": Vector3, "time": float (s od startu)}]
var drops: Array[Dictionary] = []

var _last_drop := {}  # peer_id -> {"position": Vector3, "time": float}


func _ready() -> void:
	add_to_group(&"blood_trail")


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Tylko host ---------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	if game_state == null:
		return
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		var peer_id := player.get_multiplayer_authority()
		var bleeding := game_state.is_up(peer_id) and game_state.is_bleeding(peer_id)
		var downed := game_state.is_downed(peer_id)
		if not bleeding and not downed:
			_last_drop.erase(peer_id)
			continue
		var last: Dictionary = _last_drop.get(peer_id, {})
		var due := last.is_empty()
		if not due:
			var moved: float = player.global_position.distance_to(last.position)
			var waited: float = now() - last.time
			due = (bleeding and (moved >= DROP_SPACING or waited >= STILL_INTERVAL)) \
				or (downed and waited >= DOWNED_INTERVAL)
		if due:
			add_drop(player.global_position, 1.6 if downed else 1.0)
			_last_drop[peer_id] = {"position": player.global_position, "time": now()}


func add_drop(position: Vector3, size := 1.0) -> void:
	assert(multiplayer.is_server())
	drops.append({"position": position, "time": now()})
	_spawn_decal.rpc(position, size, randf() * TAU)


## Duży rozbryzg (egzekucja): kałuża na podłodze i plama na najbliższej ścianie.
func add_splatter(position: Vector3) -> void:
	assert(multiplayer.is_server())
	for i in 6:
		var offset := Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		add_drop(position + offset, 2.5)
	# Ściana: szukamy najbliższej w czterech kierunkach na wysokości tułowia.
	var space := get_world_3d().direct_space_state
	var chest := position + Vector3.UP * 1.2
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + direction * 3.0, 1))
		if not hit.is_empty():
			_spawn_wall_decal.rpc(hit.position, hit.normal)
			break


## Najświeższa kropla w promieniu `radius`, nowsza niż `newer_than`. Pusty słownik, gdy brak.
func freshest_near(position: Vector3, radius: float, newer_than := -INF) -> Dictionary:
	var best := {}
	for drop in drops:
		if drop.time > newer_than and drop.position.distance_to(position) <= radius:
			if best.is_empty() or drop.time > best.time:
				best = drop
	return best


## Nowy gracz dostaje wszystkie dotychczasowe ślady.
func send_all_to(peer_id: int) -> void:
	for drop in drops:
		_spawn_decal.rpc_id(peer_id, drop.position, 1.0, randf() * TAU)


func clear_all() -> void:
	assert(multiplayer.is_server())
	drops.clear()
	_last_drop.clear()
	_clear_decals.rpc()


# --- Wszyscy -------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _spawn_decal(position: Vector3, size: float, angle: float) -> void:
	var decal := Decal.new()
	decal.texture_albedo = DROP_TEXTURE
	# Lekka emisja: ślad ma być czytelny w ciemności, bo to mechanika, nie tylko dekoracja.
	decal.texture_emission = DROP_TEXTURE
	decal.emission_energy = 0.25
	decal.cull_mask = 1  # tylko warstwa 1 (świat). Postacie graczy są na warstwie 2.
	var radius := randf_range(0.35, 0.6) * size
	decal.size = Vector3(radius * randf_range(1.0, 1.6), 0.8, radius)
	decal.rotation.y = angle
	decal.position = position + Vector3.UP * 0.3
	add_child(decal)
	if get_child_count() > MAX_DECALS:
		get_child(0).queue_free()


## Plama na ścianie: decal rzutuje wzdłuż swojej osi -Y, więc obracamy go "w ścianę".
@rpc("authority", "call_local", "reliable")
func _spawn_wall_decal(position: Vector3, normal: Vector3) -> void:
	var decal := Decal.new()
	decal.texture_albedo = DROP_TEXTURE
	decal.texture_emission = DROP_TEXTURE
	decal.emission_energy = 0.25
	decal.cull_mask = 1
	decal.size = Vector3(2.2, 0.6, 1.6)
	var up := normal
	var side := up.cross(Vector3.UP).normalized()
	decal.transform = Transform3D(Basis(side, up, side.cross(up)), position + normal * 0.2)
	add_child(decal)


@rpc("authority", "call_local", "reliable")
func _clear_decals() -> void:
	for child in get_children():
		child.queue_free()
