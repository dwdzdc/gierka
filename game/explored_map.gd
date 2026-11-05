class_name ExploredMap
extends CanvasLayer
## Mapa-notatnik (65): pod klawiszem M (trzymanym) na środku ekranu. Pokazuje tylko pokoje, w których
## ten gracz był, i windę, jeśli ją widział. Całkiem lokalna: nic nie leci przez sieć, a każdy
## gracz ma swój notatnik, więc „znalazłem windę” trzeba koledze powiedzieć. Póki mapa jest
## otwarta, postać stoi (Player sprawdza akcję "map"), a W/S przełączają piętra.

const FLOOR_STEP := 5.0  # wysokość piętra, jak FLOOR_STEP w tools/gen_rooms.py
const MAX_SCALE := 14.0  # px na metr: pierwszy pokój nie wypełnia całego ekranu
const PANEL_FRACTION := 0.8  # część wysokości ekranu zajęta przez mapę
const LAYER := 5  # nad HUD-em, pod menu
const BODY_POINT := 0.5  # m nad stopami: punkt ciała do sprawdzania, w którym pokoju stoi gracz
const EXIT_SIGN_HEIGHT := 1.3  # m nad znacznikiem wyjścia: znak nad drzwiami windy
const EXIT_SEE_RANGE := 25.0  # m: dalej winda w kadrze to plamka, nie „znalezienie”
const WORLD_MASK := 1  # warstwa "world"
const WALL := 0.2  # m: ściana pokoju, rysujemy wnętrze
const MARGIN := 48.0  # px od brzegu panelu do mapy
const TITLE_OFFSET := Vector2(16, 30)
const TITLE_SIZE := 22
const LABEL_SIZE := 18
const PANEL_EDGE := 2.0  # px: obwódka panelu
const ROOM_EDGE := 1.5  # px: obwódka pokoju
const DOOR_MARK := 8.0  # px: kwadracik przejścia
const EXIT_MARK := 14.0  # px: kwadrat windy
const EXIT_LABEL_OFFSET := Vector2(10, 6)
const ARROW_TIP := 12.0  # px: strzałka gracza (czubek, tył i pół szerokości)
const ARROW_BACK := 7.0
const ARROW_HALF := 7.0
const COLOR_BACK := Color(0.05, 0.06, 0.07, 0.88)
const COLOR_ROOM := Color(0.55, 0.58, 0.55, 0.35)
const COLOR_HERE := Color(0.75, 0.78, 0.7, 0.55)
const COLOR_EDGE := Color(0.85, 0.87, 0.8)
const COLOR_DOOR := Color(0.95, 0.8, 0.45)
const COLOR_EXIT := Color(0.3, 0.95, 0.4)
const COLOR_PLAYER := Color(1.0, 0.35, 0.3)

## Ustawia main.gd: skąd brać pokoje, przejścia, pozycję wyjścia i gracza.
var main: Node
## Indeksy pokoi z main.rooms, w których gracz był (kolejność pokoi jest ta sama u wszystkich).
var visited := {}
var exit_seen := false
## Piętro pokazywane na mapie (0 = parter hali, ujemne pod nim).
var shown_floor := 0

var _canvas := Control.new()


func _ready() -> void:
	layer = LAYER
	visible = false
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)


## Nowa mapa (nowa runda albo nowy seed): notatnik zaczyna się od zera.
func reset() -> void:
	visited.clear()
	exit_seen = false


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	var player := _local_player()
	if player == null:
		visible = false
		return
	_explore(player)
	var wanted := Input.is_action_pressed("map")
	if wanted and not visible:
		shown_floor = floor_of(player.global_position.y)
	visible = wanted
	if visible:
		var floors := _visited_floors()
		if Input.is_action_just_pressed("move_forward"):
			shown_floor = _step_floor(floors, 1)
		elif Input.is_action_just_pressed("move_back"):
			shown_floor = _step_floor(floors, -1)
		_canvas.queue_redraw()


static func floor_of(y: float) -> int:
	return roundi(y / FLOOR_STEP)


## Piętra, na których pokój ma przejścia (rampa i klatka schodowa leżą na dwóch).
static func room_floors(room: Room) -> Array[int]:
	var floors: Array[int] = [floor_of(room.global_position.y)]
	for door in room.get_doorways():
		var level := floor_of(door.global_position.y)
		if not floors.has(level):
			floors.append(level)
	return floors


static func room_box(room: Room) -> AABB:
	return room.global_transform * room.bounds


func _local_player() -> Node3D:
	if main == null or not main.is_node_ready():
		return null
	return main.get_node("Players").get_node_or_null(str(multiplayer.get_unique_id())) as Node3D


func _rooms() -> Array:
	return main.rooms.filter(func(r: Room) -> bool: return is_instance_valid(r))


## Zaznacza pokój, w którym stoi gracz, i windę, gdy była w kadrze (nie od samego wejścia do pokoju:
## winda w głębi dużej sali nie jest jeszcze „znaleziona”).
func _explore(player: Node3D) -> void:
	var point := player.global_position + Vector3.UP * BODY_POINT
	for i in main.rooms.size():
		var room: Room = main.rooms[i]
		if not visited.has(i) and is_instance_valid(room) and room_box(room).has_point(point):
			visited[i] = true
	if exit_seen:
		return
	var exit: Vector3 = main.game_state.exit_position
	var camera := get_viewport().get_camera_3d()
	if not exit.is_finite() or camera == null:
		return
	var sign_point := exit + Vector3.UP * EXIT_SIGN_HEIGHT
	if camera.global_position.distance_to(sign_point) > EXIT_SEE_RANGE or not camera.is_position_in_frustum(sign_point):
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, sign_point, WORLD_MASK)
	if camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		exit_seen = true


