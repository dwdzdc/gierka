extends SceneTree
# Potwór wciśnięty w ścianę albo w stół sam się z niej wydostaje (przeniesienie na wolne
# miejsce przy NavMeshu), zamiast stać tam do końca rundy.
const Maps = preload("res://tests/test_maps.gd")
const CASES := {"ściana": Vector3(5, 0.05, -5.9), "stół": Vector3(-4, 0.05, -3.4)}

var main: Node3D
var f := 0
var m
var start := 0
var names: Array = CASES.keys()
var current := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _place() -> void:
	m.global_position = CASES[names[current]]
	m._enter(m.State.PATROL)
	m.agent.target_position = Vector3(30, 0, 0)
	m.director_goal = Vector3.INF
	start = f
	log.append("%s: start %s, wolne miejsce: %s" % [names[current], m.global_position, m._fits_at(m.global_transform)])

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("MonsterDirector").stop()
		m = main.get_node("Monsters").get_child(0)
		main.get_node("Players/1").global_position = Vector3(30, 0.05, 0)
	if f == 40:
		_place()
	if f > 40 and f == start + 60 * 6:
		var free: bool = m._fits_at(m.global_transform)
		var inside := absf(m.global_position.z) < 5.6 and absf(m.global_position.x) < 30.0 and absf(m.global_position.y) < 0.5
		log.append("%s  %s: po 6 s %s, wolne miejsce: %s" % ["OK " if free and inside else "ZLE", names[current], m.global_position.round(), free])
		current += 1
		if current == names.size():
			print("\n".join(log))
			return true
		_place()
	return false
