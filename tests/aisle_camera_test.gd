extends SceneTree
# Zgłoszony przypadek: gracz wraca środkową alejką magazynu w stronę drzwi.
# Oczekiwane ujęcie: Storage/MiddleAisle (kamera z tyłu, widać, co przed postacią).

var main: Node3D
var p
var director
var frames := 0
var cases := [
	# [start, kierunek obrotu y]: wejście ze wschodniego końca blisko regału B i blisko regału A
	[Vector3(28.3, 0.05, 2.4), Vector3(21, 0.05, 1.7)],
	[Vector3(28.3, 0.05, -2.2), Vector3(21, 0.05, -1.2)],
	[Vector3(28.3, 0.05, 0.3), Vector3(21, 0.05, 0.3)],
]
var idx := 0
var shots := []
var at_mid := ""

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		p = main.get_node("Players/1")
		director = main.get_node("CameraDirector")
		director.camera_changed.connect(func(z): shots.append(z.name))
	if frames < 2:
		return false
	var local := (frames - 2) % 400
	# Kamera w chwili, gdy gracz jest w połowie alejki (x=24) i w połowie drogi do jej końca (x=22.5).
	if director.current_zone == null:
		return false
	if p.global_position.x < 24.0 and at_mid == "":
		at_mid = director.current_zone.name
	if p.global_position.x < 22.5 and at_mid.find("/") == -1 and at_mid != "":
		at_mid += "/" + director.current_zone.name
	if local == 0:
		if idx > 0:
			var ok := at_mid == "MiddleAisle/MiddleAisle"
			print("%s start=%s ujęcia=%s w alejce (x=24/x=22.5)=%s" % ["OK " if ok else "ZLE", cases[idx - 1][0], shots, at_mid])
		at_mid = ""
		if idx >= cases.size():
			return true
		Input.action_release("move_forward")
		shots.clear()
		p.global_position = cases[idx][0]
		idx += 1
	if local == 20:
		# Obróć się w stronę celu i idź prosto przed siebie (wzdłuż alejki na zachód).
		var target: Vector3 = cases[idx - 1][1]
		var dir: Vector3 = target - p.global_position
		p.rotation.y = atan2(-dir.x, -dir.z)
		Input.action_press("move_forward")
	if local == 200:
		Input.action_release("move_forward")
		p.rotation.y = PI / 2  # dalej na zachód, wzdłuż alejki
		Input.action_press("move_forward")
	return false
