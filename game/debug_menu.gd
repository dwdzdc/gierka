class_name DebugMenu
extends CanvasLayer
## Menu testowe (klawisz `). Działa tylko u hosta i tylko w buildzie deweloperskim
## (uruchomienie przez Godota) albo po starcie z `-- --cheats`; w wydanej grze go nie ma.
##
## Nowe narzędzie = jedna linia w `_build_actions` (nazwa + funkcja), bez nowych klawiszy.

var _main: Node3D
var _immortal := false
var _frozen := false
var _items: VBoxContainer


func _ready() -> void:
	_main = get_parent()
	visible = false
	layer = 5
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	_items = VBoxContainer.new()
	_items.add_theme_constant_override("separation", 6)
	margin.add_child(_items)


static func enabled() -> bool:
	return OS.is_debug_build() or "--cheats" in OS.get_cmdline_user_args()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("debug_menu"):
		return
	if not enabled() or not multiplayer.is_server() or not _main.get_node("HUD").visible:
		return
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _items.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "MENU TESTOWE (host)   ` zamyka"
	title.add_theme_font_size_override("font_size", 26)
	_items.add_child(title)
	for action in _build_actions():
		if action.is_empty():
			_items.add_child(HSeparator.new())
			continue
		var button := Button.new()
		button.text = action.name
		button.add_theme_font_size_override("font_size", 22)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void:
			action.run.call()
			_rebuild())
		_items.add_child(button)


## Lista narzędzi: {"name", "run"}; pusty słownik = separator.
func _build_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for profile_id in MonsterDirector.SPAWN_ORDER:
		var profile := MonsterProfile.load_by_id(profile_id)
		actions.append({"name": "Spawn: %s (pokój obok)" % profile.display_name, "run": _spawn_near.bind(profile_id)})
	actions.append({})
	actions.append({"name": "Następny etap teraz (etap %d)" % _main.director.stage, "run": _main.director._next_stage})
	actions.append({"name": "Zamroź potwory: %s" % ("WŁ" if _frozen else "wył"), "run": _toggle_freeze})
	actions.append({"name": "Usuń wszystkie potwory", "run": _remove_monsters})
	actions.append({})
	actions.append({"name": "Nieśmiertelność: %s" % ("WŁ" if _immortal else "wył"), "run": _toggle_immortal})
	actions.append({"name": "Ulecz (HP 100, bez krwawienia, +bandaże)", "run": _heal})
	actions.append({"name": "+100 monet", "run": _add_coins})
	actions.append({"name": "+1 klucz", "run": func() -> void: _main.game_state.add_key(multiplayer.get_unique_id())})
	actions.append({"name": "Teleport do windy", "run": _teleport_to_exit})
	return actions


func _me() -> Player:
	return _main.players.get_node_or_null(str(multiplayer.get_unique_id())) as Player


## Pokój najbliższy graczowi, ale nie ten, w którym stoi (żeby potwór nie wyskoczył na plecy).
func _spawn_near(profile_id: String) -> void:
	var me := _me()
	if me == null:
		return
	var best: Room = null
	for room in _main.rooms:
		if (room.transform * room.bounds).has_point(me.global_position + Vector3.UP * 0.5) or room.bounds.size.y >= 8.0:
			continue
		if best == null or room.global_position.distance_to(me.global_position) < best.global_position.distance_to(me.global_position):
			best = room
	if best:
		var monster: Monster = _main.director.spawn(profile_id, best)
		monster.set_physics_process(not _frozen)


func _toggle_freeze() -> void:
	_frozen = not _frozen
	for monster in _main.director.monsters():
		monster.set_physics_process(not _frozen)


func _remove_monsters() -> void:
	for monster in _main.director.monsters():
		monster.queue_free()


func _toggle_immortal() -> void:
	_immortal = not _immortal
	_main.game_state.set_invulnerable(multiplayer.get_unique_id(), _immortal)


func _heal() -> void:
	_main.game_state.debug_heal(multiplayer.get_unique_id())


func _add_coins() -> void:
	var me := _me()
	if me:
		_main.game_state.add_coins(multiplayer.get_unique_id(), 100, me.global_position)


func _teleport_to_exit() -> void:
	var me := _me()
	if me:
		me.global_position = _main.game_state.exit_position + Vector3(1.5, 0, 0)
