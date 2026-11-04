extends SceneTree
# Podgląd kolegi po śmierci (58): martwy gracz od razu widzi ujęcie strefy, w której stoi kolega,
# choć kolega się nie rusza (dawniej obraz pojawiał się dopiero, gdy kolega zmienił strefę).
#   godot --headless --path . -s tests/spectate_test.gd

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var cd
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
		gs = main.get_node("GameState")
		main.get_node("Players/2").set_physics_process(false)
		main.get_node("Players/2").global_position = Vector3(34, 0.05, 4)  # magazyn
		for m in main.get_node("Monsters").get_children():
			m.set_physics_process(false)
	if f == 30:
		cd = get_first_node_in_group(&"camera_director")
		_check(cd.target == main.get_node("Players/1"), "na starcie kamera śledzi własną postać")
		gs.damage(1, 500)
		gs.damage(1, 500)  # powalony, potem dobity
	if f == 33:
		var p2: Node3D = main.get_node("Players/2")
		_check(gs.Life.keys()[gs.life(1)] == "DEAD", "gracz 1 nie żyje")
		_check(cd.target == p2, "kamera przełączyła się na gracza 2")
		_check(cd.current_zone != null and cd.current_zone.overlaps_body(p2),
			"od razu jest ujęcie strefy, w której stoi gracz 2 (bez ruchu): %s" % (cd.current_zone.get_parent().name if cd.current_zone else "brak"))
		_check(cd.current_zone != null and cd.current_zone.camera.current, "ta kamera jest aktywna")
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
