class_name CameraDirector
extends Node
## Wybiera aktywne ujęcie dla JEDNEGO, lokalnego gracza. Działa tylko na kliencie
## i nie jest replikowany: każdy gracz w co-opie ma własnego dyrektora.
##
## Reguły, od najważniejszej:
## 1. Strefy. Dopóki gracz stoi w strefie bieżącej kamery, kamera się nie zmienia
##    (histereza), chyba że wejdzie w strefę o wyższym `camera_priority`.
## 2. Remis przy wyjściu ze strefy: wygrywa kamera, która lepiej pokrywa stożek
##    widzenia postaci. Liczone tylko przy zdarzeniach stref, więc obrót w miejscu nie tnie.
## 3. Bezpiecznik: jeśli postaci nie widać w bieżącym ujęciu dłużej niż
##    `occlusion_grace`, przełączamy na kamerę z tego samego pokoju, która ją widzi.

signal camera_changed(zone: CameraZone)

@export var occlusion_grace := 0.5
## Przeszkody dla raycastów widoczności (warstwa "world").
@export_flags_3d_physics var occluder_mask := 1

const _TARGET_POINTS: Array[float] = [1.5, 0.7]  # wysokości (głowa, biodra), z których liczy się "widać postać"
const _CONE_DISTANCES: Array[float] = [1.0, 2.5, 4.0]
const _CONE_ANGLES: Array[float] = [-0.5, 0.0, 0.5]  # rad, ok. ±30°

var target: Node3D
var current_zone: CameraZone
var _zones: Array[CameraZone] = []  # strefy, w których stoi target, w kolejności wejścia
var _hidden_time := 0.0


func _ready() -> void:
	add_to_group(&"camera_director")


func set_target(new_target: Node3D) -> void:
	target = new_target
	_zones.clear()
	current_zone = null
	_hidden_time = 0.0


func on_zone_entered(zone: CameraZone, body: Node3D) -> void:
	if body != target:
		return
	_zones.erase(zone)
	_zones.append(zone)
	# Ujęcie z bezpiecznika (strefa, w której gracza nie ma) oddaje kontrolę przy pierwszej okazji.
	var overridden := current_zone != null and not _zones.has(current_zone)
	if current_zone == null or overridden or zone.camera_priority > current_zone.camera_priority:
		_activate(zone)


func on_zone_exited(zone: CameraZone, body: Node3D) -> void:
	if body != target:
		return
	_zones.erase(zone)
	if zone == current_zone:
		var best := _pick_best(_zones)
		# Poza wszystkimi strefami zostajemy przy ostatnim ujęciu, zamiast pokazać nic.
		if best:
			_activate(best)


func _physics_process(delta: float) -> void:
	if target == null or current_zone == null:
		return
	if is_target_visible(current_zone.camera):
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


## Widać postać, jeśli jest w kadrze i przynajmniej jeden jej punkt nie jest zasłonięty.
func is_target_visible(camera: Camera3D) -> bool:
	for height in _TARGET_POINTS:
		var point := target.global_position + Vector3.UP * height
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
	zone.camera.activate(target)
	camera_changed.emit(zone)
