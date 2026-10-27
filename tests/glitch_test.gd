extends SceneTree
# Zakłócenie obrazu (48): potwór blisko i w kadrze = glitch; daleko albo za ścianą = czysto.

const Maps = preload("res://tests/test_maps.gd")
var main
var f := 0
var m
var glitch
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _check(cond: bool, what: String) -> void:
	log.append("%s  %s (glitch %.2f)" % ["OK " if cond else "ZLE", what, glitch.amount])

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		glitch = main.get_node("PostProcess/Retro")
		main.get_node("Players/1").global_position = Vector3(-4, 0.05, 1)
		m.global_position = Vector3(-1, 0.05, 1)
	if f == 4:
		m.set_physics_process(false)
	if f == 60:
		_check(glitch.amount > 0.4, "potwór 3 m w kadrze")
		m.global_position = Vector3(30, 0.05, 0)  # magazyn: za ścianami, 34 m
	if f == 160:
		_check(glitch.amount == 0.0, "potwór daleko za ścianami")
		print("\n".join(log))
		return true
	return false
