extends SceneTree
# Pole "Dołącz" pamięta ostatni adres (57): wpisz adres, kliknij Dołącz, a po powrocie do menu
# (nowa scena, jak po rozłączeniu albo wyjściu hosta) adres jest już w polu.
# Prawdziwe ustawienia gracza są odkładane na bok i przywracane na końcu.
#   godot --headless --path . -s tests/last_address_test.gd

const PATH := "user://settings.cfg"
const ADDRESS := "test.at.ply.gg:12345"
var backup := PackedByteArray()
var had_file := false
var main: Node
var f := 0


func _initialize() -> void:
	had_file = FileAccess.file_exists(PATH)
	if had_file:
		backup = FileAccess.get_file_as_bytes(PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)


func _process(_d: float) -> bool:
	f += 1
	if f == 3:
		main.address_input.text = ADDRESS
		main._on_join_pressed()
		root.multiplayer.multiplayer_peer.close()
		main.queue_free()
	if f == 5:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if f == 7:
		var got: String = main.address_input.text
		var ok := got == ADDRESS
		print("%s  po powrocie do menu w polu Dołącz: '%s'" % ["OK " if ok else "ZLE", got])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		if had_file:
			var file := FileAccess.open(PATH, FileAccess.WRITE)
			file.store_buffer(backup)
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
