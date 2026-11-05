extends SceneTree
# Menu testowe: otwiera się u hosta, spawnuje rzeźnika w pokoju obok, nieśmiertelność działa.
# Narzędzia gracza na innym graczu (61): wybór celu, ożywienie martwego, nieśmiertelność;
# debug (F1) pokazuje pokój każdego gracza.

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
		var gs = main.get_node("GameState")
		print("po egzekucji z nieśmiertelnością: %s" % gs.Life.keys()[gs.life(1)])
		var ok: bool = gs.Life.keys()[gs.life(1)] == "OK"
		# Drugi gracz: zabity, potem ożywiony z menu hosta.
		main._spawn_player(2)
		main.get_node("Players/2").set_physics_process(false)
		main.get_node("Players/2").global_position = Vector3(34, 0.05, 4)  # magazyn
		gs.execute(2)
		menu._next_target()
		var target_ok: bool = menu._target() == 2
		menu._heal()
		var revived: bool = gs.Life.keys()[gs.life(2)] == "OK" and gs.hp(2) == 100
		menu._toggle_immortal()
		var immortal: bool = gs.invulnerable.get(2, false)
		gs.execute(2)
		var survived: bool = gs.Life.keys()[gs.life(2)] == "OK"
		menu._next_target()
		var back: bool = menu._target() == 1
		main._show_debug = true
		var text: String = main._stats_text()
		var listed: bool = text.contains("GRACZE (pozycje)") and text.contains("Storage")
		print("cel gracz 2: %s, ożywiony z martwego: %s, nieśmiertelny: %s (przeżył egzekucję: %s), cel wrócił do hosta: %s, pokój gracza 2 w debugu: %s" % [target_ok, revived, immortal, survived, back, listed])
		ok = ok and target_ok and revived and survived and back and listed
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
