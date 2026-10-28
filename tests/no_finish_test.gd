extends SceneTree
# Łowca nie dobija powalonego (profil `finishes_downed = false`): stoi 2 m przed leżącym
# graczem 2, przodem do niego, przez 12 s; gracz 2 ma zostać powalony, a łowca ma odejść
# (nie wracać po świeżej kałuży i nie pilnować ciała).
# Kontrola (--case=control): ten sam łowca z `finishes_downed = true` dobija.
#   godot --headless --path . -s tests/no_finish_test.gd [-- --case=control]

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var m
var f := 0
var control := "--case=control" in OS.get_cmdline_user_args()


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)


func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		gs = main.get_node("GameState")
		main._spawn_player(2)
		gs.invulnerable[1] = true
		main.get_node("Players/1").global_position = Vector3(34, 0.05, 4)  # magazyn, daleko
		main.get_node("Players/2").global_position = Vector3(-2.5, 0.05, 0.3)
		m = main.get_node("Monsters").get_child(0)
		m.profile = m.profile.duplicate()
		m.profile.finishes_downed = control
		gs.damage(2, 200)
	if f == 4:
		m.global_position = Vector3(-2.5, 0.05, 2.3)
		m.look_at(Vector3(-2.5, 0.05, 0.3), Vector3.UP)
	if f == 4 + 60 * 12:
		var life: String = gs.Life.keys()[gs.life(2)]
		var away: float = m.global_position.distance_to(Vector3(-2.5, 0.05, 0.3))
		print("łowca (dobija=%s): profil %s, gracz 2 %s, łowca %.1f m od niego, stan %s" % [control, m.profile.id, life, away, m.State.keys()[m.state]])
		var ok: bool = life == "DEAD" if control else (life == "DOWNED" and away > 3.0)
		print("WYNIK: ", "OK" if ok else "BŁĄD")
		return true
	return false
