extends SceneTree
# Czy postać fizycznie wchodzi po rampie i po schodach (bieg 1 do półpiętra, bieg 2 na górę).
# Mapa: hala -> rampa (Low/High) i osobno hala -> klatka schodowa.

var main: Node3D
var p
var f := 0
var room: Node3D
var stage := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = [["res://rooms/ramp.tscn", "East", "Low"]]
	if "--stairwell" in OS.get_cmdline_user_args():
		main.map_layout = [["res://rooms/stairwell.tscn", "East", "Low"]]
	root.add_child.call_deferred(main)

func _face(local_dir: Vector3) -> void:
	var d: Vector3 = room.global_transform.basis * local_dir
	p.rotation.y = atan2(-d.x, -d.z)

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		room = main.rooms[1]
		p = main.get_node("Players/1")
	if f == 10:
		p.global_position = room.to_global(Vector3(-4.3, 0.05, 0) if room.name.ends_with("Ramp") else Vector3(-2.3, 0.05, -1.25))
		_face(Vector3(1, 0, 0))
		Input.action_press("move_forward")
	if f > 10 and f % 30 == 0:
		log.append("t=%.1f lokalnie=%s" % [(f - 10) / 60.0, room.to_local(p.global_position).snapped(Vector3.ONE * 0.1)])
	if room and room.name.ends_with("Stairwell") and stage == 0 and f > 10 and room.to_local(p.global_position).x > 2.4:
		stage = 1
		_face(Vector3(0, 0, 1))  # na półpiętrze: skręt w stronę drugiego biegu
	if stage == 1 and room.to_local(p.global_position).z > 1.2:
		stage = 2
		_face(Vector3(-1, 0, 0))  # drugi bieg w górę, z powrotem na zachód
	if f == 10 + 60 * 6:
		print("%s: %s" % [room.name, ", ".join(log)])
		return true
	return false
