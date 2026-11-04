extends SceneTree
# Potwór trzyma się gonionej ofiary (56): dwóch graczy w podobnej odległości, ich odległości
# na zmianę się przeplatają (kołysanie ±0,6 m); cel ma się nie przełączać tam i z powrotem.
# Potem gracz 2 staje wyraźnie bliżej (o >3 m): wtedy potwór ma zmienić cel.
#   godot --headless --path . -s tests/prey_switch_test.gd

const Maps = preload("res://tests/test_maps.gd")
const A := Vector3(-3.0, 0.05, -3.0)
const B := Vector3(3.0, 0.05, -3.0)
var main: Node3D
var m
var p1
var p2
var f := 0
var ok := true
var switches := 0
var last_prey = null


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)


func _check(cond: bool, what: String) -> void:
	ok = ok and cond
	print("%s  %s" % ["OK " if cond else "ZLE", what])


func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main._spawn_player(2)
		var gs = main.get_node("GameState")
		gs.invulnerable[1] = true
		gs.invulnerable[2] = true
		p1 = main.get_node("Players/1")
		p2 = main.get_node("Players/2")
		p2.set_physics_process(false)  # bez właściciela; pozycję ustawia test
		m = main.get_node("Monsters").get_child(0)
	if f == 4:
		m.global_position = Vector3(0, 0.05, 4.0)
		m.look_at(Vector3(0, 0.05, 0), Vector3.UP)
	if f >= 4 and f < 4 + 60 * 6:
		# Odległości graczy od potwora przeplatają się co ~0,5 s.
		var wobble := sin(f * 0.2) * 0.6
		p1.global_position = A + Vector3(0, 0, wobble)
		p2.global_position = B - Vector3(0, 0, wobble)
		if m.state in [m.State.HUNT, m.State.ATTACK, m.State.RECOVER]:
			if last_prey != null and m._prey != last_prey:
				switches += 1
			last_prey = m._prey
	if f == 4 + 60 * 6:
		_check(last_prey != null, "potwór goni któregoś z graczy")
		_check(switches <= 1, "cel nie skacze między graczami (zmian: %d)" % switches)
		# Drugi gracz wyraźnie bliżej: potwór ma przejść na niego.
		var far: Node3D = p1 if m._prey == p2 else p2
		var near: Node3D = p2 if far == p1 else p1
		far.global_position = m.global_position + (far.global_position - m.global_position).normalized() * 7.0
		near.global_position = m.global_position + Vector3(0, 0, -1.5).rotated(Vector3.UP, m.rotation.y)
		last_prey = near
	if f == 4 + 60 * 8:
		_check(m._prey == last_prey, "gracz bliżej o >3 m przejmuje uwagę potwora")
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
