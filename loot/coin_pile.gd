class_name CoinPile
extends Area3D
## Kupka monet. Spawnuje ją i zbiera wyłącznie host (wejście sprawnego gracza w obszar);
## klienci dostają ją przez MultiplayerSpawner i widzą tylko wygląd.

const COIN_MESH_HEIGHT := 0.035
## Wygląd zależny od wartości: więcej monet = więcej słupków (1-6), każdy 2-6 monet wysoki.
const VALUE_PER_STACK := 12
const MAX_STACKS := 6
const STACK_HEIGHT_RANGE := Vector2i(2, 6)
const STACK_RADIUS := 0.09
const STACK_RADIAL_SEGMENTS := 8
const STACK_ANGLE_JITTER := 0.5
const STACK_OUTER_RADIUS := 0.18  # pierwszy słupek na środku, reszta wokół

## Ustawiane przed dodaniem do drzewa; replikowane przy spawnie (wygląd zależy od wartości).
@export var value := 10


func _ready() -> void:
	_build_visual()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	var game_state: GameState = get_tree().get_first_node_in_group(&"game_state")
	var peer_id := body.get_multiplayer_authority()
	if game_state.is_up(peer_id):
		game_state.add_coins(peer_id, value, global_position)
		queue_free()


## Im większa wartość, tym więcej słupków monet (1-6). Losowy, ale stały dla danej kupki układ.
func _build_visual() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var stacks := clampi(value / VALUE_PER_STACK + 1, 1, MAX_STACKS)
	for i in stacks:
		var height := rng.randi_range(STACK_HEIGHT_RANGE.x, STACK_HEIGHT_RANGE.y)
		var stack := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = STACK_RADIUS
		mesh.bottom_radius = STACK_RADIUS
		mesh.height = COIN_MESH_HEIGHT * height
		mesh.radial_segments = STACK_RADIAL_SEGMENTS
		mesh.rings = 1
		mesh.material = preload("res://loot/gold.tres")
		stack.mesh = mesh
		var angle := TAU * i / stacks + rng.randf() * STACK_ANGLE_JITTER
		var radius := 0.0 if i == 0 else STACK_OUTER_RADIUS
		stack.position = Vector3(cos(angle) * radius, mesh.height / 2.0, sin(angle) * radius)
		$Visual.add_child(stack)
