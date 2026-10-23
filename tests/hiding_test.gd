extends SceneTree
# Kryjówki:
#  -- --case=unseen   gracz chowa się w szafce, gdy potwór go nie widzi: potwór go nie znajduje
#  -- --case=seen     potwór widzi, jak gracz się chowa: otwiera szafkę i atakuje
#  -- --case=table    kucanie pod stołem: nie da się wstać, potwór nie wchodzi pod blat

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var case := "unseen"
var m
var p
var log: Array[String] = []

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
		m = main.get_node("Monsters").get_child(0)
		m.state_changed.connect(func(s): _say("potwór -> %s" % m.State.keys()[s]))
	if f < 20:
		return false
	var locker = main.rooms[0].get_node("HidingSpots/Locker1")
	match case:
		"unseen", "seen":
			if f == 20:
				p.global_transform = locker.front_transform()
				p.rotate_y(PI)  # przodem do szafki
				m.set_physics_process(case == "seen")
				m.global_position = locker.global_position + Vector3(0, 0, 6) if case == "seen" else Vector3(30, 0.05, 0)
				m.look_at(locker.global_position, Vector3.UP)
				Input.action_press("interact")
			if f == 60:
				Input.action_release("interact")
				_say("schowany=%s, kamera szafki aktywna=%s" % [gs.is_hidden(1), locker.peek_camera().current])
				m.set_physics_process(true)
			if f == 60 * 8:
				_say("koniec: schowany=%s stan=%s hp=%d" % [gs.is_hidden(1), gs.Life.keys()[gs.life(1)], gs.hp(1)])
				print("\n".join(log))
				return true
		"table":
			if f == 20:
				m.set_physics_process(false)
				p.global_position = Vector3(1.5, 0.05, 1.5)  # obok stołu w hali (środek blatu: 1.5, -1.0)
				p.rotation.y = 0  # przodem na -Z, pod stół
				Input.action_press("crouch")
				Input.action_press("move_forward")
			if f == 140:
				Input.action_release("move_forward")
				Input.action_release("crouch")
			if f == 160:
				_say("pod stołem? pos=%s, kuca=%s (nie da się wstać)" % [p.global_position.snapped(Vector3.ONE * 0.1), p.crouching])
				var map: RID = main.navigation.get_navigation_map()
				var cp: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(1.5, 0.3, -1.0))
				_say("NavMesh najbliżej środka stołu: %s (potwór nie wejdzie pod blat, jeśli to krawędź)" % cp.snapped(Vector3.ONE * 0.1))
				print("\n".join(log))
				return true
	return false
