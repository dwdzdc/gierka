@tool
class_name FixedCamera
extends Camera3D
## Nieruchome ujęcie w stylu RE. Pozycja jest stała, kamera celuje w `look_target`
## (współrzędne lokalne rodzica, czyli strefy). Gdy `follow > 0`, obraca się
## lekko za graczem, ale nigdy nie zmienia pozycji.

@export var look_target := Vector3.ZERO:
	set(value):
		look_target = value
		if is_inside_tree():
			_aim(_base_point())
## 0 = statyczna, 1 = patrzy prosto na gracza. Wartości pośrednie dają lekki "pan".
@export_range(0.0, 1.0) var follow := 0.0
@export var follow_smoothing := 4.0

var follow_target: Node3D
var _shake := 0.0


func _ready() -> void:
	_aim(_base_point())


func activate(target: Node3D) -> void:
	follow_target = target
	make_current()
	# Po cięciu ustawiamy kąt od razu, żeby nie było widać "dojeżdżania".
	_aim(_goal_point())


## Krótki wstrząs obrazu (np. po trafieniu). Przesuwa tylko obraz, nie pozycję kamery.
func shake(strength := 0.15) -> void:
	_shake = maxf(_shake, strength)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not current:
		return
	_shake = move_toward(_shake, 0.0, delta * 0.5)
	h_offset = randf_range(-_shake, _shake)
	v_offset = randf_range(-_shake, _shake)
	if follow <= 0.0 or follow_target == null:
		return
	var desired := global_transform.looking_at(_goal_point(), Vector3.UP).basis.get_rotation_quaternion()
	var now := global_transform.basis.get_rotation_quaternion()
	# Wykładnicze wygładzanie: niezależne od FPS, w przeciwieństwie do stałego lerp(a, b, 0.1).
	global_transform.basis = Basis(now.slerp(desired, 1.0 - exp(-follow_smoothing * delta)))


func _goal_point() -> Vector3:
	if follow <= 0.0 or follow_target == null:
		return _base_point()
	return _base_point().lerp(follow_target.global_position + Vector3.UP, follow)


func _base_point() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.to_global(look_target) if parent else look_target


func _aim(point: Vector3) -> void:
	if not global_position.is_equal_approx(point):
		look_at(point, Vector3.UP)
