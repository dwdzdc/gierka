extends SceneTree
# Chodzenie, bieg i stanie: ile hałasów i o jakim promieniu emituje gracz.

var main: Node3D
var frames := 0
var log := {"walk": [], "run": [], "idle": []}
var phase := "idle"

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()  # bez potwora
		var p: Node3D = main.get_node("Players/1")
		p.global_position = Vector3(-2.5, 0.05, 0)
		root.get_node("NoiseBus").noise_made.connect(func(_pos, r, _src): log[phase].append(r))
	if frames == 10:
		phase = "walk"
		Input.action_press("move_forward")
	if frames == 130:
		phase = "run"
		Input.action_press("run")
	if frames == 250:
		phase = "idle"
		Input.action_release("move_forward")
		Input.action_release("run")
	if frames == 400:
		for k in log:
			print("%s: %d hałasów, promienie %s" % [k, log[k].size(), log[k]])
		return true
	return false
