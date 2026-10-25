extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Scenariusze maszyny stanów potwora. Wypisuje przejścia stanów z czasem.
#   -- --scenario=attack   gracz stoi przed potworem w ciemności
#   -- --scenario=noise    hałas za plecami potwora, gracz daleko
#   -- --scenario=escape   potwór zaczyna gonić, gracz teleportuje się za ścianę; potem 20–35 s
#                          przeszukuje okolicę (odległość od miejsca zgubienia co 5 s), na koniec patrol
#   -- --scenario=dodge    gracz odskakuje w czasie zamachu
#   -- --scenario=death    cios zabija (100 dmg), po 8 s respawn
#   -- --scenario=walk_away / run_away / sidestep   (47h) w czasie zamachu gracz idzie prosto
#                          w tył 2,2 m/s / biegnie 4,6 m/s / schodzi w bok 2,2 m/s; trafił?

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
		m.global_position = Vector3(37.8, 0.05, 0)
		m.rotation.y = PI / 2  # patrzy na -X
		m.state_changed.connect(func(s): log.append("t=%.1f %s" % [frames / 60.0, m.State.keys()[s]]))
		match scenario:
			"attack":
				p.global_position = Vector3(33.8, 0.05, 0)
			"noise":
				p.global_position = Vector3(-4, 0.05, -3)
				m.rotation.y = -PI / 2  # plecami do hałasu
				root.get_node("NoiseBus").emit_noise.call_deferred(Vector3(32.8, 0, 0.5), 10.0, null)
			"escape", "dodge", "walk_away", "run_away", "sidestep":
				p.global_position = Vector3(33.8, 0.05, 0)
			"death":
				p.global_position = Vector3(33.8, 0.05, 0)
				m.attack_damage = 100
	if scenario == "escape" and frames == 40:
		p.global_position = Vector3(-4, 0.05, -3)  # zniknął z pola widzenia
	if scenario == "dodge" and m != null and m.state == m.State.ATTACK and p.global_position.x > 30.0:
		p.global_position = Vector3(27.8, 0.05, 0)  # odskok o kilka metrów w czasie zamachu
	if scenario in ["walk_away", "run_away", "sidestep"] and m != null and m.state == m.State.ATTACK:
		var speed := 4.6 if scenario == "run_away" else 2.2
		var direction := Vector3(0, 0, 1) if scenario == "sidestep" else Vector3(-1, 0, 0)
		p.global_position += direction * speed / 60.0
	var gs = main.get_node("GameState")
	if frames == 2 and scenario in ["walk_away", "run_away", "sidestep"]:
		gs.player_hit.connect(func(_id, amount): log.append("TRAFIONY %d" % amount))
	if scenario == "escape" and frames % 300 == 0:
		log.append("t=%d od miejsca zgubienia %.1f m" % [frames / 60, m.global_position.distance_to(Vector3(33.8, 0, 0))])
	if scenario == "death" and frames % 60 == 0 and frames <= 60 * 12:
		log.append("t=%d hp=%d alive=%s pos=%s" % [frames / 60, gs.hp(1), gs.is_alive(1), p.global_position.snapped(Vector3.ONE)])
	if scenario in ["walk_away", "run_away", "sidestep"] and frames == 60 * 2:
		print("[%s] %s" % [scenario, ", ".join(log)])
		return true
	if frames == 60 * (45 if scenario == "escape" else 20):
		log.append("koniec hp=%d" % gs.hp(1))
		print("[%s] %s" % [scenario, ", ".join(log)])
		return true
	return false
