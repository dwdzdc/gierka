extends SceneTree
# Wszyscy powaleni (62): skoro nikt nie stoi, nikt nie pomoże; runda kończy się po ~3 s,
# a nie po 30 s wykrwawiania. Kontrola: gdy ktoś stoi, powalony dalej czeka na pomoc.
#   godot --headless --path . -s tests/all_down_test.gd

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var ok := true
var start := 0


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
		for m in main.get_node("Monsters").get_children():
			m.queue_free()
		gs = main.get_node("GameState")
		main._spawn_player(2)
		main.get_node("Players/2").set_physics_process(false)
		gs.damage(2, 200)
	if f == 2 + 60 * 6:
		_check(gs.Life.keys()[gs.life(2)] == "DOWNED", "gracz 1 stoi: powalony gracz 2 po 6 s dalej czeka na pomoc")
		gs.damage(1, 200)
		start = f
	if start > 0 and f == start + 60 * 5:
		_check(gs.round_over, "obaj powaleni: runda skończona po <= 5 s (a nie po 30 s)")
		_check(gs.Life.keys()[gs.life(1)] == "DEAD" and gs.Life.keys()[gs.life(2)] == "DEAD", "powaleni liczą się jako martwi")
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
