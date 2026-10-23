extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Statyczne scenariusze percepcji: potwór stoi w miejscu (AI wyłączone), gracz w różnych pozycjach.

var main: Node3D
var m
var p
var frames := 0
var heard_count := 0
var cases := [
	# [opis, pozycja gracza, latarka, oczekiwane widzi]
	["przed potworem 4 m, ciemno", Vector3(22.8, 0.05, 0), false, true],
	["przed potworem 10 m, ciemno", Vector3(16.8, 0.05, 0), false, false],
	["przed potworem 10 m, latarka", Vector3(16.8, 0.05, 0), true, true],
	["za plecami 2.5 m", Vector3(29.3, 0.05, 0), false, false],
	["w stożku, 5.4 m, za regałem", Vector3(22.3, 0.05, -3.0), false, false],
	["w stożku, 5.4 m, bez zasłony", Vector3(22.3, 0.05, 1.0), false, true],
]
var idx := -1

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		m = main.get_node("Monsters").get_child(0)
		p = main.get_node("Players/1")
		m.set_physics_process(false)  # tylko percepcja, bez ruchu
		m.global_position = Vector3(26.8, 0.05, 0)
		m.rotation.y = PI / 2  # patrzy w stronę -X (do wejścia)
		m.heard.connect(func(_pos): heard_count += 1)
	if frames < 2:
		return false
	if frames % 20 == 3:
		if idx >= 0:
			m._sight_timer = 0.0
			m._update_sight(0.0)
			var c = cases[idx]
			var ok: bool = (m.seen_player != null) == c[3]
			print("%s %s: widzi=%s" % ["OK " if ok else "ZLE", c[0], m.seen_player != null])
		idx += 1
		if idx >= cases.size():
			# Słuch: hałas 10 m z odległości 8 m (słychać) i 4 m z odległości 8 m (nie słychać).
			var bus = root.get_node("NoiseBus")
			bus.emit_noise(Vector3(18.8, 0, 0), 10.0, null)
			bus.emit_noise(Vector3(18.8, 0, 0), 4.0, null)
			print("%s słuch: usłyszał %d z 2 (oczekiwane 1)" % ["OK " if heard_count == 1 else "ZLE", heard_count])
			return true
		var c = cases[idx]
		p.global_position = c[1]
		p.flashlight.visible = c[2]
	return false
