class_name CoinPile
extends Area3D
## Kupka monet. Spawnuje ją i zbiera wyłącznie host (wejście sprawnego gracza w obszar);
## klienci dostają ją przez MultiplayerSpawner i widzą tylko wygląd.

const COIN_MESH_HEIGHT := 0.035

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
	var stacks := clampi(value / 12 + 1, 1, 6)
	for i in stacks:
		var height := rng.randi_range(2, 6)
		var stack := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.09
		mesh.height = COIN_MESH_HEIGHT * height
		mesh.radial_segments = 8
		mesh.rings = 1
		mesh.material = preload("res://loot/gold.tres")
		stack.mesh = mesh
		var angle := TAU * i / stacks + rng.randf() * 0.5
		var radius := 0.0 if i == 0 else 0.18
		stack.position = Vector3(cos(angle) * radius, mesh.height / 2.0, sin(angle) * radius)
		$Visual.add_child(stack)