func _visited_floors() -> Array[int]:
	var floors: Array[int] = []
	for i in visited:
		if i < main.rooms.size() and is_instance_valid(main.rooms[i]):
			for level in room_floors(main.rooms[i]):
				if not floors.has(level):
					floors.append(level)
	floors.sort()
	return floors


## Następne piętro w górę (1) lub w dół (-1), na którym coś odwiedziliśmy.
func _step_floor(floors: Array[int], direction: int) -> int:
	var best := shown_floor
	for level in floors:
		if (level - shown_floor) * direction > 0 and (best == shown_floor or absi(level - shown_floor) < absi(best - shown_floor)):
			best = level
	return best


func _draw_map() -> void:
	var view := _canvas.get_viewport_rect().size
	var side := view.y * PANEL_FRACTION
	var panel := Rect2((view - Vector2(side, side)) / 2.0, Vector2(side, side))
	_canvas.draw_rect(panel, COLOR_BACK)
	_canvas.draw_rect(panel, COLOR_EDGE, false, PANEL_EDGE)
	var font := ThemeDB.fallback_font
	var floors := _visited_floors()
	var title := "Piętro %d" % shown_floor
	if floors.size() > 1:
		title += "   (W/S: piętro, %d z %d)" % [floors.find(shown_floor) + 1, floors.size()]
	_canvas.draw_string(font, panel.position + TITLE_OFFSET, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, COLOR_EDGE)

	# Skala z obrysu wszystkich odwiedzonych pokoi (wszystkie piętra): przełączanie pięter nie
	# przesuwa ani nie powiększa mapy, więc piętra da się porównać.
	var area := Rect2()
	var first := true
	for i in visited:
		if i >= main.rooms.size() or not is_instance_valid(main.rooms[i]):
			continue
		var box := room_box(main.rooms[i])
		var rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		area = rect if first else area.merge(rect)
		first = false
	if first:
		return
	var inner := panel.grow(-MARGIN)
	var scale := minf(MAX_SCALE, minf(inner.size.x / maxf(area.size.x, 1.0), inner.size.y / maxf(area.size.y, 1.0)))
	var origin := inner.get_center() - area.get_center() * scale
	var to_screen := func(p: Vector3) -> Vector2: return origin + Vector2(p.x, p.z) * scale

	var player := _local_player()
	for i in visited:
		if i >= main.rooms.size() or not is_instance_valid(main.rooms[i]):
			continue
		var room: Room = main.rooms[i]
		if not room_floors(room).has(shown_floor):
			continue
		var box := room_box(room)
		# Ściany 0,2 m: rysujemy wnętrze, żeby sąsiednie pokoje nie zlewały się w jedną plamę.
		var rect := Rect2(to_screen.call(box.position), Vector2(box.size.x, box.size.z) * scale).grow(-WALL * scale)
		var here := player != null and box.has_point(player.global_position + Vector3.UP * BODY_POINT)
		_canvas.draw_rect(rect, COLOR_HERE if here else COLOR_ROOM)
		_canvas.draw_rect(rect, COLOR_EDGE, false, ROOM_EDGE)
	# Przejścia odwiedzonych pokoi: notatnik wie, że tam są drzwi, nawet jeśli nie wie dokąd.
	for connection in main.map_connections:
		for door in [connection.a, connection.b]:
			var room := _room_of(door)
			var index: int = main.rooms.find(room)
			if visited.has(index) and floor_of(door.global_position.y) == shown_floor:
				_canvas.draw_rect(Rect2(to_screen.call(door.global_position) - Vector2.ONE * DOOR_MARK / 2.0, Vector2.ONE * DOOR_MARK), COLOR_DOOR)
	if exit_seen and floor_of(main.game_state.exit_position.y) == shown_floor:
		var at: Vector2 = to_screen.call(main.game_state.exit_position)
		_canvas.draw_rect(Rect2(at - Vector2.ONE * EXIT_MARK / 2.0, Vector2.ONE * EXIT_MARK), COLOR_EXIT)
		_canvas.draw_string(font, at + EXIT_LABEL_OFFSET, "winda", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, COLOR_EXIT)
	if player != null and floor_of(player.global_position.y) == shown_floor:
		var at: Vector2 = to_screen.call(player.global_position)
		var forward := -player.global_transform.basis.z
		var dir := Vector2(forward.x, forward.z).normalized()
		var normal := Vector2(-dir.y, dir.x)
		_canvas.draw_colored_polygon(PackedVector2Array([at + dir * ARROW_TIP, at - dir * ARROW_BACK + normal * ARROW_HALF, at - dir * ARROW_BACK - normal * ARROW_HALF]), COLOR_PLAYER)


func _room_of(node: Node) -> Room:
	while node != null and not node is Room:
		node = node.get_parent()
	return node as Room
