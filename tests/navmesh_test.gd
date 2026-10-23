extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Sprawdza, że NavMesh się wypiekł i że da się znaleźć ścieżkę z hali na koniec magazynu.

var main: Node3D
var frames := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
	if frames < 30:
		return false
	var region: NavigationRegion3D = main.get_node("Navigation")
	var polys := region.navigation_mesh.get_polygon_count()
	var map := region.get_navigation_map()
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(-3, 0, 0))
	var to := NavigationServer3D.map_get_closest_point(map, Vector3(28.8, 0, 5))
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	var ys := []
	for i in 20:
		ys.append(snappedf(NavigationServer3D.map_get_random_point(map, 1, false).y, 0.1))
	print("polygons=%d path_points=%d path_len=%.1f end=%s random_y=%s" % [polys, path.size(), length, to.snapped(Vector3.ONE * 0.1), ys])
	return true
