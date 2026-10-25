class_name BatteryPickup
extends Area3D
## Bateria do latarki (41c): doładowuje część baterii. Jak klucz: spawnuje i zbiera host,
## klienci dostają ją przez MultiplayerSpawner. Lekko świeci, żeby dało się ją dostrzec.

const COLOR := Color(0.55, 0.85, 0.45)


func _ready() -> void:
	_build_visual()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	$Visual.rotate_y(delta * 1.5)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	var peer_id := body.get_multiplayer_authority()
	# Pełna bateria: zostaw dla kolegi.
	if game_state.is_up(peer_id) and game_state.battery(peer_id) < GameState.BATTERY_MAX:
		game_state.add_battery(peer_id)
		queue_free()


func _build_visual() -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = COLOR
	body_material.emission_enabled = true
	body_material.emission = COLOR
	body_material.emission_energy_multiplier = 0.35
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.75, 0.75, 0.75)
	cap_material.metallic = 0.8
	# Gruba bateria typu D: walec i metalowy biegun na górze.
	var cell := CylinderMesh.new()
	cell.top_radius = 0.07
	cell.bottom_radius = 0.07
	cell.height = 0.24
	cell.material = body_material
	var cap := CylinderMesh.new()
	cap.top_radius = 0.025
	cap.bottom_radius = 0.025
	cap.height = 0.03
	cap.material = cap_material
	for part in [[cell, Vector3(0, 0.3, 0)], [cap, Vector3(0, 0.435, 0)]]:
		var instance := MeshInstance3D.new()
		instance.mesh = part[0]
		instance.position = part[1]
		$Visual.add_child(instance)
