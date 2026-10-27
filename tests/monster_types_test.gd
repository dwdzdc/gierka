extends SceneTree
# Typy potworów (profile) i reżyser:
#  -- --case=butcher   ślepy rzeźnik: nie widzi gracza przed sobą, słyszy kroki, zabija od razu
#  -- --case=guard     strażnik: goni gracza poza rewir, a gdy go zgubi, wraca do gniazda
#  -- --case=watcher   obserwator: nie rusza się, krzyczy (hałas w miejscu gracza)
#  -- --case=searchlight  obserwator widzi tylko w stożku reflektora (47g.7), za to także po ciemku
#  -- --case=director  etapy: nowe potwory i ostrzejsze zmysły; wskaźnik zagrożenia odsyła łowcę
#  -- --case=nest      strażnik przenosi gniazdo do innego pokoju

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var case := "butcher"
var m
var p
var log: Array[String] = []
var screams := 0
var max_from_home := 0.0

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
		if case == "nest":
			main.get_node("Players/1").global_position = Vector3(-5, 0.05, 1.5)
			m = director.spawn("guard", main.rooms[2])
			director.rooms = main.rooms
			director.monsters_parent = main.get_node("Monsters")
			director._active = true
			director._relocate[m] = 1.0
			log.append("gniazdo przed: %s" % m.home.snapped(Vector3.ONE))
			return false
		m = director.spawn("watcher" if case == "searchlight" else case, main.rooms[2])  # magazyn
		m.global_position = Vector3(37.8, 0.05, 0)
		m.home = m.global_position
		m.rotation.y = PI / 2  # patrzy na -X
		m.state_changed.connect(func(s): _say("%s -> %s" % [m.profile.display_name, m.State.keys()[s]]))
		root.get_node("NoiseBus").noise_made.connect(func(pos, r, src): if src == m: screams += 1)
		match case:
			"butcher":
				p.global_position = Vector3(34.3, 0.05, 0)  # 3.5 m przed nim, stoi cicho
			"guard":
				p.global_position = Vector3(31.8, 0.05, 0)
			"watcher":
				p.global_position = Vector3(30.8, 0.05, 0)
	if f == 2:
		return false
	match case:
		"searchlight":
			if f == 10:
				m.set_physics_process(false)
				main.rooms[2].dark = true
				p.flashlight.visible = false
				p.global_position = Vector3(25.8, 0.05, 0)  # 12 m na wprost, po ciemku
			if f == 20:
				_say("%s  reflektor: %s" % ["OK " if m.has_node("Searchlight") else "ZLE", m.has_node("Searchlight")])
				_say("%s  12 m na wprost po ciemku: widzi=%s" % ["OK " if m.can_see(p) else "ZLE", m.can_see(p)])
				p.global_position = Vector3(34.8, 0.05, 3.5)  # 4,6 m, 49° w bok (poza stożkiem 70°)
			if f == 30:
				_say("%s  z boku poza stożkiem: widzi=%s" % ["OK " if not m.can_see(p) else "ZLE", m.can_see(p)])
				print("\n".join(log))
				return true
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
			# Gracz ucieka przed strażnikiem do korytarza, zawsze kilka metrów przed nim
			# (widoczny), potem znika w hali poza zasięgiem wzroku.
			if f > 30 and f < 60 * 9 and f % 30 == 0:
				var target: Vector3 = m.global_position + Vector3(-5, 0, 0)
				p.global_position = Vector3(maxf(target.x, 4.0), 0.05, 0)
			if f % 60 == 0 and OS.get_cmdline_user_args().has("--verbose-guard"):
				_say("m %s p %s %s seen=%s" % [m.global_position.snapped(Vector3.ONE*0.1), p.global_position.snapped(Vector3.ONE*0.1), m.State.keys()[m.state], m.seen_player != null])
			if f == 60 * 9:
				p.global_position = Vector3(-6, 0.05, 6)
			if m:
				max_from_home = maxf(max_from_home, m.global_position.distance_to(m.home))
			if f == 60 * 45:
				_say("strażnik najdalej od gniazda: %.1f m (dawniej smycz 16 m), teraz od gniazda: %.1f m, stan %s" % [max_from_home, m.global_position.distance_to(m.home), m.State.keys()[m.state]])
				var ok: bool = max_from_home > 18.0 and m.global_position.distance_to(m.home) < m.profile.territory_radius + 1.0
				_say("%s goni poza rewir i wraca" % ("OK " if ok else "ZLE"))
				print("\n".join(log))
				return true
		"watcher":
			if f == 60 * 8:
				_say("obserwator przesunął się o %.2f m, krzyków: %d, stan gracza: %s" % [m.global_position.distance_to(Vector3(37.8, 0.05, 0)), screams, gs.Life.keys()[gs.life(1)]])
				print("\n".join(log))
				return true
		"nest":
			if f == 60 * 30:
				log.append("gniazdo po: %s, strażnik w %s (odległość od nowego gniazda %.1f)" % [m.home.snapped(Vector3.ONE), m.global_position.snapped(Vector3.ONE), m.global_position.distance_to(m.home)])
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
