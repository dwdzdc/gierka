extends SceneTree
# Gracz pod stołem (55): potwór go nie widzi, dopóki nie zajrzy pod spód.
# Stół w hali mapy CLASSIC (środek blatu 1.5, -1.0). Trzy części w jednym przebiegu:
#  1) kucający przy stole na widoku: widać; ten sam pod blatem: nie widać, mimo że stoi 2,5 m przed nim
#  2) potwór goni gracza, a ten wczołguje się pod stół na jego oczach: potwór zagląda i znajduje
#  3) zaglądanie pod stół 3 m dalej niż gracz nic nie daje (potwór wraca do przeszukiwania)
#   godot --headless --path . -s tests/table_peek_test.gd

const Maps = preload("res://tests/test_maps.gd")
const UNDER := Vector3(1.5, 0.05, -1.0)
const OPEN := Vector3(1.5, 0.05, 1.6)
var main: Node3D
var p
var m
var f := 0
var ok := true
var start := 0
var peeked := false


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
		main.get_node("GameState").invulnerable[1] = true
		p = main.get_node("Players/1")
		m = main.get_node("Monsters").get_child(0)
		m.set_physics_process(false)
		Input.action_press("crouch")
	if f == 20:
		p.global_position = OPEN
		m.global_position = Vector3(1.5, 0.05, 4.1)
		m.look_at(Vector3(1.5, 0.05, 0), Vector3.UP)
	if f == 24:
		_check(p.crouching and not p.under_cover(), "kuca przy stole, nie pod nim")
		_check(m.can_see(p), "potwór widzi kucającego na widoku")
		p.global_position = UNDER
	if f == 28:
		_check(p.under_cover(), "pod blatem: under_cover")
		var t0 := Time.get_ticks_msec()
		var covers: Array = main.director.cover_points()
		_check(covers.any(func(c): return c.distance_to(UNDER) < 1.0),
			"reżyser zna miejsca pod stołami: %d, w tym pod stołem w hali (%d ms)" % [covers.size(), Time.get_ticks_msec() - t0])
		_check(not m.can_see(p), "potwór nie widzi gracza pod stołem (2,5 m przed nim, przodem)")
		# 2) Pościg na widoku, potem gracz pod stół.
		p.global_position = OPEN
		m.set_physics_process(true)
	if f == 34:
		_check(m.state == m.State.HUNT, "goni gracza na widoku (%s)" % m.State.keys()[m.state])
		p.global_position = UNDER
		start = f
	if start > 0 and f > start and m.state == m.State.PEEK_UNDER:
		peeked = true
	if start > 0 and f == start + 60 * 6:
		_check(peeked, "widział, jak gracz wchodzi pod stół: zagląda (PEEK_UNDER)")
		_check(m.state in [m.State.HUNT, m.State.ATTACK, m.State.RECOVER] and m._found_under == p,
			"po zajrzeniu znalazł gracza (%s)" % m.State.keys()[m.state])
		_check(m.can_see(p), "znalezionego pod stołem widzi")
		# 3) Pod stół 3 m dalej: pusto.
		m._found_under = null
		m.global_position = Vector3(-4.0, 0.05, 3.0)
		m.check_under(Vector3(-1.5, 0.05, -1.0))
		start = -f
	if start < 0 and f == -start + 60 * 6:
		_check(m.state != m.State.HUNT and m._found_under == null,
			"zaglądanie 3 m od gracza nic nie daje (%s)" % m.State.keys()[m.state])
		Input.action_release("crouch")
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
