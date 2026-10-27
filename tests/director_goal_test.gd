extends SceneTree
# Reżyser nie pozwala potworowi zabłądzić: daleki potwór szybko dostaje cel przy graczu,
# dochodzi tam i krąży w okolicy zamiast wracać na drugi koniec mapy.
const Maps = preload("res://tests/test_maps.gd")

var main: Node3D
var f := 0
var m
var p
var goal_frame := -1
var near_time := 0.0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		p = main.get_node("Players/1")
	if f == 40:
		p.global_position = Vector3(-5, 0.05, 0)
		m.global_position = Vector3(38, 0.05, 0)
		m._enter(m.State.PATROL)
		m.agent.target_position = Vector3(40, 0, 2)  # idzie dalej od gracza
		log.append("start: potwór %.0f m od gracza" % m.global_position.distance_to(p.global_position))
	if f > 40:
		p.global_position = Vector3(-5, 0.05, 0)
		if f == 40 + 210:
			log.append("t=3.5 s: stan %s, cel %s, szyb %s" % [m.State.keys()[m.state], m.agent.target_position.round(), m._vent_plan])
		var heading: Vector3 = m._vent_plan.exit if not m._vent_plan.is_empty() else m.agent.target_position
		if goal_frame < 0 and heading.distance_to(p.global_position) < 20.0:
			goal_frame = f
			log.append("cel przy graczu po %.1f s" % ((f - 40) / 60.0))
		if f > 40 + 60 * 20 and m.global_position.distance_to(p.global_position) < 20.0:
			near_time += d
	if f == 40 + 60 * 50:
		log.append("%s  cel przy graczu w ciągu 4 s" % ("OK " if goal_frame > 0 and goal_frame - 40 <= 240 else "ZLE"))
		log.append("%s  po dojściu trzyma się okolicy (%.0f z 30 s w 20 m)" % ["OK " if near_time > 20.0 else "ZLE", near_time])
		print("\n".join(log))
		return true
	return false
