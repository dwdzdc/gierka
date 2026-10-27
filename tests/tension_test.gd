extends SceneTree
# Napięcie: wartość zagrożenia przy różnych odległościach potwora, skok po fałszywym alarmie.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var f := 0
var m
var t
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		m.set_physics_process(false)
		t = main.get_node("TensionAudio")
		main.get_node("Players/1").global_position = Vector3(-5, 0.05, 1.5)
	if f == 3:
		m.global_position = Vector3(30, 0.05, 0)  # daleko
	if f == 100:
		m.state = m.State.HUNT  # pościg 35 m dalej: bez akcentu
	if f == 105:
		log.append("pościg 35 m dalej: akcent %s" % ("ZLE, gra" if t.get_node("Stinger").playing else "OK, cisza"))
		m.state = m.State.PATROL
	if f == 240:
		log.append("potwór 35 m: zagrożenie %.2f, serce %.0f dB" % [t.threat, t.get_node("Heartbeat").volume_db])
		m.global_position = Vector3(1, 0.05, 1.5)  # 6 m
	if f == 480:
		log.append("potwór 6 m (patrol): zagrożenie %.2f, serce %.0f dB, ambient %.0f dB" % [t.threat, t.get_node("Heartbeat").volume_db, t.get_node("Ambient").volume_db])
		m.state = m.State.HUNT
	if f == 485:
		log.append("pościg 6 m: akcent %s" % ("OK, gra" if t.get_node("Stinger").playing else "ZLE, cisza"))
	if f == 720:
		log.append("potwór 6 m (pościg): zagrożenie %.2f, oddech %.0f dB" % [t.threat, t.get_node("Breath").volume_db])
		m.global_position = Vector3(30, 0.05, 0)
		m.state = m.State.PATROL
	if f == 1200:
		log.append("potwór odszedł (8 s): zagrożenie %.2f" % t.threat)
		main.get_node("FakeAlarms")._play("steps", Vector3(-1, 1, 1.5))
	if f == 1290:
		log.append("fałszywe kroki 4 m obok: zagrożenie %.2f" % t.threat)
		print("\n".join(log))
		return true
	return false
