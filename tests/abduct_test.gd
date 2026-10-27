extends SceneTree
# Porywacz: łapie gracza, niesie do gniazda, w gnieździe szybciej zabiera HP.
#  -- --rescue   kolega (peer 2, sterowany tym procesem jako host) odbija porwanego
#  -- --group    (47g.7) kolega stoi obok: porywacz tylko się skrada; po 8 s kolega odchodzi i dopiero
#                wtedy porwanie
# Bez flagi: porwany ginie w gnieździe.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var m
var log: Array[String] = []
var rescue := false
var group := false

func _initialize() -> void:
	rescue = "--rescue" in OS.get_cmdline_user_args()
	group = "--group" in OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _say(text: String) -> void:
	log.append("t=%.1f %s" % [f / 60.0, text])

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		gs = main.get_node("GameState")
		for old in main.get_node("Monsters").get_children():
			old.free()
		main._spawn_player(2)
		var director = main.get_node("MonsterDirector")
		m = director.spawn("abductor", main.rooms[2])
		m.home = main.rooms[2].global_position  # gniazdo w magazynie
		m.global_position = Vector3(20, 0.05, 0)  # w korytarzu
		m.rotation.y = -PI / 2
		m.state_changed.connect(func(s): _say("porywacz -> %s" % m.State.keys()[s]))
		# Ofiarą jest gracz 2 (sztuczny), gracz 1 (ten proces) będzie ratował.
		main.get_node("Players/2").global_position = Vector3(22.5, 0.05, 0)
		main.get_node("Players/1").global_position = Vector3(12, 0.05, 0)
		main.get_node("Players/1").flashlight.visible = false
		if group:
			main.get_node("Players/1").global_position = Vector3(23.5, 0.05, 1.0)
	if group and f == 60 * 8:
		_say("kolega odchodzi; porwany do tej pory: %s, odległość porywacza %.1f m" % [gs.Life.keys()[gs.life(2)], m.global_position.distance_to(main.get_node("Players/2").global_position)])
		main.get_node("Players/1").global_position = Vector3(0, 0.05, 0)
	if f > 2 and f % 60 == 0:
		_say("gracz 2: %s hp=%d, odległość potwora od gniazda %.1f" % [gs.Life.keys()[gs.life(2)], gs.hp(2), m.global_position.distance_to(m.home) if is_instance_valid(m) else -1.0])
	if rescue and f == 60 * 6:
		# Gracz 1 dobiega do porwanego i trzyma E.
		main.get_node("Players/1").global_position = main.get_node("Players/2").global_position + Vector3(1.0, 0, 0)
		Input.action_press("interact")
	if f == 60 * 9:
		Input.action_release("interact")
	if f == 60 * 30:
		print("\n".join(log))
		return true
	return false
