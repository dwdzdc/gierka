extends SceneTree
# Jak szybko kamery obracają się za graczem (59). Dla każdej strefy każdego pokoju: gracz w
# punktach siatki 0,5 m biegnie (4,6 m/s) w 8 kierunkach; liczymy prędkość obrotu kamery
# (kierunek `aim_point`, z limitem `max_turn`, bez wygładzania, czyli z zapasem).
# Miarą jest 90. percentyl próbek strefy, nie maksimum: tuż pod kamerą obrót zawsze jest szybki,
# ale tam postaci i tak nie widać (bezpiecznik tnie na inną kamerę).
# Strefa ponad progiem = kamera musiałaby się kręcić za szybko, czyli w tym miejscu powinna
# patrzeć inna kamera (podział strefy albo przesunięcie kamery w tools/gen_rooms.py).
#   godot --headless --path . -s tests/camera_turn_test.gd [-- --limit=150 --scale=0.5]

const RUN := 4.6
const DT := 0.1
var limit := 150.0  # °/s; wygładzanie kamery (follow_smoothing) i tak go łagodzi
var scale := 1.0  # --scale=0.5: porównanie ze słabszym `follow`


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--limit="):
			limit = arg.trim_prefix("--limit=").to_float()
		elif arg.begins_with("--scale="):
			scale = arg.trim_prefix("--scale=").to_float()
	var worst := 0.0
	var over := []
	var files := Array(DirAccess.get_files_at("res://rooms")).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
	for file in files:
		var room: Node3D = load("res://rooms/" + file).instantiate()
		root.add_child(room)
		var zones := room.get_node_or_null("CameraZones")
		if zones == null:
			room.free()
			continue
		for zone in zones.get_children():
			var cam = zone.get_node("Camera")
			cam.follow_target = null
			cam.follow *= scale
			var rates: Array[float] = []
			var shape: CollisionShape3D = zone.get_node("Shape")
			var size: Vector3 = (shape.shape as BoxShape3D).size
			var center: Vector3 = shape.global_position
			var x := -size.x / 2.0 + 0.25
			while x < size.x / 2.0:
				var z := -size.z / 2.0 + 0.25
				while z < size.z / 2.0:
					var p := center + Vector3(x, -size.y / 2.0 + 0.05, z)
					var aim0: Vector3 = (cam.aim_point(p) - cam.global_position).normalized()
					var fastest := 0.0
					for i in 8:
						var step := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 4.0) * RUN * DT
						var aim1: Vector3 = (cam.aim_point(p + step) - cam.global_position).normalized()
						fastest = maxf(fastest, rad_to_deg(aim0.angle_to(aim1)) / DT)
					rates.append(fastest)
					z += 0.5
				x += 0.5
			rates.sort()
			var top: float = rates[int(rates.size() * 0.9)] if not rates.is_empty() else 0.0
			worst = maxf(worst, top)
			if top > limit:
				over.append("%s/%s: %.0f°/s (follow %.2f)" % [file.get_basename(), zone.name, top, cam.follow])
		room.free()
	print("najszybszy obrót (90. percentyl strefy): %.0f°/s (próg %.0f°/s)" % [worst, limit])
	for line in over:
		print("ZA SZYBKO  ", line)
	print("WYNIK: ", "OK" if over.is_empty() else "BŁĄD")
	quit(0 if over.is_empty() else 1)
