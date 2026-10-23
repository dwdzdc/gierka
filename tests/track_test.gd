extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Potwór tropi krew: ranny gracz przeszedł z korytarza do kąta hali i tam leży powalony.
# Potwór startuje przy początku śladu w korytarzu, plecami do hali.

var main: Node3D
var m
var frames := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	var t := frames - 2
	if t == 0:
		main._on_connected()
		var gs = main.get_node("GameState")
		var bt = main.get_node("BloodTrail")
		var p = main.get_node("Players/1")
		# Ślad: korytarz -> drzwi hali -> kąt hali. Krople coraz świeższe.
		var path := [Vector3(20, 0, 0), Vector3(15, 0, 0), Vector3(10, 0, 0), Vector3(7, 0, 0.5), Vector3(4, 0, 1.5),
			Vector3(0, 0, 2.5), Vector3(-3, 0, 3.2), Vector3(-6, 0, 4.5)]
		# Krople co ~0.7 m wzdłuż ścieżki, jak u prawdziwego krwawiącego gracza.
		for i in range(path.size() - 1):
			var steps := int(path[i].distance_to(path[i + 1]) / 0.7)
			for k in steps:
				var point: Vector3 = path[i].lerp(path[i + 1], float(k) / steps)
				bt.drops.append({"position": point, "time": bt.now() - 60.0 + bt.drops.size() * 0.5})
		p.global_position = Vector3(-6.5, 0.05, 4.8)
		gs.players[1].hp = 0
		gs.players[1].life = gs.Life.DOWNED
		gs.players[1].bleed_out = 999
		gs._broadcast()
		m = main.get_node("Monsters").get_child(0)
		m.global_position = Vector3(22, 0.05, 0)
		m.rotation.y = -PI / 2  # patrzy na +X, w głąb korytarza
		m.state_changed.connect(func(s): log.append("t=%.1f %s d=%.1f" % [(frames - 2) / 60.0, m.State.keys()[s], m.global_position.distance_to(p.global_position)]))
	if t > 0 and t % 60 == 0 and main.get_node("GameState").life(1) == 2 and not log[-1].begins_with("gracz"):
		log.append("gracz DEAD przy t=%.1f" % (t / 60.0))
	if t == 60 * 25:
		var gs = main.get_node("GameState")
		log.append("koniec: gracz %s" % gs.Life.keys()[gs.life(1)])
		print(", ".join(log))
		return true
	return false
