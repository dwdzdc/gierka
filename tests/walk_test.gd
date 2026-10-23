extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Tymczasowy test: idź na wprost przez trzy pokoje, loguj cięcia kamery.

var main: Node3D
var p: Node3D
var frames := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()  # tryb offline: spawn gracza bez sieci
		p = main.get_node("Players/1")
		print("start rot_y=%.1f deg forward=%s" % [rad_to_deg(p.rotation.y), -p.global_transform.basis.z.snapped(Vector3.ONE * 0.01)])
		p.global_position = Vector3(-2.5, 0.05, 0)
		main.get_node("CameraDirector").camera_changed.connect(func(z):
			print("t=%.2f x=%.2f cut -> %s/%s" % [frames / 60.0, p.global_position.x, z.owner.name, z.name]))
		Input.action_press("move_forward")
		Input.action_press("run")
	if frames == 400:
		print("final pos ", p.global_position.snapped(Vector3.ONE * 0.01))
		return true
	return false
