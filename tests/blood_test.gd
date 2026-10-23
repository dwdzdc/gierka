extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Krwawiący gracz idzie przez halę: krople co ~0.7 m, decale u wszystkich.
# Potem powalenie: kałuża co 3 s. Na koniec zrzut ekranu (z oknem) do sprawdzenia wyglądu.

var main: Node3D
var gs
var bt
var frames := 0
var shot_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.trim_prefix("--shot=")
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	var t := frames - 2
	if t == 0:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		gs = main.get_node("GameState")
		bt = main.get_node("BloodTrail")
		var p = main.get_node("Players/1")
		p.global_position = Vector3(-3.5, 0.05, 2.5)
		p.rotation.y = -PI / 2
		gs.players[1].bleeding = true
		Input.action_press("move_forward")
	if t == 150:
		Input.action_release("move_forward")
		print("po 2.5 s marszu: krople=%d decale=%d" % [bt.drops.size(), bt.get_child_count()])
		gs.players[1].hp = 1
	if t == 60 * 9:
		print("po powaleniu (~6 s): krople=%d stan=%s" % [bt.drops.size(), gs.Life.keys()[gs.life(1)]])
		var f = bt.freshest_near(main.get_node("Players/1").global_position, 2.0)
		print("najświeższa kropla przy graczu: %s" % ("brak" if f.is_empty() else str(f.position.snapped(Vector3.ONE * 0.1))))
		if shot_path != "":
			root.get_texture().get_image().save_png(shot_path)
		return true
	return false
