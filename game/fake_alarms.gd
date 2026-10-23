class_name FakeAlarms
extends Node
## Fałszywe alarmy (filar „niepewność”): dźwięki otoczenia, których gracz od razu nie
## odróżni od potwora. Losuje host i puszcza wszystkim w tym samym miejscu, żeby gracze
## mogli się kłócić, czy to było „coś”.
##
## Proporcje (strojenie, krok 40): co MIN..MAX s jedno zdarzenie w punkcie AmbientPoints
## pokoju w odległości DISTANCE od losowego żywego gracza. FAKE_STEPS_WEIGHT to udział
## najmocniejszego fałszu: kroków brzmiących jak potwór.

const MIN_INTERVAL := 12.0
const MAX_INTERVAL := 28.0
const DISTANCE := Vector2(6.0, 20.0)
const SOUNDS := {
	"creak": [preload("res://assets/sfx/creak.tres"), 3.0, -2.0],
	"thud": [preload("res://assets/sfx/monster_steps.tres"), 1.5, 2.0],
	"clang": [preload("res://assets/sfx/vent_bangs.tres"), 2.0, -4.0],
	"steps": [preload("res://assets/sfx/monster_steps.tres"), 1.0, 0.0],
}
## Wagi losowania [creak, thud, clang, steps].
var weights := {"creak": 4.0, "thud": 2.0, "clang": 2.0, "steps": 1.5}

var _timer := 0.0
var _active := false


func start() -> void:
	_active = true
	_timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)


func stop() -> void:
	_active = false


func _process(delta: float) -> void:
	if not _active or not multiplayer.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)
	var point := _pick_point()
	if point != Vector3.INF:
		_play.rpc(_pick_kind(), point)


func _pick_point() -> Vector3:
	var main := get_tree().get_first_node_in_group(&"main")
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	var alive := get_tree().get_nodes_in_group(&"players").filter(func(p: Node) -> bool:
		return game_state.is_alive(p.get_multiplayer_authority()))
	if alive.is_empty() or main == null:
		return Vector3.INF
	var listener: Node3D = alive[randi() % alive.size()]
	var candidates: Array[Vector3] = []
	for room in main.rooms:
		for marker in room.get_ambient_points():
			var distance: float = marker.global_position.distance_to(listener.global_position)
			if distance >= DISTANCE.x and distance <= DISTANCE.y:
				candidates.append(marker.global_position)
	return Vector3.INF if candidates.is_empty() else candidates[randi() % candidates.size()]


func _pick_kind() -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	for kind in weights:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return "creak"


@rpc("authority", "call_local", "reliable")
func _play(kind: String, position: Vector3) -> void:
	var config: Array = SOUNDS[kind]
	var repeats := 4 if kind == "steps" else 1
	for i in repeats:
		var player := AudioStreamPlayer3D.new()
		player.stream = config[0]
		player.pitch_scale = 0.6 if kind in ["steps", "thud"] else 1.0
		player.volume_db = config[2]
		player.unit_size = config[1] * 3.0
		player.max_distance = 30.0
		add_child(player)
		player.global_position = position
		player.finished.connect(player.queue_free)
		get_tree().create_timer(i * 0.55).timeout.connect(player.play)
	# Serce podskakuje, jeśli alarm był blisko.
	var tension := get_tree().get_first_node_in_group(&"tension_audio") as TensionAudio
	var focus := get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	if tension and focus and is_instance_valid(focus.target) and focus.target.global_position.distance_to(position) < 15.0:
		tension.spike(0.35 if kind == "steps" else 0.2)
