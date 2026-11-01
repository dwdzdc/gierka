extends SceneTree
# Raport błędu (F2): okno otwiera się z opisanym zdarzeniem, blokuje sterowanie postacią
# (żeby pisanie nie odpalało akcji), a tekst raportu ma komplet danych do zgłoszenia.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var dialog
var f := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main.get_node("Menu").visible = false
		main._on_connected()
		main.get_node("Players/1").global_position = Vector3(12, 0.05, 0)  # korytarz
	if f == 10:
		main._track_room()  # w teście nie czekamy 0,25 s na zegar
	if f == 12:
		var ev := InputEventAction.new()
		ev.action = "report_bug"
		ev.pressed = true
		Input.parse_input_event(ev)
	if f == 14:
		dialog = main.get_node("ReportDialog")
		var player = main.get_node("Players/1")
		print("okno widoczne: %s, gracz stoi: %s, akcje zablokowane: %s" % [
			dialog.visible, not player.is_physics_processing(), not player.is_processing_unhandled_input()])
		dialog._note.text = "test: potwór przeszedł przez zamknięte drzwi"
		var image := root.get_texture().get_image()
		if image:  # bez --headless: zrzut okna do katalogu tymczasowego
			image.save_png(OS.get_temp_dir().path_join("report_dialog.png"))
		dialog._copy()
		var report: String = dialog.last_report
		print("raport: %d znaków" % report.length())
		for needle in ["test: potwór przeszedł przez zamknięte drzwi", "wersja: dev", "seed ",
				"pokoi na mapie", "etap trudności", "pozycja:", "Corridor", "ujęcie kamery",
				"POTWORY", "dystans", "-- --seed="]:
			print("  %s: %s" % [needle, report.contains(needle)])
		print("----\n%s\n----" % report)
		# Esc przy otwartym raporcie zamyka okno, a nie grę (main ma Esc = wyjście).
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		Input.parse_input_event(esc)
	if f == 16:
		print("po Esc okno: %s, gracz stoi: %s" % [
			dialog.visible, not main.get_node("Players/1").is_physics_processing()])
		return true
	return false
