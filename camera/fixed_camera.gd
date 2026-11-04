@tool
class_name FixedCamera
extends Camera3D
## Nieruchome ujęcie w stylu RE. Pozycja jest stała, kamera celuje w `look_target`
## (współrzędne lokalne rodzica, czyli strefy). Gdy `follow > 0`, obraca się
## za graczem, ale nigdy nie zmienia pozycji i nie wychodzi poza `max_turn` od
## ustawienia bazowego. Gdyby musiała się kręcić szybko albo daleko, w tym miejscu
## powinna już patrzeć inna kamera: to sprawa rozstawienia stref (`camera_turn_test`).

@export var look_target := Vector3.ZERO:
	set(value):
		look_target = value
		if is_inside_tree():
			_aim(_base_point())
## 0 = statyczna, 1 = patrzy prosto na gracza. Wartości pośrednie dają lekki "pan".
@export_range(0.0, 1.0) var follow := 0.0
@export var follow_smoothing := 4.0
## Największy kąt (stopnie) między kierunkiem bazowym a kierunkiem za graczem.
@export var max_turn := 30.0

const DEFAULT_SHAKE := 0.15  # typowy wstrząs (np. trafienie)
const SHAKE_FADE := 0.5  # jednostek na sekundę: wstrząs wygasa

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
func shake(strength := DEFAULT_SHAKE) -> void:
	_shake = maxf(_shake, strength)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not current:
		return
	_shake = move_toward(_shake, 0.0, delta * SHAKE_FADE)
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
	return aim_point(follow_target.global_position)


## Punkt, w który kamera patrzy, gdy gracz stoi w `player_position`: przesunięcie w stronę
## gracza o `follow`, przycięte do `max_turn` od kierunku bazowego. Publiczne dla testów.
func aim_point(player_position: Vector3) -> Vector3:
	var base := _base_point()
	var wanted := base.lerp(player_position + Vector3.UP, follow)
	var base_dir := (base - global_position).normalized()
	var wanted_dir := (wanted - global_position).normalized()
	var angle := base_dir.angle_to(wanted_dir)
	var limit := deg_to_rad(max_turn)
	if angle <= limit or angle < 0.001:
		return wanted
	return global_position + base_dir.slerp(wanted_dir, limit / angle) * global_position.distance_to(wanted)


func _base_point() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.to_global(look_target) if parent else look_target


func _aim(point: Vector3) -> void:
	if not global_position.is_equal_approx(point):
		look_at(point, Vector3.UP)
