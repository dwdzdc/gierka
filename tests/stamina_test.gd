extends SceneTree
# Wytrzymałość (47g): bieg kończy się po ~6 s zadyszką (marsz, dyszenie = hałas dla potworów),
# potem wolna regeneracja i powrót biegu.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var p
var f := 0
var breath_noises := 0
var winded_at := -1.0
var walk_speed_when_winded := 0.0
var recovered_at := -1.0
var last_pos := Vector3.ZERO
var ok := true

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).set_physics_process(false)
		p = main.get_node("Players/1")
		p.global_position = Vector3(0, 0.05, 0)
		root.get_node("NoiseBus").noise_made.connect(func(_pos, r, src): if src == p and is_equal_approx(r, p.WINDED_NOISE_RADIUS): breath_noises += 1)
	if f == 10:
		# Bieg w kółko (promień ~1,6 m), żeby nie wbiec w ścianę hali.
		Input.action_press("move_forward")
		Input.action_press("move_left")
		Input.action_press("run")
	var t := (f - 10) / 60.0
	if f > 10:
		var speed: float = ((p.global_position - last_pos) * Vector3(1, 0, 1)).length() / d
		if p.winded and winded_at < 0.0:
			winded_at = t
		if winded_at > 0.0 and t > winded_at + 1.0 and t < winded_at + 1.1:
			walk_speed_when_winded = speed
		if winded_at > 0.0 and not p.winded and recovered_at < 0.0:
			recovered_at = t
	if p:  # w 1. klatce gracza jeszcze nie ma
		last_pos = p.global_position
	if f == 10 + 60 * 9:
		Input.action_release("move_forward")
		Input.action_release("move_left")
	if f == 10 + 60 * 16:
		Input.action_release("run")
		print("zadyszka po %.1f s biegu (oczekiwane ~6)" % winded_at)
		print("prędkość w zadyszce %.1f m/s (marsz %.1f)" % [walk_speed_when_winded, p.walk_speed])
		print("hałasy dyszenia: %d" % breath_noises)
		print("koniec zadyszki po %.1f s (oczekiwane ~6+1+4)" % recovered_at)
		ok = absf(winded_at - 6.0) < 0.3 and walk_speed_when_winded < p.walk_speed + 0.3 \
				and breath_noises >= 3 and recovered_at > 9.0 and recovered_at < 13.0
		print("OK" if ok else "FAIL")
		return true
	return false
