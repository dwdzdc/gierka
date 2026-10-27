extends SceneTree
# Menu testowe: otwiera się u hosta, spawnuje rzeźnika w pokoju obok, nieśmiertelność działa.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var f := 0
var menu

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main.get_node("Menu").visible = false
		main._on_connected()
		menu = main.get_node("DebugMenu")
		main.get_node("Players/1").global_position = Vector3(12, 0.05, 0)  # korytarz
	if f == 10:
		var ev := InputEventAction.new()
		ev.action = "debug_menu"
		ev.pressed = true
		Input.parse_input_event(ev)
	if f == 14:
		print("menu widoczne: %s, przycisków: %d" % [menu.visible, menu._items.get_child_count()])
		var image := root.get_texture().get_image()
		if image:  # bez --headless: zrzut menu do katalogu tymczasowego
			image.save_png(OS.get_temp_dir().path_join("debug_menu.png"))
		menu._spawn_near("butcher")
		var b = main.get_node("Monsters").get_children().filter(func(m): return m.profile_id == "butcher")
		print("rzeźnik w pokoju: %s" % main._room_name_at(b[0].global_position))
		menu._toggle_immortal()
		main.get_node("GameState").execute(1)
		print("po egzekucji z nieśmiertelnością: %s" % main.get_node("GameState").Life.keys()[main.get_node("GameState").life(1)])
		return true
	return false
