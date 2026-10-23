extends SceneTree
# Scenariusze maszyny stanów potwora. Wypisuje przejścia stanów z czasem.
#   -- --scenario=attack   gracz stoi przed potworem w ciemności
#   -- --scenario=noise    hałas za plecami potwora, gracz daleko
#   -- --scenario=escape   potwór zaczyna gonić, gracz teleportuje się za ścianę

var main: Node3D
var m
var p
var frames := 0
var scenario := "attack"
var log: Array[String] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		p = main.get_node("Players/1")
		m.global_position = Vector3(26, 0.05, 0)
		m.rotation.y = PI / 2  # patrzy na -X
		m.state_changed.connect(func(s): log.append("t=%.1f %s" % [frames / 60.0, m.State.keys()[s]]))
		match scenario:
			"attack":
				p.global_position = Vector3(22, 0.05, 0)
			"noise":
				p.global_position = Vector3(-4, 0.05, -3)
				m.rotation.y = -PI / 2  # plecami do hałasu
				root.get_node("NoiseBus").emit_noise.call_deferred(Vector3(21, 0, 0.5), 10.0, null)
			"escape":
				p.global_position = Vector3(22, 0.05, 0)
	if scenario == "escape" and frames == 40:
		p.global_position = Vector3(-4, 0.05, -3)  # zniknął z pola widzenia
	if frames == 60 * 20:
		print("[%s] %s" % [scenario, ", ".join(log)])
		return true
	return false
