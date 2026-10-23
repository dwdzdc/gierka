extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Bandaże: H opatruje siebie (2 s), E opatruje krwawiącego kolegę; bandaże się zużywają.

var main: Node3D
var gs
var frames := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _say(text: String) -> void:
	log.append("t=%.1f %s | 1: krwawi=%s bandaże=%d  2: krwawi=%s bandaże=%d" % [frames / 60.0, text, gs.is_bleeding(1), gs.bandages(1), gs.is_bleeding(2), gs.bandages(2)])

func _physics_process(_d: float) -> bool:
	frames += 1
	var t := frames - 2
	if t == 0:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		gs = main.get_node("GameState")
		main._spawn_player(2)
		main.get_node("Players/1").global_position = Vector3(-2.5, 0.05, 1.5)
		main.get_node("Players/2").global_position = Vector3(-2.5, 0.05, 0.3)
		gs.players[1].bleeding = true
		gs.players[2].bleeding = true
		_say("obaj krwawią")
		Input.action_press("bandage_self")
	if t == 60 * 1:
		_say("1 s trzymania H")
	if t == 60 * 3:
		_say("3 s trzymania H")
		Input.action_release("bandage_self")
		Input.action_press("interact")
	if t == 60 * 6:
		_say("3 s trzymania E przy koledze")
		Input.action_release("interact")
		gs.players[1].bleeding = true
		Input.action_press("bandage_self")
	if t == 60 * 9:
		_say("znów krwawi, H przy 0 bandaży")
		print("\n".join(log))
		return true
	return false
