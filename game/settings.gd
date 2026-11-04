class_name Settings
extends RefCounted
## Ustawienia zapisywane między uruchomieniami gry (`user://settings.cfg`).
## Na razie tylko ostatni adres z pola Dołącz; tu trafią też przyszłe opcje (menu ustawień, 50).
## Statyczne funkcje zamiast autoloadu: plik czyta się raz przy starcie menu i raz przy zapisie,
## więc nie ma po co trzymać go w pamięci.

const PATH := "user://settings.cfg"


static func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return default
	return config.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(PATH)  # brak pliku = puste ustawienia; reszta wpisów zostaje nietknięta
	config.set_value(section, key, value)
	config.save(PATH)
