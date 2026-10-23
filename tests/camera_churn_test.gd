extends SceneTree
# Jak często tnie kamera przy losowym błądzeniu (15d). Losowe sterowanie tank co 0.6 s, 90 s.
# Wypisuje liczbę cięć na minutę i najkrótsze ujęcie. Cięcia < min_shot_time są dopuszczalne
# tylko wtedy, gdy postaci nie było widać (bezpiecznik).

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var director
var frames := 0
var cut_times: Array[float] = []
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = 5
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		director = main.get_node("CameraDirector")
		director.camera_changed.connect(func(_z): cut_times.append(frames / 60.0))
	if frames > 2 and frames % 36 == 0:
		for a in ["move_forward", "move_left", "move_right", "run"]:
			Input.action_release(a)
		Input.action_press("move_forward")
		var r := rng.randf()
		if r < 0.3:
			Input.action_press("move_left")
		elif r < 0.6:
			Input.action_press("move_right")
		if rng.randf() < 0.3:
			Input.action_press("run")
	if frames == 60 * 92:
		var shortest := INF
		for i in range(1, cut_times.size()):
			shortest = minf(shortest, cut_times[i] - cut_times[i - 1])
		print("cięć: %d w 90 s (%.1f/min), najkrótsze ujęcie %.2f s" % [cut_times.size() - 1, (cut_times.size() - 1) / 1.5, shortest])
		return true
	return false
