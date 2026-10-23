extends SceneTree
# Potwór bez graczy w pobliżu: powinien patrolować, czyli przemieszczać się po mapie.

var main: Node3D
var frames := 0
var visited := {}

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Players/1").global_position = Vector3(-4, 0.05, -3)  # gracz w kącie hali, nieruchomo
	if frames < 2:
		return false
	var m = main.get_node("Monsters").get_child(0)
	var cell := Vector2i(floori(m.global_position.x / 4.0), floori(m.global_position.z / 4.0))
	visited[cell] = true
	if frames % 300 == 0:
		print("t=%ds pos=%s state=%s" % [frames / 60, m.global_position.snapped(Vector3.ONE * 0.1), m.State.keys()[m.state]])
	if frames == 60 * 60:
		print("odwiedzone komórki 4x4 m: %d" % visited.size())
		return true
	return false
