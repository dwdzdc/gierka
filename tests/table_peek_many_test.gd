extends SceneTree
# Kilku graczy pod jednym stołem (64): potwór zagląda raz i odkrywa wszystkich, nie tylko
# pierwszego. Atakuje najbliższego, ale drugiego też już widzi.
#   godot --headless --path . -s tests/table_peek_many_test.gd

const Maps = preload("res://tests/test_maps.gd")
const UNDER := Vector3(1.5, 0.05, -1.0)
var main: Node3D
var p1
var p2
var m
var f := 0
var ok := true


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
		p2.set_physics_process(false)
		m = main.get_node("Monsters").get_child(0)
		m.set_physics_process(false)
		Input.action_press("crouch")
	if f == 20:
		p1.global_position = UNDER + Vector3(-0.6, 0, 0)
		p2.global_position = UNDER + Vector3(0.6, 0, 0)
		p2.crouching = true
		m.global_position = Vector3(1.5, 0.05, 3.0)
		m.look_at(Vector3(1.5, 0.05, 0), Vector3.UP)
	if f == 24:
		_check(p1.under_cover() and p2.under_cover(), "obaj gracze pod blatem")
		_check(not m.can_see(p1) and not m.can_see(p2), "przed zajrzeniem potwór nie widzi żadnego")
		m.set_physics_process(true)
		m.check_under(UNDER)
	if f == 24 + 60 * 8:
		_check(m._found_under.has(p1) and m._found_under.has(p2), "zajrzenie odkryło obu (%d)" % m._found_under.size())
		_check(m.can_see(p1) and m.can_see(p2), "potwór widzi obu")
		Input.action_release("crouch")
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
