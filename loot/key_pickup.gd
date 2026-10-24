class_name KeyPickup
extends Area3D
## Klucz: otwiera dowolne zakluczone drzwi (zużywa się). Jak kupka monet: spawnuje i zbiera
## host, klienci dostają go przez MultiplayerSpawner. Lekko świeci, żeby dało się go dostrzec.

const COLOR := Color(0.85, 0.8, 0.55)


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
	if game_state.is_up(peer_id):
		game_state.add_key(peer_id)
		queue_free()


func _build_visual() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 0.4
	# Ucho klucza (pierścień), trzon i dwa ząbki.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.05
	ring.outer_radius = 0.09
	ring.material = material
	var parts := [[ring, Vector3(0, 0.35, -0.16), Vector3(PI / 2, 0, 0)]]
	for spec in [[Vector3(0.03, 0.03, 0.26), Vector3(0, 0.35, 0.02)], [Vector3(0.03, 0.06, 0.03), Vector3(0, 0.31, 0.1)], [Vector3(0.03, 0.05, 0.03), Vector3(0, 0.315, 0.05)]]:
		var box := BoxMesh.new()
		box.size = spec[0]
		box.material = material
		parts.append([box, spec[1], Vector3.ZERO])
	for part in parts:
		var instance := MeshInstance3D.new()
		instance.mesh = part[0]
		instance.position = part[1]
		instance.rotation = part[2]
		$Visual.add_child(instance)
