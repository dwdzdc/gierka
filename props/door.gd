class_name Door
extends StaticBody3D
## Drzwi w przejściu między dwoma pokojami (15l–15n). Stawia je main według planu z generatora,
## identycznie u każdego peera; nazwa węzła ("Door07") jest identyfikatorem w sieci.
## Stan trzyma GameState (host), ten węzeł tylko go pokazuje (`apply_state`).
##
## Układ lokalny = znacznik przejścia pokoju A: początek na granicy pokoi, na podłodze,
## +Z w głąb pokoju A, -Z w stronę pokoju B. Skrzydło obraca się na zawiasie do pokoju A.
## W skrzydle jest kratka: gracze patrzą przez nią jak przez szpary szafki (`peek_camera`),
## potwór widzi przez nią tylko z bliska i patrząc prosto na drzwi (Monster.can_see).

## Nowe stany tylko na końcu: wartość leci przez sieć jako liczba.
enum State { OPEN, CLOSED, LOCKED, BROKEN }

const SIZE := Vector2(2.0, 2.6)
const THICKNESS := 0.08
## Okienko z kratą (lokalnie: x od środka skrzydła, y od podłogi).
const GRATE_HALF_WIDTH := 0.3
const GRATE_Y := Vector2(1.45, 1.95)
const USE_DISTANCE := 1.8
## Potwór widzi przez kratkę tylko z tej odległości i patrząc prawie prosto na drzwi.
const GRATE_SIGHT_DISTANCE := 2.6
const GRATE_SIGHT_ANGLE := 35.0
const PEEK_BACK := 0.6  # jak daleko za skrzydłem stoi kamera podglądu
## Warstwa renderu, na którą podglądający przenosi swoją postać: kamera podglądu jej nie rysuje,
## bo stoi za plecami gracza i jego głowa zasłoniłaby kratkę. Inne postacie zostają widoczne.
const PEEK_HIDDEN_LAYER := 4  # warstwa 3 (bit)
const SHAKE_DISTANCE := 10.0

const WOOD := preload("res://rooms/materials/wood.tres")
const METAL := preload("res://rooms/materials/metal.tres")
const CREAK := preload("res://assets/sfx/creak.tres")
const SPLINTER := preload("res://assets/sfx/generated/door_splinter.wav")
const POUND := preload("res://assets/sfx/door_pound.tres")

var state := State.CLOSED
var _leaf: Node3D
var _shape: CollisionShape3D
var _debris: Node3D
var _sound: AudioStreamPlayer3D
## Łomot i wyłamanie mają własny, głośniejszy odtwarzacz: nie ucinają skrzypienia ani siebie
## nawzajem, a słychać je z sąsiednich pokoi (15x).
var _impact: AudioStreamPlayer3D
var _jolt: Tween


func _ready() -> void:
	add_to_group(&"doors")
	collision_layer = 1  # "świat": blokuje graczy, potwory i wzrok
	collision_mask = 0
	_build()
	apply_state(state, false)


## Pokazuje stan (kolizja, skrzydło, gruz). `audible`: zagraj dźwięk zmiany.
func apply_state(new_state: State, audible := true) -> void:
	var changed := new_state != state
	state = new_state
	if _leaf == null:
		return
	_shape.disabled = not blocks()
	_leaf.visible = state != State.BROKEN
	_debris.visible = state == State.BROKEN
	var target_yaw := -PI / 2.0 if state == State.OPEN else 0.0
	if changed and audible and is_inside_tree():
		create_tween().tween_property(_leaf, "rotation:y", target_yaw, 0.35)
		if state == State.BROKEN:
			_impact.stream = SPLINTER
			_impact.play()
			_shake_nearby(0.3)
		else:
			_play(CREAK)
	else:
		_leaf.rotation.y = target_yaw


func blocks() -> bool:
	return state in [State.CLOSED, State.LOCKED]


## Dodatnie po stronie pokoju A (+Z), ujemne po stronie B.
func side(point: Vector3) -> float:
	return (point - global_position).dot(global_transform.basis.z)


## Odległość punktu od środka drzwi w poziomie.
func flat_distance(point: Vector3) -> float:
	var delta := point - global_position
	delta.y = 0.0
	return delta.length()


## Odległość punktu w bok od osi przejścia (wzdłuż szerokości drzwi).
func lateral(point: Vector3) -> float:
	return absf((point - global_position).dot(global_transform.basis.x))


## Kamera podglądu przez kratkę dla kogoś stojącego w `from`: patrzy na drugą stronę.
func peek_camera(from: Vector3) -> Camera3D:
	return $PeekA if side(from) > 0.0 else $PeekB


