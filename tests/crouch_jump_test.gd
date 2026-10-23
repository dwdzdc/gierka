extends SceneTree
# Kucanie i skok: hałas kroków, wysokość skoku, hałas lądowania, wzrok potwora na kucającego.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var p
var f := 0
var noises := {"walk": [], "crouch": [], "jump": []}
var phase := ""
var max_y := 0.0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).set_physics_process(false)
		p = main.get_node("Players/1")
		p.global_position = Vector3(-6, 0.05, 1.5)
		root.get_node("NoiseBus").noise_made.connect(func(_pos, r, src): if src == p and phase != "": noises[phase].append(snappedf(r, 0.1)))
	if f == 10:
		phase = "walk"
		Input.action_press("move_forward")
	if f == 130:
		phase = "crouch"
		Input.action_press("crouch")
	if f == 250:
		Input.action_release("move_forward")
		Input.action_release("crouch")
	if f == 280:
		log.append("kucanie: wysokość kapsuły %.2f -> po puszczeniu %.2f" % [1.0, p.get_node("Shape").shape.height])
		phase = "jump"
		max_y = p.global_position.y
		Input.action_press("jump")
	if f > 280 and f < 400:
		max_y = maxf(max_y, p.global_position.y)
	if f == 282:
		Input.action_release("jump")
	if f == 400:
		log.append("skok: maks. wysokość %.2f m" % (max_y - 0.05))
		var m = main.get_node("Monsters").get_child(0)
		m.global_position = p.global_position + Vector3(4.5, 0, 0)
		m.look_at(p.global_position, Vector3.UP)
		p.flashlight.visible = false
		log.append("potwór 4.5 m, gracz stoi: widzi=%s" % m.can_see(p))
		p.crouching = true
		log.append("potwór 4.5 m, gracz kuca: widzi=%s (zasięg w ciemności 6 m x 0.6)" % m.can_see(p))
		for k in noises:
			log.append("%s: %s" % [k, noises[k]])
		print("\n".join(log))
		return true
	return false
