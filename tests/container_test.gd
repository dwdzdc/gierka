extends SceneTree
# Łup w pojemnikach (33b): pojemniki na mapie, przeszukanie E (1,5 s) daje zawartość i hałas,
# drugi raz się nie da; część monet zostaje na meblach.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var p
var gs
var f := 0
var ok := true
var c
var noise := 0.0
var coins_before := 0

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
	if f == 10:
		var containers = main.loot.get_children().filter(func(n): return n.is_in_group(&"loot_containers"))
		var piles = main.loot.get_children().filter(func(n): return n.scene_file_path.ends_with("coin_pile.tscn"))
		var raised = piles.filter(func(n): return n.global_position.y > 0.4)
		print("pojemniki %d, kupki %d (na meblach %d)" % [containers.size(), piles.size(), raised.size()])
		_check(containers.size() >= 1, "na mapie są pojemniki")
		# Pojemnik z monetami (zawartość zna host), postać przed nim, przodem.
		for candidate in containers:
			if candidate.content == candidate.Content.COINS:
				c = candidate
		if c == null:
			c = containers[0]
			c.content = c.Content.COINS
			c.value = 40
		var front: Vector3 = c.global_position + Vector3(0, 0, 1.0)
		p.global_position = front
		p.look_at(Vector3(c.global_position.x, front.y, c.global_position.z), Vector3.UP)
		coins_before = gs.coins(1)
		root.get_node("NoiseBus").noise_made.connect(func(_pos, r, src): if src == p and r == gs.SEARCH_NOISE_RADIUS: noise = r)
	if f == 12:
		_check(p.hint.begins_with("E - przeszukaj"), "podpowiedź: %s" % p.hint)
		Input.action_press("interact")
	if f == 12 + 45:
		_check(not c.opened, "po 0,75 s jeszcze nie przeszukany (%d%%)" % int(p.help_progress * 100))
	if f == 12 + 100:
		Input.action_release("interact")
		_check(c.opened, "po 1,5 s pojemnik otwarty")
		_check(gs.coins(1) == coins_before + c.value, "monety z pojemnika: +%d" % (gs.coins(1) - coins_before))
		_check(noise > 0.0, "przeszukiwanie hałasuje (%.0f m)" % noise)
		coins_before = gs.coins(1)
		Input.action_press("interact")
	if f == 12 + 220:
		Input.action_release("interact")
		_check(gs.coins(1) == coins_before, "drugi raz nic nie daje")
		print("OK" if ok else "FAIL")
		return true
	return false
