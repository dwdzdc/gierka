extends SceneTree
# Kolejność potworów (36d): pierwszy zawsze Łowca, kolejne losowo i bez powtórzeń.
# Kilka rund na tej samej scenie; w każdej wymuszamy etapy do maksimum potworów.
#   godot --headless --path . -s tests/spawn_order_test.gd

const Maps = preload("res://tests/test_maps.gd")
const ROUNDS := 8
var main: Node3D
var director
var f := 0
var ok := true
var orders := {}  # kolejność -> ile razy


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)


func _check(cond: bool, what: String) -> void:
	ok = ok and cond
	if not cond:
		print("ZLE  ", what)


func _physics_process(_d: float) -> bool:
	f += 1
	if f != 3:
		return false
	main._on_connected()
	director = main.director
	for i in ROUNDS:
		for old in main.monsters.get_children():
			old.free()
		director.start_round(main.rooms, main.monsters)
		for stage in 5:
			director._next_stage()
		var order: Array = main.monsters.get_children().map(func(m): return m.profile_id)
		orders[str(order)] = orders.get(str(order), 0) + 1
		_check(order[0] == "hunter", "runda %d: pierwszy %s" % [i, order[0]])
		_check(order.size() == director.max_monsters, "runda %d: %d potworów" % [i, order.size()])
		var unique := {}
		for id in order:
			unique[id] = true
		_check(unique.size() == order.size(), "runda %d: powtórzenie w %s" % [i, order])
	for order in orders:
		print("%s x%d" % [order, orders[order]])
	_check(orders.size() > 1, "kolejność się zmienia między rundami")
	print("WYNIK: ", "OK" if ok else "BŁĄD")
	return true
