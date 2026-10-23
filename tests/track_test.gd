extends SceneTree
# Potwór tropi krew: ranny gracz przeszedł z korytarza do kąta hali i tam leży powalony.
# Potwór startuje przy początku śladu w korytarzu, plecami do hali.

var main: Node3D
var m
var frames := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
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
		var path := [Vector3(12, 0, 0), Vector3(9, 0, 0), Vector3(6, 0, 0), Vector3(4, 0, 0.5), Vector3(2, 0, 1.5),
			Vector3(0, 0, 2.5), Vector3(-2, 0, 3.2), Vector3(-4, 0, 3.4)]
		for point in path:
			bt.drops.append({"position": point, "time": bt.now() - 20.0 + bt.drops.size()})
		p.global_position = Vector3(-4.3, 0.05, 3.5)
		gs.players[1].hp = 0
		gs.players[1].life = gs.Life.DOWNED
		gs.players[1].bleed_out = 999
		gs._broadcast()
		m = main.get_node("Monsters").get_child(0)
		m.global_position = Vector3(14, 0.05, 0)
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
