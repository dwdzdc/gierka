extends CanvasLayer
## Raport błędu (F2): krótki opis od gracza + stan gry, kopiowane do schowka.
## Osobny węzeł zamiast stałego fragmentu sceny, bo UI buduje się w kodzie (jak w menu
## testowym): nowe pole w raporcie = jedna linia w `_build_ui`.
##
## Gra się NIE pauzuje: pauza u hosta zamroziłaby potwory i zegar rundy wszystkim.
## Zamiast tego `main.set_report_open` blokuje sterowanie własną postacią, więc pisanie
## nie porusza nią ani nie odpala akcji (F, Q, R…), a świat leci dalej.

## Kolory tekstu w oknie (spójne z resztą UI).
const HINT_COLOR := Color(0.8, 0.8, 0.75)
const INFO_COLOR := Color(0.5, 0.9, 0.5)
## UI okna: warstwa nad HUD-em, szerokość panelu, marginesy i czcionki.
const LAYER := 4  # nad HUD (2) i menu (3), pod debug menu (5)
const PANEL_WIDTH := 760
const PANEL_MARGIN := 28
const ITEM_SEPARATION := 12
const TITLE_FONT := 26
const HINT_FONT := 18
const NOTE_HEIGHT := 140
const NOTE_FONT := 20
const BUTTON_FONT := 20

var last_report := ""  # ostatni tekst wysłany do schowka (test nie dotyka schowka)

var _main: Node3D
var _note: TextEdit
var _info: Label


func _ready() -> void:
	_main = get_parent()
	visible = false
	layer = LAYER  # nad HUD (2) i menu (3), pod debug menu (5)
	_build_ui()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PANEL_MARGIN)
	panel.add_child(margin)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", ITEM_SEPARATION)
	margin.add_child(items)

	var title := Label.new()
	title.text = "RAPORT BŁĘDU (F2)"
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	items.add_child(title)

	var hint := Label.new()
	hint.text = "Krótko, co się stało. Do raportu dołączy się stan gry (seed, pokój, potwory, kamera).\nGra nie stoi: twoja postać stoi w miejscu, dopóki piszesz."
	hint.add_theme_font_size_override("font_size", HINT_FONT)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	items.add_child(hint)

	_note = TextEdit.new()
	_note.custom_minimum_size = Vector2(0, NOTE_HEIGHT)
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.placeholder_text = "np. potwór przeszedł przez zamknięte drzwi w magazynie"
	_note.add_theme_font_size_override("font_size", NOTE_FONT)
	items.add_child(_note)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", HINT_FONT)
	_info.add_theme_color_override("font_color", INFO_COLOR)
	items.add_child(_info)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", ITEM_SEPARATION)
	items.add_child(row)
	var close_button := Button.new()
	close_button.text = "Zamknij (Esc)"
	close_button.add_theme_font_size_override("font_size", BUTTON_FONT)
	close_button.pressed.connect(close)
	row.add_child(close_button)
	var copy_button := Button.new()
	copy_button.text = "Kopiuj do schowka (Ctrl+Enter)"
	copy_button.add_theme_font_size_override("font_size", BUTTON_FONT)
	copy_button.pressed.connect(_copy)
	row.add_child(copy_button)


## `_input`, a nie `_unhandled_input`: Esc i F2 muszą dojść tutaj, zanim zobaczy je
## main (Esc = wyjście z gry) i zanim pole tekstowe połknie klawisz.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("report_bug") or event.is_action_pressed("quit"):
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and event.ctrl_pressed:
		_copy()
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return
	visible = true
	_note.text = ""
	_info.text = ""
	_main.set_report_open(true)
	_note.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_note.release_focus()
	_main.set_report_open(false)


func _copy() -> void:
	last_report = _main.report_text(_note.text)
	DisplayServer.clipboard_set(last_report)
	_info.text = "Skopiowano %d znaków do schowka. Wklej w zgłoszeniu; Esc zamyka." % last_report.length()
	_main.report_copied()
