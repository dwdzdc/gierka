extends SceneTree
# Bateria latarki (41c): zużycie tylko przy włączonej latarce, migotanie przy słabej,
# pusta = latarka gaśnie i nie da się jej włączyć, bateria z mapy doładowuje.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var p
var gs
var f := 0
var ok := true
var energies := {}

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
		main.get_node("Monsters").get_child(0).set_physics_process(false)
		p = main.get_node("Players/1")
		gs = main.get_node("GameState")
		p.flashlight.visible = false
	if f == 2 + 60 * 3:
		_check(gs.battery(1) == gs.BATTERY_MAX, "zgaszona latarka nie zużywa baterii (%d)" % gs.battery(1))
		p.flashlight.visible = true
	if f == 2 + 60 * 6:
		_check(gs.battery(1) in [gs.BATTERY_MAX - 3, gs.BATTERY_MAX - 2], "włączona zużywa 1 s na sekundę (%d)" % gs.battery(1))
		gs.players[1].battery = 20
		gs._broadcast()
	if f > 2 + 60 * 6 and f < 2 + 60 * 9:
		energies[snappedf(p.flashlight.light_energy, 0.01)] = true
	if f == 2 + 60 * 9:
		_check(energies.size() > 3, "słaba bateria: latarka migocze (%d różnych jasności)" % energies.size())
		gs.players[1].battery = 1
		gs._broadcast()
	if f == 2 + 60 * 11:
		_check(gs.battery(1) == 0 and not p.flashlight.visible, "pusta bateria: latarka gaśnie")
		var press := InputEventAction.new()
		press.action = "toggle_flashlight"
		press.pressed = true
		p._unhandled_input(press)
		_check(not p.flashlight.visible, "pustej nie da się włączyć")
		var batteries = main.loot.get_children().filter(func(n): return n.scene_file_path.ends_with("battery_pickup.tscn"))
		_check(batteries.size() >= 1, "na mapie są baterie (%d)" % batteries.size())
		p.global_position = batteries[0].global_position
	if f == 2 + 60 * 12:
		_check(gs.battery(1) == gs.BATTERY_PICKUP, "bateria z mapy doładowuje do %d s" % gs.battery(1))
		print("OK" if ok else "FAIL")
		return true
	return false
