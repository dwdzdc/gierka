extends SceneTree
# Typy potworów (profile) i reżyser:
#  -- --case=butcher   ślepy rzeźnik: nie widzi gracza przed sobą, słyszy kroki, zabija od razu
#  -- --case=guard     strażnik: goni, ale za smyczą wraca do rewiru
#  -- --case=watcher   obserwator: nie rusza się, krzyczy (hałas w miejscu gracza)
#  -- --case=director  etapy: nowe potwory i ostrzejsze zmysły; wskaźnik zagrożenia odsyła łowcę

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var case := "butcher"
var m
var p
var log: Array[String] = []
var screams := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case = a.trim_prefix("--case=")
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
		p = main.get_node("Players/1")
		var director = main.get_node("MonsterDirector")
		for old in main.get_node("Monsters").get_children():
			old.free()
		if case == "director":
			director.stage_base_seconds = 4.0
			director.stage_seconds_per_room = 0.0
			director.start_round(main.rooms, main.get_node("Monsters"))
			m = main.get_node("Monsters").get_child(0)
			return false
		m = director.spawn(case, main.rooms[2])  # magazyn
		m.global_position = Vector3(37.8, 0.05, 0)
		m.home = m.global_position
		m.rotation.y = PI / 2  # patrzy na -X
		m.state_changed.connect(func(s): _say("%s -> %s" % [m.profile.display_name, m.State.keys()[s]]))
		root.get_node("NoiseBus").noise_made.connect(func(pos, r, src): if src == m: screams += 1)
		match case:
			"butcher":
				p.global_position = Vector3(34.3, 0.05, 0)  # 3.5 m przed nim, stoi cicho
			"guard":
				p.global_position = Vector3(33.8, 0.05, 0)
			"watcher":
				p.global_position = Vector3(30.8, 0.05, 0)
	if f == 2:
		return false
	match case:
		"butcher":
			if f == 120:
				_say("po 2 s ciszy: stan %s (ślepy, gracz stoi przed nim)" % m.State.keys()[m.state])
				Input.action_press("move_forward")  # kroki = hałas
			if f == 125:
				p.rotation.y = -PI / 2  # idzie w stronę potwora
			if f == 600:
				Input.action_release("move_forward")
				_say("koniec: gracz %s" % gs.Life.keys()[gs.life(1)])
				print("\n".join(log))
				return true
		"guard":
			if f == 30:
				p.global_position = Vector3(10, 0.05, 0)  # ucieka daleko, do korytarza
			if f == 60 * 14:
				_say("strażnik odległość od gniazda: %.1f (smycz %.0f)" % [m.global_position.distance_to(m.home), m.profile.leash])
				print("\n".join(log))
				return true
		"watcher":
			if f == 60 * 8:
				_say("obserwator przesunął się o %.2f m, krzyków: %d, stan gracza: %s" % [m.global_position.distance_to(Vector3(37.8, 0.05, 0)), screams, gs.Life.keys()[gs.life(1)]])
				print("\n".join(log))
				return true
		"director":
			if f % 120 == 0:
				var dir = main.get_node("MonsterDirector")
				var names = dir.monsters().map(func(x): return "%s(x%.1f)" % [x.profile.display_name, x.sense_boost])
				_say("etap %d: %s" % [dir.stage, names])
			if f == 60 * 18:
				print("\n".join(log))
				return true
	return false
