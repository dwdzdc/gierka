extends SceneTree
# Biblioteka (15r): po antresoli da się obejść całą rotundę. Dla każdego narożnika ścieżka
# NavMesh między środkami sąsiednich pasów antresoli musi iść przez ten narożnik (krótko),
# a nie objazdem przez trzy pozostałe. NavMesh liczony dla potwora (promień 0,5 m), więc
# przejście dla niego jest też przejściem dla gracza (0,35 m).

const MEZZ := 3.6
var main: Node3D
var frames := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = [["res://rooms/library.tscn", "East", "West"]]
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
	if frames < 40:
		return false
	var library: Node3D = main.rooms[1]
	var map: RID = main.get_node("Navigation").get_navigation_map()
	var strips := {"N": Vector3(0, MEZZ, -8.3), "S": Vector3(0, MEZZ, 8.3), "W": Vector3(-8.3, MEZZ, 0), "E": Vector3(8.3, MEZZ, 0)}
	var bad := 0
	for pair in [["N", "W"], ["N", "E"], ["S", "W"], ["S", "E"]]:
		var from := NavigationServer3D.map_get_closest_point(map, library.to_global(strips[pair[0]]))
		var to := NavigationServer3D.map_get_closest_point(map, library.to_global(strips[pair[1]]))
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		# Przez narożnik ~15 m, objazd przez trzy pozostałe ~45 m.
		# Ścieżka kończy się w celu (bez przejścia map_get_path zwraca drogę do najbliższego punktu)
		# i biegnie górą (NavMesh leży trochę nad bryłą antresoli).
		var ok := path.size() > 1 and path[-1].distance_to(to) < 0.3 and length < 20.0 \
				and absf(library.to_local(from).y - MEZZ) < 0.7
		if not ok:
			bad += 1
		print("%s  %s-%s: %.1f m  %s -> %s" % ["OK " if ok else "ZLE", pair[0], pair[1], length, library.to_local(from).snapped(Vector3.ONE * 0.1), library.to_local(to).snapped(Vector3.ONE * 0.1)])
	print("PROBLEMY: %d" % bad)
	return true
