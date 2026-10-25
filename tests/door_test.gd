extends SceneTree
# Drzwi (15l–15n) na stałej mapie: drzwi między korytarzem (x=16) a magazynem (x=34), w x=24.
#  - gracz otwiera/zamyka, zakluczone tylko z kluczem (klucz się zużywa)
#  - patrolujący potwór otwiera zamknięte drzwi powoli; zakluczonych nie rusza
#  - goniący potwór wyważa drzwi szybko
#  - wzrok przez kratkę: tylko z bliska i na wprost; hałas przez zamknięte drzwi słabszy

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var m
var p
var door
var f := 0
var phase := 0
var phase_start := 0
var results: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _check(ok: bool, text: String) -> void:
	results.append("%s %s" % ["OK " if ok else "ZLE", text])

func _next() -> void:
	phase += 1
	phase_start = f

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		gs = main.get_node("GameState")
		p = main.get_node("Players/1")
		var holder := Node3D.new()
		holder.name = "Doors"
		main.add_child(holder)
		door = load("res://props/door.gd").new()
		door.name = "Door00"
		holder.add_child(door)
		door.global_transform = main.map_connections[1].a.global_transform
		gs.init_doors({"Door00": door.State.CLOSED})
		main.director.stop()  # reżyser mógłby w trakcie testu przerzucić potwora szybem
		m = main.get_node("Monsters").get_child(0)
		m.set_physics_process(false)
		m.global_position = Vector3(40, 0.05, 6)
		_next()
		return false
	var t := f - phase_start
	match phase:
		1:  # gracz przy drzwiach od strony korytarza
			if t == 10:
				p.global_position = Vector3(22.8, 0.05, 0)
			if t == 20:
				gs.request_door("Door00", false)
			if t == 30:
				_check(door.state == door.State.OPEN, "gracz otwiera drzwi")
				gs.request_door("Door00", false)
			if t == 40:
				_check(door.state == door.State.CLOSED and not door.get_child(0).disabled, "gracz zamyka drzwi (kolizja wraca)")
				gs.doors["Door00"] = door.State.LOCKED
				gs._broadcast_doors()
				gs.request_door("Door00", false)
			if t == 50:
				_check(door.state == door.State.LOCKED, "bez klucza zakluczone zostają zakluczone")
				gs.add_key(1)
				gs.request_door("Door00", false)
			if t == 60:
				_check(door.state == door.State.OPEN and gs.keys(1) == 0, "klucz otwiera i się zużywa")
				gs.doors["Door00"] = door.State.CLOSED
				gs._broadcast_doors()
				_next()
		2:  # patrol: potwór w magazynie idzie do korytarza przez zamknięte drzwi
			if t == 1:
				p.global_position = Vector3(-5, 0.05, 4)  # daleko, w hali
				m.global_position = Vector3(27.5, 0.05, 0)
				m._enter(m.State.PATROL)
				m.director_goal = Vector3.INF
				m.set_physics_process(true)
				m.agent.target_position = Vector3(18, 0.05, 0)
			if t > 1 and door.state == door.State.OPEN and not has_meta("opened"):
				set_meta("opened", t)
			if t == 60 * 6:
				var at = get_meta("opened", -1)
				_check(door.state == door.State.OPEN and at > 60 * 2.5, "patrol otwiera powoli (po %.1f s), nie wyważa" % (at / 60.0))
				gs.doors["Door00"] = door.State.LOCKED
				gs._broadcast_doors()
				m.global_position = Vector3(27.5, 0.05, 0)
				m._enter(m.State.PATROL)
				m.agent.target_position = Vector3(18, 0.05, 0)
			if t == 60 * 11:
				_check(door.state == door.State.LOCKED and m.global_position.x > 24.0, "patrol nie rusza zakluczonych drzwi")
				gs.doors["Door00"] = door.State.CLOSED
				gs._broadcast_doors()
				_next()
		3:  # pościg: wyważa szybko
			if t == 1:
				m.global_position = Vector3(27.5, 0.05, 0)
				m.velocity = Vector3.ZERO
				m._door = null
				m._vent_plan = {}
				p.global_position = Vector3(20, 0.05, 0)
				m._prey = p
				m.last_seen_position = p.global_position
				m._enter(m.State.HUNT)
			if t == 1:
				root.get_node("NoiseBus").noise_made.connect(func(_pos, radius, source):
					if source == m and is_equal_approx(radius, m.DOOR_POUND_NOISE):
						set_meta("pounds", get_meta("pounds", 0) + 1))
			if t > 1 and door.state == door.State.BROKEN and not has_meta("broken"):
				set_meta("broken", t)
				set_meta("splinter", door._impact.playing and door._impact.stream == door.SPLINTER)
			if door._impact.playing and door._impact.stream == door.POUND:
				set_meta("pound_audible", true)
			if t == 60 * 3:
				var at = get_meta("broken", -1)
				_check(at > 0 and at < 60 * 2.8, "pościg wyważa szybko (po %.1f s)" % (at / 60.0))
				_check(get_meta("pounds", 0) >= 2, "przed wyłamaniem seria łomotów (%d)" % get_meta("pounds", 0))
				_check(get_meta("pound_audible", false) and get_meta("splinter", false), "łomot i trzask grają z odtwarzacza uderzeń")
				m.set_physics_process(false)
				gs.doors["Door00"] = door.State.CLOSED
				gs._broadcast_doors()
				_next()
		4:  # wzrok przez kratkę
			if t == 2:
				p.global_position = Vector3(23.3, 0.05, 0)  # tuż za drzwiami, od strony korytarza
				p.flashlight.visible = true
				m.global_position = Vector3(25.6, 0.05, 0)
				m.rotation.y = PI / 2  # patrzy na -X, na drzwi
			if t == 4:
				_check(m.can_see(p), "z bliska, na wprost: widzi przez kratkę")
				m.global_position = Vector3(30, 0.05, 0)
			if t == 6:
				_check(not m.can_see(p), "z 6 m: przez kratkę nie widzi")
				m.global_position = Vector3(25.6, 0.05, 1.5)
				m.rotation.y = 0.0  # bokiem do drzwi
			if t == 8:
				_check(not m.can_see(p), "z bliska, ale bokiem: nie widzi")
				_next()
		5:  # hałas przez zamknięte drzwi
			if t == 2:
				m.global_position = Vector3(30, 0.05, 0)
				m._heard_new = false
				m._on_noise(Vector3(20, 0.05, 0), 12.0, null)  # 10 m, przez drzwi: zasięg 6 m
				_check(not m._heard_new, "hałas 12 m z 10 m przez zamknięte drzwi: nie słyszy")
				gs.doors["Door00"] = door.State.OPEN
				gs._broadcast_doors()
			if t == 4:
				m._heard_new = false
				m._on_noise(Vector3(20, 0.05, 0), 12.0, null)
				_check(m._heard_new, "ten sam hałas przy otwartych drzwiach: słyszy")
				_next()
		6:  # zatrzaśnięcie za sobą (15t): przebiegł przez otwarte drzwi, drzwi za plecami
			if t == 2:
				m.global_position = Vector3(40, 0.05, 6)
				p.rotation.y = -PI / 2  # przodem na +X, w stronę magazynu
				p.global_position = Vector3(23.0, 0.05, 0)
			if t == 4:
				p.global_position = Vector3(25.5, 0.05, 0)
			if t == 6:
				Input.action_press("interact")
			if t == 8:
				Input.action_release("interact")
				_check(door.state == door.State.CLOSED, "E tuż po przebiegnięciu zatrzaskuje drzwi za plecami")
				gs.doors["Door00"] = door.State.OPEN
				gs._broadcast_doors()
				p.global_position = Vector3(23.0, 0.05, 0)
			if t == 10:
				p.global_position = Vector3(25.5, 0.05, 0)
			if t == 10 + 60 * 2:
				Input.action_press("interact")
			if t == 12 + 60 * 2:
				Input.action_release("interact")
				_check(door.state == door.State.OPEN, "po 2 s już nie (trzeba odwrócić się do drzwi)")
				print("\n".join(results))
				return true
	return false
