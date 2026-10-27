extends SceneTree
# 47f, nauka: ucieczki na inne piętro. Mapa: hala -> rampa (dół = hala, góra +5 m).
# Pierwsza ucieczka zawsze się udaje (potwór szuka na dole); potem coraz częściej szuka na piętrze
# gracza i wchodzi po rampie.

var main: Node3D
var f := 0
var m
var p
var director
var upstairs := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = [["res://rooms/ramp.tscn", "East", "Low"]]
	root.add_child.call_deferred(main)

func _lose_once() -> bool:
	m._prey = p
	m.last_seen_position = m.global_position + Vector3(1, 0, 0)
	m._lose_prey()
	return m._search_center.y > m.global_position.y + 2.0

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		director = main.get_node("MonsterDirector")
		m = main.get_node("Monsters").get_child(0)
		p = main.get_node("Players/1")
		var high: Marker3D = main.rooms[1].get_node("Doorways/High")
		p.global_position = high.global_position + high.global_transform.basis.z * 1.5 + Vector3.UP * 0.05
		m.global_position = Vector3(2, 0.05, 0)  # w hali, na dole
	if f == 40:
		log.append("gracz y=%.1f, potwór y=%.1f" % [p.global_position.y, m.global_position.y])
		var first := _lose_once()
		log.append("%s  pierwsza ucieczka: szuka na dole (%s)" % ["OK " if not first else "ZLE", "piętro" if first else "dół"])
		for i in 30:
			if _lose_once():
				upstairs += 1
		log.append("kolejne 30 ucieczek: na piętrze %d razy, szansa teraz %.2f (oczekiwane ok. 20)" % [upstairs, director.floor_check_chance()])
		log.append("%s  z czasem szuka na piętrze" % ("OK " if upstairs >= 12 else "ZLE"))
		# Ostatnia decyzja na piętro: czy faktycznie tam dojdzie?
		while not _lose_once():
			pass
	if f > 40 and f % 120 == 0:
		log.append("t=%.0f potwór y=%.1f stan %s" % [(f - 40) / 60.0, m.global_position.y, m.State.keys()[m.state]])
	if f == 40 + 60 * 14:
		log.append("%s  wszedł na piętro gracza" % ("OK " if m.global_position.y > 3.0 else "ZLE"))
		print("\n".join(log))
		return true
	return false
