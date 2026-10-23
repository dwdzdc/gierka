extends SceneTree
# Powalenie i podnoszenie w jednym procesie: drugi gracz (peer 2) dodany ręcznie.
# 1) gracz 2 powalony, gracz 1 trzyma E obok -> po 3 s gracz 2 wstaje z 30 HP
# 2) gracz 2 znów powalony, nikt nie pomaga -> po 30 s umiera
# 3) gracz 1 ginie -> wszyscy martwi -> po 5 s reset obu

var main: Node3D
var gs
var frames := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _say(text: String) -> void:
	log.append("t=%.1f %s | 1:%s/%d 2:%s/%d" % [frames / 60.0, text, gs.Life.keys()[gs.life(1)], gs.hp(1), gs.Life.keys()[gs.life(2)], gs.hp(2)])

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		gs = main.get_node("GameState")
		main._spawn_player(2)
		main.get_node("Players/1").global_position = Vector3(-2.5, 0.05, 1.5)
		main.get_node("Players/2").global_position = Vector3(-2.5, 0.05, 0.3)
		gs.damage(2, 200)
		_say("gracz 2 powalony")
		Input.action_press("interact")
	if frames == 2 + 60 * 2:
		_say("po 2 s trzymania E")
	if frames == 2 + 60 * 4:
		_say("po 4 s trzymania E")
		Input.action_release("interact")
		gs.damage(2, 200)
		_say("gracz 2 znów powalony")
	if frames == 2 + 60 * 36:
		_say("po 32 s bez pomocy")
		gs.damage(1, 200)
		gs.damage(1, 200)
		_say("gracz 1 powalony i dobity")
	if frames == 2 + 60 * 43:
		_say("7 s po wipe")
		print("\n".join(log))
		return true
	return false
