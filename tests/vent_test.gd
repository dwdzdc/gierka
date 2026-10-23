extends SceneTree
# Wentylacja: łowca w magazynie dostaje polecenie przejścia do hali szybami.
# Oczekiwane: podchodzi pod kratkę, znika (VENT), przesuwa się, zeskakuje w hali.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var f := 0
var m
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("Players/1").global_position = Vector3(-5, 0.05, -4)
		main.get_node("Players/1").flashlight.visible = false
		m = main.get_node("Monsters").get_child(0)
		m.global_position = Vector3(34.8, 0.05, 0)
		m.state_changed.connect(func(s): log.append("t=%.1f %s pos=%s widoczny=%s" % [f / 60.0, m.State.keys()[s], m.global_position.snapped(Vector3.ONE * 0.1), m.get_node("Body").visible]))
	if f == 30:
		log.append("polecenie: do hali szybem -> %s" % m.vent_travel_to(main.rooms[0]))
	if f == 60 * 20:
		log.append("koniec: pos=%s (hala ma środek w 0,0,0)" % m.global_position.snapped(Vector3.ONE * 0.1))
		print("\n".join(log))
		return true
	return false
