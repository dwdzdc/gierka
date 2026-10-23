extends SceneTree
# Test sieci: odpal dwa procesy:
#   godot --headless --path . -s tests/net_test.gd -- --host
#   godot --headless --path . -s tests/net_test.gd -- --join=127.0.0.1
# Każdy przesuwa własną postać w inne miejsce i wypisuje, gdzie widzi wszystkich graczy.

var main: Node3D
var frames := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)  # main sam hostuje/dołącza na podstawie argumentów

func _physics_process(_d: float) -> bool:
	frames += 1
	if main == null or not main.is_inside_tree():
		return false
	var players: Node3D = main.get_node("Players")
	var me := players.get_node_or_null(str(main.multiplayer.get_unique_id()))
	if me and frames % 60 == 0 and frames <= 180:
		me.global_position = Vector3(-2.5 + 0.5 * frames / 60.0, 0.05, -2.0 if main.multiplayer.is_server() else 2.0)
	if frames == 200 and main.multiplayer.is_server():
		for id in main.get_node("GameState").players:
			if id != 1:
				main.get_node("GameState").damage(id, 30)
	if frames == 210 and main.multiplayer.is_server():
		var gs = main.get_node("GameState")
		for id in gs.players:
			if id != 1:
				gs.players[id].bleeding = true
		gs._broadcast()
	if frames == 230 and not main.multiplayer.is_server():
		Input.action_press("bandage_self")  # klient prosi hosta o bandaż (po 2 s trzymania)
	if frames == 400:
		var role := "HOST" if main.multiplayer.is_server() else "KLIENT"
		print("%s (id %d) widzi %d graczy:" % [role, main.multiplayer.get_unique_id(), players.get_child_count()])
		print("  game_state: ", main.get_node("GameState").players)
		for m in main.get_node("Monsters").get_children():
			print("  potwor %s pos=%s state=%d" % [m.name, m.global_position.snapped(Vector3.ONE * 0.1), m.state])
		for p in players.get_children():
			print("  %s pos=%s authority=%d kamera_lokalna=%s" % [p.name, p.global_position.snapped(Vector3.ONE * 0.01),
				p.get_multiplayer_authority(), main.get_node("CameraDirector").target == p])
	# Host żyje dłużej, żeby klient zdążył się wypisać przed rozłączeniem.
	return frames >= (520 if main.multiplayer.is_server() else 400)
