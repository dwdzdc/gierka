extends SceneTree
# Lampy (15q): w zgaszonym pokoju nic nie świeci (oprawy, lampki nad drzwiami po jego stronie,
# świetlik), zostaje tylko słaba poświata futryn. Migocząca żarówka przygasa razem z oprawą.
# Mapy z generatora (bez main), kilka seedów, aż trafi się zgaszona biblioteka.

const FRAME_MATERIAL := preload("res://rooms/materials/door_frame.tres")
var results: Array[String] = []
var parent: Node3D
var seed_value := 0
var dark_rooms := 0
var dark_library := false
var flicker_lights: Array = []
var f := 0

func _initialize() -> void:
	parent = Node3D.new()
	root.add_child.call_deferred(parent)

func _check(ok: bool, text: String) -> void:
	results.append("%s %s" % ["OK " if ok else "ZLE", text])

func _material(node: Node) -> Material:
	if node is CSGPrimitive3D:
		return node.material
	if node.material_override:
		return node.material_override
	return node.mesh.surface_get_material(0) if node.mesh else null

func _glowing(room: Node) -> Array[String]:
	var found: Array[String] = []
	for node in room.find_children("*", "", true, false):
		if not (node is MeshInstance3D or node is CSGPrimitive3D) or not node.is_visible_in_tree():
			continue
		var material := _material(node) as StandardMaterial3D
		if material and material.emission_enabled and material != FRAME_MATERIAL:
			found.append(str(room.get_path_to(node)))
	return found

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	if not dark_library and seed_value < 40:
		for child in parent.get_children():
			child.free()
		var rooms = load("res://game/map_generator.gd").new().generate(parent, seed_value, 30)
		seed_value += 1
		for room in rooms:
			if room.dark:
				dark_rooms += 1
				dark_library = dark_library or room.name.contains("Library")
				var glowing := _glowing(room)
				if not glowing.is_empty():
					_check(false, "seed %d, zgaszony %s świeci: %s" % [seed_value - 1, room.name, glowing])
			for light in room.find_children("Light*", "OmniLight3D", true, false):
				if light.get_script() != null and light.visible:
					flicker_lights.append(light)
		if not dark_library:
			flicker_lights.clear()
		return false
	if f < 200:  # migocząca lampa działa dopiero po kilku klatkach
		return false
	_check(dark_library, "trafiła się zgaszona biblioteka (seedy 0..%d), zgaszonych pokoi: %d" % [seed_value - 1, dark_rooms])
	var follows := true
	for light in flicker_lights:
		var fixture = light.get_parent().get_node_or_null(NodePath(light.name.replace("Light", "Fixture")))
		if fixture == null or not light.is_processing() or fixture.material_override == null:
			follows = false
			continue
		var base: float = light.get("_base_energy")
		var expected: float = load("res://rooms/materials/door_lamp.tres").emission_energy_multiplier * light.light_energy / base
		follows = follows and absf(fixture.material_override.emission_energy_multiplier - expected) < 0.01
	_check(not flicker_lights.is_empty() and follows, "%d migoczących lamp działa, oprawy świecą jak żarówki" % flicker_lights.size())
	for r in results:
		print(r)
	print("PROBLEMY: %d" % results.filter(func(r): return r.begins_with("ZLE")).size())
	return true