func in_grate(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= GRATE_HALF_WIDTH and local.y >= GRATE_Y.x and local.y <= GRATE_Y.y


## Potwór przy drzwiach — wywoływane u wszystkich przez GameState: szarpanie klamki, gdy
## otwiera, albo łomot, gdy wyważa (seria łomotów, na końcu trzask z `apply_state`).
func rattle(pound := false) -> void:
	if not pound:
		_play(CREAK)
		return
	_impact.stream = POUND
	_impact.play()
	# Skrzydło drga w futrynie (w stronę pokoju A, bo tam się otwiera), kamera lekko się trzęsie.
	if _jolt:
		_jolt.kill()
	_jolt = create_tween()
	_jolt.tween_property(_leaf, "rotation:y", -0.06, 0.05)
	_jolt.tween_property(_leaf, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE)
	_shake_nearby(0.12)


## Wstrząs kamery u tego peera, gdy jego postać jest blisko (słabnie z odległością).
func _shake_nearby(strength: float) -> void:
	var director := get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	var cam := get_viewport().get_camera_3d() as FixedCamera
	if director == null or cam == null or not is_instance_valid(director.target):
		return
	var falloff := 1.0 - clampf(flat_distance(director.target.global_position) / SHAKE_DISTANCE, 0.0, 1.0)
	if falloff > 0.0:
		cam.shake(strength * falloff)


func _play(stream: AudioStream) -> void:
	_sound.stream = stream
	_sound.play()


func _build() -> void:
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x - 0.04, SIZE.y - 0.02, THICKNESS + 0.04)
	_shape.shape = box
	_shape.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(_shape)

	# Skrzydło: zawias na lewej krawędzi, panele dookoła okienka z kratą.
	_leaf = Node3D.new()
	_leaf.name = "Leaf"
	_leaf.position = Vector3(-SIZE.x / 2.0, 0, 0)
	add_child(_leaf)
	var w := SIZE.x
	var gw := GRATE_HALF_WIDTH
	_leaf_box(Vector3(w / 2.0, GRATE_Y.x / 2.0, 0), Vector3(w, GRATE_Y.x, THICKNESS), WOOD)
	_leaf_box(Vector3(w / 2.0, (GRATE_Y.y + SIZE.y) / 2.0, 0), Vector3(w, SIZE.y - GRATE_Y.y, THICKNESS), WOOD)
	var side_width := w / 2.0 - gw
	var grate_height := GRATE_Y.y - GRATE_Y.x
	_leaf_box(Vector3(side_width / 2.0, (GRATE_Y.x + GRATE_Y.y) / 2.0, 0), Vector3(side_width, grate_height, THICKNESS), WOOD)
	_leaf_box(Vector3(w - side_width / 2.0, (GRATE_Y.x + GRATE_Y.y) / 2.0, 0), Vector3(side_width, grate_height, THICKNESS), WOOD)
	for i in 5:
		var x := w / 2.0 - gw + (i + 0.5) * (2.0 * gw / 5.0)
		_leaf_box(Vector3(x, (GRATE_Y.x + GRATE_Y.y) / 2.0, 0), Vector3(0.025, grate_height, 0.025), METAL)
	for side_sign in [-1.0, 1.0]:  # klamki z obu stron
		_leaf_box(Vector3(w - 0.18, 1.05, side_sign * (THICKNESS / 2.0 + 0.04)), Vector3(0.14, 0.04, 0.04), METAL)

	# Wyłamane drzwi: deski na podłodze po stronie A (bez kolizji).
	_debris = Node3D.new()
	_debris.name = "Debris"
	add_child(_debris)
	for i in 3:
		var plank := _mesh_box(Vector3(1.6 - i * 0.3, 0.05, 0.35), WOOD)
		plank.position = Vector3(-0.4 + i * 0.45, 0.03 + i * 0.05, 0.8 + i * 0.35)
		plank.rotation.y = 0.3 * (i - 1)
		_debris.add_child(plank)

	for peek_name in ["PeekA", "PeekB"]:
		var camera := Camera3D.new()
		camera.name = peek_name
		camera.fov = 70.0
		camera.near = 0.05
		camera.cull_mask &= ~PEEK_HIDDEN_LAYER
		var back := PEEK_BACK if peek_name == "PeekA" else -PEEK_BACK
		camera.position = Vector3(0, (GRATE_Y.x + GRATE_Y.y) / 2.0, back)
		# Kamera patrzy wzdłuż -Z: od strony A na B; od strony B obrócona o 180°.
		camera.rotation.y = 0.0 if peek_name == "PeekA" else PI
		add_child(camera)

	_sound = AudioStreamPlayer3D.new()
	_sound.position = Vector3(0, 1.3, 0)
	_sound.max_distance = 16.0
	add_child(_sound)
	_impact = AudioStreamPlayer3D.new()
	_impact.position = Vector3(0, 1.3, 0)
	_impact.unit_size = 6.0
	_impact.volume_db = 4.0
	_impact.max_distance = 28.0
	add_child(_impact)


func _leaf_box(position: Vector3, size: Vector3, material: Material) -> void:
	var mesh := _mesh_box(size, material)
	mesh.position = position
	_leaf.add_child(mesh)


func _mesh_box(size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = box
	return instance
