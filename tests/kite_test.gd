extends SceneTree
# Anty-kiting i zryw (47g): gracz biega w kółko wokół fontanny w atrium z prędkością biegu
# (bez limitu wytrzymałości, żeby sprawdzić samego potwora). Mierzy, po ilu sekundach łowca
# dochodzi na zasięg ciosu: z anty-kitingiem i zrywem vs bez nich.
# Użycie: godot --headless --path . -s tests/kite_test.gd [-- --off]

const Maps = preload("res://tests/test_maps.gd")
const RADIUS := 3.6  # niecka fontanny ma 2,4 m
const SPEED := 4.6
const LIMIT := 30.0
var main: Node3D
var p
var m
var f := 0
var center := Vector3.ZERO
var angle := 0.0
var t := 0.0
var room_rot := Vector3.ZERO
var off := "--off" in OS.get_cmdline_user_args()
var no_burst := "--no-burst" in OS.get_cmdline_user_args()

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.KITE
	root.add_child.call_deferred(main)

func _physics_process(d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		p = main.get_node("Players/1")
		p.set_physics_process(false)
		for room in main.room_parent.get_children():
			if str(room.scene_file_path).ends_with("atrium.tscn"):
				center = room.to_global(Vector3(0, 0, 2))
				room_rot = room.global_rotation_degrees
		center.y = 0.05
		print("fontanna: ", center, " obrót pokoju: ", room_rot, " argumenty: ", OS.get_cmdline_user_args())
		m = main.get_node("Monsters").get_child(0)
		if off or no_burst:
			m.profile.burst_speed = 0.0
		if off:
			m.anti_kiting = false
	if f < 2:
		return false
	if f < 60:
		p.global_position = center + Vector3(RADIUS, 0, 0)
		m.global_position = center + Vector3(cos(-1.2), 0, sin(-1.2)) * RADIUS + Vector3(0, 0.05, 0)  # za plecami gracza
		return false
	if f == 60:
		m._prey = p
		m.last_seen_position = p.global_position
		m._enter(m.State.HUNT)
		m._start_burst()
	t += d
	angle += SPEED / RADIUS * d
	p.global_position = center + Vector3(cos(angle), 0, sin(angle)) * RADIUS
	p.look_at(p.global_position + Vector3(-sin(angle), 0, cos(angle)), Vector3.UP)
	m.seen_player = p
	m.last_seen_position = p.global_position
	var dist: float = m.global_position.distance_to(p.global_position)
	if false and f % 60 == 0:
		print("  t=%.1f dystans %.1f stan %s ślad %d przecięcie %s" % [t, dist, m.State.keys()[m.state], m._prey_trail.size(), m._intercept])
	if m.state == m.State.ATTACK or dist <= m.attack_range:
		print("%s: łowca dochodzi gracza po %.1f s" % [_label(), t])
		return true
	if t >= LIMIT:
		print("%s: łowca nie doszedł gracza przez %.0f s (dystans %.1f m)" % [_label(), LIMIT, dist])
		return true
	return false


func _label() -> String:
	return "bez anty-kitingu i zrywu" if off else ("sam anty-kiting" if no_burst else "anty-kiting + zryw")
