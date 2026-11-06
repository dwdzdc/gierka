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
const COLOR_PROP := Color(0.18, 0.2, 0.19, 0.95)  # meble ciemniejsze od podłogi: widać przejścia między nimi
const COLOR_RAMP := Color(0.7, 0.62, 0.42, 0.5)
const COLOR_PLATFORM := Color(0.85, 0.87, 0.8, 0.12)  # antresola półprzezroczysta: pod nią też jest podłoga
const PROP_EDGE := 1.0  # px: obwódka mebla
const PLATFORM_DASH := 6.0  # px: kreska obrysu antresoli
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
## Podłoga pokoju (lokalnie, x/z) bez ścian w środku: liczona raz na pokój, bo obrysy się nie zmieniają.
var _floors := {}  # Room -> [podłogi, słupy]


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
	_floors.clear()


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
		var here := player != null and box.has_point(player.global_position + Vector3.UP * BODY_POINT)
		_draw_room(room, here, origin, scale)
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


## Kształt pokoju z obrysów z generatora (67): podłoga minus ściany, na niej meble, rampy i antresola.
func _draw_room(room: Room, here: bool, origin: Vector2, scale: float) -> void:
	var shape := _floor_of(room)
	var project := func(poly: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for point in poly:
			var world := room.global_transform * Vector3(point.x, 0.0, point.y)
			out.append(origin + Vector2(world.x, world.z) * scale)
		return out
	for poly in shape[0]:
		_canvas.draw_colored_polygon(project.call(poly), COLOR_HERE if here else COLOR_ROOM)
	for poly in room.map_ramps:
		_canvas.draw_colored_polygon(project.call(poly), COLOR_RAMP)
	for poly in room.map_props:
		var screen: PackedVector2Array = project.call(poly)
		_canvas.draw_colored_polygon(screen, COLOR_PROP)
		_canvas.draw_polyline(_closed(screen), COLOR_EDGE, PROP_EDGE)
	for poly in shape[2]:
		var screen: PackedVector2Array = project.call(poly)
		_canvas.draw_colored_polygon(screen, COLOR_PLATFORM)
		var ring := _closed(screen)
		for k in ring.size() - 1:
			_canvas.draw_dashed_line(ring[k], ring[k + 1], COLOR_EDGE, PROP_EDGE, PLATFORM_DASH)
	for poly in shape[0]:
		_canvas.draw_polyline(_closed(project.call(poly)), COLOR_EDGE, ROOM_EDGE)
	for poly in shape[1]:
		var screen: PackedVector2Array = project.call(poly)
		_canvas.draw_colored_polygon(screen, COLOR_BACK)
		_canvas.draw_polyline(_closed(screen), COLOR_EDGE, ROOM_EDGE)


## [podłogi, słupy, pomosty]: wnętrze pokoju (bryła bez ścian zewnętrznych) minus ściany z generatora.
## Ściana w środku podłogi zrobiłaby dziurę, której wielokąt nie opisze – taką rysujemy jako słup.
## Pomosty też przycinamy do ścian: deski antresoli biblioteki wchodzą w ścięte narożniki.
func _floor_of(room: Room) -> Array:
	if _floors.has(room):
		return _floors[room]
	var b := room.bounds
	var x0 := b.position.x + Room.WALL_THICKNESS
	var x1 := b.end.x - Room.WALL_THICKNESS
	var z0 := b.position.z + Room.WALL_THICKNESS
	var z1 := b.end.z - Room.WALL_THICKNESS
	var floors: Array[PackedVector2Array] = [PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])]
	var pillars: Array[PackedVector2Array] = []
	var platforms: Array[PackedVector2Array] = room.map_platforms.duplicate()
	for wall in room.map_walls:
		var cut: Array[PackedVector2Array] = []
		for poly in platforms:
			cut.append_array(Geometry2D.clip_polygons(poly, wall).filter(func(part: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(part)))
		platforms = cut
		var next: Array[PackedVector2Array] = []
		var hole := false
		for poly in floors:
			var parts := Geometry2D.clip_polygons(poly, wall)
			if parts.any(func(part: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(part)):
				hole = true
				next.append(poly)
			else:
				next.append_array(parts)
		floors = next
		if hole:
			pillars.append(wall)
	_floors[room] = [floors, pillars, platforms]
	return _floors[room]


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var ring := poly.duplicate()
	ring.append(poly[0])
	return ring


func _room_of(node: Node) -> Room:
	while node != null and not node is Room:
		node = node.get_parent()
	return node as Room
