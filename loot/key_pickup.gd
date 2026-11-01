class_name KeyPickup
extends Area3D
## Klucz: otwiera dowolne zakluczone drzwi (zużywa się). Jak kupka monet: spawnuje i zbiera
## host, klienci dostają go przez MultiplayerSpawner. Lekko świeci, żeby dało się go dostrzec.

const COLOR := Color(0.85, 0.8, 0.55)
## Wygląd: lekki obrót, metal i poświata, żeby klucz było widać w ciemności.
const SPIN_SPEED := 1.5
const METALLIC := 0.8
const ROUGHNESS := 0.3
const EMISSION_ENERGY := 0.4
const RING_INNER_RADIUS := 0.05
const RING_OUTER_RADIUS := 0.09
## Ucho, trzon i dwa ząbki klucza.
const RING_POSITION := Vector3(0, 0.35, -0.16)
const SHAFT_SIZE := Vector3(0.03, 0.03, 0.26)
const SHAFT_POSITION := Vector3(0, 0.35, 0.02)
const TOOTH_LONG_SIZE := Vector3(0.03, 0.06, 0.03)
const TOOTH_LONG_POSITION := Vector3(0, 0.31, 0.1)
const TOOTH_SHORT_SIZE := Vector3(0.03, 0.05, 0.03)
const TOOTH_SHORT_POSITION := Vector3(0, 0.315, 0.05)


func _ready() -> void:
	_build_visual()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	$Visual.rotate_y(delta * SPIN_SPEED)


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
	material.metallic = METALLIC
	material.roughness = ROUGHNESS
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = EMISSION_ENERGY
	# Ucho klucza (pierścień), trzon i dwa ząbki.
	var ring := TorusMesh.new()
	ring.inner_radius = RING_INNER_RADIUS
	ring.outer_radius = RING_OUTER_RADIUS
	ring.material = material
	var parts := [[ring, RING_POSITION, Vector3(PI / 2, 0, 0)]]
	for spec in [[SHAFT_SIZE, SHAFT_POSITION], [TOOTH_LONG_SIZE, TOOTH_LONG_POSITION], [TOOTH_SHORT_SIZE, TOOTH_SHORT_POSITION]]:
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
