extends SceneTree
# Mapa-notatnik (65): zapisuje tylko odwiedzone pokoje, windę dopiero, gdy była w kadrze;
# z wciśniętym M postać stoi mimo W; W/S zmieniają piętro; nowa mapa czyści notatnik.

const Maps = preload("res://tests/test_maps.gd")
var main
var map
var p
var f := 0
var start := Vector3.ZERO
var log: Array[String] = []
var ok := true


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)


func _check(cond: bool, what: String) -> void:
	ok = ok and cond
	log.append(("OK   " if cond else "ZLE  ") + what)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		map = main.explored_map
		p = main.get_node("Players/1")
		var m = main.get_node("Monsters").get_child(0)
		m.set_physics_process(false)
		m.global_position = Vector3(-30, 0, 0)
	if f == 10:
		_check(map.visited.keys() == [0], "na starcie zapisana tylko hala: %s" % [map.visited.keys()])
		_check(not map.exit_seen, "winda nieznana")
		_check(not map.visible, "mapa zamknięta bez M")
		start = p.global_position
		Input.action_press("map")
		Input.action_press("move_forward")
	if f == 50:
		_check(map.visible, "z M mapa otwarta")
		_check(p.global_position.distance_to(start) < 0.05, "z M postać stoi mimo W (%.2f m)" % p.global_position.distance_to(start))
		Input.action_release("move_forward")
		Input.action_release("map")
	if f == 55:
		_check(not map.visible, "po puszczeniu M mapa znika")
		p.global_position = Vector3(16, 0.05, 0)  # korytarz
	if f == 65:
		_check(map.visited.size() == 2, "korytarz dopisany: %s" % [map.visited.keys()])
		_check(not map.exit_seen, "winda dalej nieznana (jest w magazynie)")
		# Magazyn: najpierw tuż za wejściem, z dala od windy przy wschodnich drzwiach.
		p.global_position = Vector3(27, 0.05, -8)
	if f == 75:
		_check(map.visited.size() == 3, "magazyn dopisany")
		var exit: Vector3 = main.game_state.exit_position
		log.append("     winda: %s, w kadrze od razu: %s" % [exit, map.exit_seen])
		p.global_position = exit + Vector3(-2.5, 0, 0)
	if f == 120:
		_check(map.exit_seen, "winda zapisana, gdy była w kadrze")
		var floors: Array[int] = [-1, 0, 2]
		map.shown_floor = 0
		_check(map._step_floor(floors, 1) == 2 and map._step_floor(floors, -1) == -1, "W/S: następne piętro z odwiedzonymi pokojami")
		map.shown_floor = 2
		_check(map._step_floor(floors, 1) == 2, "nad najwyższym piętrem W nic nie zmienia")
		main._build_map(main.map_seed, main.room_count)
		_check(not map.exit_seen and map.visited.is_empty(), "nowa mapa: notatnik od zera")
	if f == 125:
		print("\n".join(log))
		print("WYNIK: ", "OK" if ok else "ZLE")
		return true
	return false
