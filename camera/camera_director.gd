class_name CameraDirector
extends Node
## Wybiera aktywne ujęcie dla JEDNEGO, lokalnego gracza. Działa tylko na kliencie
## i nie jest replikowany: każdy gracz w co-opie ma własnego dyrektora.
##
## Reguły, od najważniejszej:
## 1. Strefy. Dopóki gracz stoi w strefie bieżącej kamery, kamera się nie zmienia
##    (histereza), chyba że wejdzie w strefę o wyższym `camera_priority`.
## 2. Remis przy wyjściu ze strefy: wygrywa kamera, która lepiej pokrywa stożek
##    widzenia postaci. Liczone tylko gdy trzeba zmienić strefę, więc obrót w miejscu nie tnie.
## 3. Minimalny czas ujęcia: zwykłe cięcie czeka, aż ujęcie potrwa `min_shot_time`
##    (chyba że postaci w nim nie widać). Częste skakanie kamer utrudnia orientację.
## 4. Bezpiecznik: jeśli postaci nie widać w bieżącym ujęciu dłużej niż
##    `occlusion_grace`, przełączamy na kamerę z tego samego pokoju, która ją widzi.

signal camera_changed(zone: CameraZone)

@export var occlusion_grace := 0.5
@export var min_shot_time := 1.2
## Przeszkody dla raycastów widoczności (warstwa "world").
@export_flags_3d_physics var occluder_mask := 1

const _TARGET_POINTS: Array[float] = [1.5, 0.7]  # wysokości (głowa, biodra), z których liczy się "widać postać"
const _CONE_DISTANCES: Array[float] = [1.0, 2.5, 4.0]
const _CONE_ANGLES: Array[float] = [-0.5, 0.0, 0.5]  # rad, ok. ±30°

var target: Node3D
var current_zone: CameraZone
var _zones: Array[CameraZone] = []  # strefy, w których stoi target, w kolejności wejścia
var _hidden_time := 0.0
var _shot_time := 0.0  # ile sekund trwa bieżące ujęcie
var _guard_shot := false  # bieżące ujęcie wybrał bezpiecznik (strefa, w której gracza nie ma)
var _held_camera: Camera3D  # wymuszone ujęcie (np. widok z wnętrza szafki); strefy wtedy nie działają


func _ready() -> void:
	add_to_group(&"camera_director")


## Wymuszone ujęcie (np. przez szpary szafki). Strefy i bezpiecznik czekają do `release_hold`.
func hold_camera(camera: Camera3D) -> void:
	_held_camera = camera
	camera.make_current()


func release_hold() -> void:
	_held_camera = null
	set_target(target)  # wybierz ujęcie od nowa według stref
	# Postać mogła się nie ruszyć (podgląd przez kratkę drzwi): strefy, w których już stoi,
	# nie zgłoszą ponownego wejścia, więc szukamy ich same.
	if is_instance_valid(target) and target is PhysicsBody3D:
		for zone in get_tree().get_nodes_in_group(&"camera_zones"):
			if zone.overlaps_body(target):
				on_zone_entered(zone, target)


func set_target(new_target: Node3D) -> void:
	target = new_target
	_zones.clear()
	current_zone = null
	_hidden_time = 0.0
	_guard_shot = false


func on_zone_entered(zone: CameraZone, body: Node3D) -> void:
	if body != target:
		return
	_zones.erase(zone)
	_zones.append(zone)
	if current_zone == null:
		_activate(zone)  # pierwsze ujęcie od razu


func on_zone_exited(zone: CameraZone, body: Node3D) -> void:
	if body != target:
		return
	_zones.erase(zone)


func _physics_process(delta: float) -> void:
	if _held_camera or target == null or not is_instance_valid(current_zone):
		return
	_shot_time += delta
	var visible_now := is_target_visible(current_zone.camera)
	var desired := _desired_zone()
	if desired != current_zone and (_shot_time >= min_shot_time or not visible_now):
		_activate(desired)
		return
	if visible_now:
		_hidden_time = 0.0
		return
	_hidden_time += delta
	if _hidden_time < occlusion_grace:
		return
	_hidden_time = 0.0
	var nearby: Array[CameraZone] = _zones.duplicate()
	nearby.append(current_zone)
	var candidates: Array[CameraZone] = []
	for zone in _zones_in_rooms_of(nearby):
		if zone != current_zone and is_target_visible(zone.camera):
			candidates.append(zone)
	var best := _pick_best(candidates, false)
	if best:
		_activate(best)
		_guard_shot = not _zones.has(best)


## Ujęcie wynikające ze stref (reguły 1–2). Bez zmian, jeśli nie ma powodu ciąć.
func _desired_zone() -> CameraZone:
	if _zones.is_empty():
		return current_zone  # poza strefami zostajemy przy ostatnim ujęciu
	if not _zones.has(current_zone):
		var best := _pick_best(_zones)
		# Ujęcie z bezpiecznika oddaje kontrolę dopiero, gdy kamera własnej strefy widzi gracza.
		# Inaczej obca kamera "przyklejałaby się" aż do wejścia w kolejną strefę.
		if _guard_shot and not is_target_visible(best.camera):
			return current_zone
		return best
	for zone in _zones:
		if zone.camera_priority > current_zone.camera_priority:
			return _pick_best(_zones)
	return current_zone


## Widać postać, jeśli jest w kadrze i przynajmniej jeden jej punkt nie jest zasłonięty.
func is_target_visible(camera: Camera3D) -> bool:
	var scale := 0.55 if target is Player and target.crouching else 1.0  # kucająca postać jest niższa
	for height in _TARGET_POINTS:
		var point := target.global_position + Vector3.UP * height * scale
		if camera.is_position_in_frustum(point) and _line_clear(camera.global_position, point):
			return true
	return false


## Ile punktów ze stożka przed postacią widać z danej kamery (0–9).
func cone_score(camera: Camera3D) -> int:
	var eye := target.global_position + Vector3.UP * 1.2
	var forward := -target.global_transform.basis.z
	var score := 0
	for angle in _CONE_ANGLES:
		var dir := forward.rotated(Vector3.UP, angle)
		for dist in _CONE_DISTANCES:
			var point := eye + dir * dist
			# Punkt za ścianą (postać go nie widzi) się nie liczy.
			if not _line_clear(eye, point):
				break
			if camera.is_position_in_frustum(point) and _line_clear(camera.global_position, point):
				score += 1
	return score


func _pick_best(zones: Array[CameraZone], require_visible := true) -> CameraZone:
	var best: CameraZone = null
	var best_score := -1
	for zone in zones:
		if require_visible and not is_target_visible(zone.camera):
			continue
		var score := cone_score(zone.camera)
		if best == null or zone.camera_priority > best.camera_priority \
				or (zone.camera_priority == best.camera_priority and score >= best_score):
			best = zone
			best_score = score
	# Jeśli żadna strefa nie widzi postaci, i tak wybierz najlepszą z dostępnych.
	if best == null and require_visible and not zones.is_empty():
		return _pick_best(zones, false)
	return best


func _zones_in_rooms_of(zones: Array[CameraZone]) -> Array[CameraZone]:
	var result: Array[CameraZone] = []
	for zone in zones:
		var holder := zone.get_parent()
		for sibling in holder.get_children():
			if sibling is CameraZone and not result.has(sibling):
				result.append(sibling)
	return result


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, occluder_mask)
	return target.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _activate(zone: CameraZone) -> void:
	current_zone = zone
	_hidden_time = 0.0
	_shot_time = 0.0
	_guard_shot = false
	zone.camera.activate(target)
	camera_changed.emit(zone)
