extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Teleportuje gracza po siatce punktów w każdym pokoju (różne kierunki) i liczy,
# w ilu miejscach po ustabilizowaniu się kamery postaci nie widać.

var main: Node3D
var p: Node3D
var director
var frames := 0
var spots: Array[Vector3] = []
var idx := 0
var hidden := 0
var cuts := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)
	for x in range(-9, 46, 2):
		for z in range(-10, 11, 2):
			spots.append(Vector3(x + 0.5, 0.05, z + 0.5))

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()  # tryb offline: spawn gracza bez sieci
		p = main.get_node("Players/1")
		director = main.get_node("CameraDirector")
		if "--no-guard" in OS.get_cmdline_user_args():
			director.occlusion_grace = 1e9
		director.camera_changed.connect(func(_z): cuts += 1)
	if frames < 10:  # mapa składana w klatce 2; kolizje CSG są dopiero chwilę później
		return false
	var step := (frames - 10) % 30
	if step == 0:
		while idx < spots.size():
			var s := spots[idx]
			idx += 1
			if _inside(s):
				p.global_position = s
				p.rotation.y = randf() * TAU
				return false
		print("spots checked, hidden after settle: %d, cuts: %d" % [hidden, cuts])
		return true
	if step == 29 and director.current_zone and not director.is_target_visible(director.current_zone.camera):
		hidden += 1
		print("hidden at ", p.global_position.snapped(Vector3.ONE * 0.1), " shot ", director.current_zone.owner.name, "/", director.current_zone.name)
	return false

func _inside(s: Vector3) -> bool:
	# Wolne miejsce: brak kolizji kapsuły w tym punkcie i podłoga pod spodem.
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	q.shape = cap
	q.transform = Transform3D(Basis(), s + Vector3.UP * 0.9)
	q.collision_mask = 1
	var space := main.get_world_3d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var ray := PhysicsRayQueryParameters3D.create(s + Vector3.UP * 0.5, s + Vector3.DOWN, 1)
	return not space.intersect_ray(ray).is_empty()
