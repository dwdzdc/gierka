extends ColorRect
## Zakłócenie obrazu (48), lokalnie u każdego gracza: potwór blisko i w kadrze bieżącej kamery.
## Zamiennik „nie patrz na potwora” z Amnesii przy stałej kamerze: patrzy kamera, nie postać,
## więc zakłóca się obraz, a nie zmysły postaci. Mocniej, im bliżej.

const RADIUS := 8.0
const RISE_PER_SECOND := 3.0
const FALL_PER_SECOND := 1.5

var amount := 0.0


func _process(delta: float) -> void:
	var target := _target_amount()
	amount = move_toward(amount, target, (RISE_PER_SECOND if target > amount else FALL_PER_SECOND) * delta)
	(material as ShaderMaterial).set_shader_parameter(&"glitch", amount)


func _target_amount() -> float:
	var director := get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	var camera := get_viewport().get_camera_3d()
	if director == null or camera == null or not is_instance_valid(director.target):
		return 0.0
	var best := 0.0
	for node in get_tree().get_nodes_in_group(&"monsters"):
		var monster := node as Monster
		if monster.state in [Monster.State.VENT, Monster.State.VENT_CLIMB]:
			continue
		var distance := monster.global_position.distance_to(director.target.global_position)
		if distance >= RADIUS:
			continue
		var chest := monster.global_position + Vector3.UP * 1.2
		if not camera.is_position_in_frustum(chest):
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, chest, 1)
		if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue  # zasłonięty ścianą: w kadrze go nie widać
		best = maxf(best, 1.0 - distance / RADIUS)
	return best
