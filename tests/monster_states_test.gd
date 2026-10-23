extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Scenariusze maszyny stanów potwora. Wypisuje przejścia stanów z czasem.
#   -- --scenario=attack   gracz stoi przed potworem w ciemności
#   -- --scenario=noise    hałas za plecami potwora, gracz daleko
#   -- --scenario=escape   potwór zaczyna gonić, gracz teleportuje się za ścianę
#   -- --scenario=dodge    gracz odskakuje w czasie zamachu
#   -- --scenario=death    cios zabija (100 dmg), po 8 s respawn

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
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		p = main.get_node("Players/1")
		m.global_position = Vector3(26.8, 0.05, 0)
		m.rotation.y = PI / 2  # patrzy na -X
		m.state_changed.connect(func(s): log.append("t=%.1f %s" % [frames / 60.0, m.State.keys()[s]]))
		match scenario:
			"attack":
				p.global_position = Vector3(22.8, 0.05, 0)
			"noise":
				p.global_position = Vector3(-4, 0.05, -3)
				m.rotation.y = -PI / 2  # plecami do hałasu
				root.get_node("NoiseBus").emit_noise.call_deferred(Vector3(21.8, 0, 0.5), 10.0, null)
			"escape", "dodge":
				p.global_position = Vector3(22.8, 0.05, 0)
			"death":
				p.global_position = Vector3(22.8, 0.05, 0)
				m.attack_damage = 100
	if scenario == "escape" and frames == 40:
		p.global_position = Vector3(-4, 0.05, -3)  # zniknął z pola widzenia
	if scenario == "dodge" and m != null and m.state == m.State.ATTACK and p.global_position.x > 15.8:
		p.global_position = Vector3(14.8, 0.05, 0)  # odskok o kilka metrów w czasie zamachu
	var gs = main.get_node("GameState")
	if scenario == "death" and frames % 60 == 0 and frames <= 60 * 12:
		log.append("t=%d hp=%d alive=%s pos=%s" % [frames / 60, gs.hp(1), gs.is_alive(1), p.global_position.snapped(Vector3.ONE)])
	if frames == 60 * 20:
		log.append("koniec hp=%d" % gs.hp(1))
		print("[%s] %s" % [scenario, ", ".join(log)])
		return true
	return false
