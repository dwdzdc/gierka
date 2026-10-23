extends SceneTree
# Podział puli zero-sum (35b): wcześniejsze wyjście nie korzysta z monet wyniesionych później.

var gs

func _initialize() -> void:
	gs = load("res://game/game_state.gd").new()
	root.add_child.call_deferred(gs)

func _process(_d: float) -> bool:
	if not gs.is_inside_tree():
		return false
	var cases := [
		["A ze 100 pierwszy, B ze 100 później", [[1, 100, 1], [2, 100, 2]], {1: 75, 2: 125}],
		["tylko A przeżył (100)", [[1, 100, 1], [2, 0, 0]], {1: 100, 2: 0}],
		["trzech: A 60, B 30, C 90 w tej kolejności (A 30+10, B 15+10+7,5, C 45+10+7,5+45)", [[1, 60, 1], [2, 30, 2], [3, 90, 3]], {1: 40, 2: 33, 3: 107}],
	]
	for c in cases:
		gs.players = {}
		for p in c[1]:
			gs.players[p[0]] = gs._fresh_entry({"name": "G%d" % p[0]})
			gs.players[p[0]].banked = p[1]
			gs.players[p[0]].extract_order = p[2]
			gs.players[p[0]].life = gs.Life.EXTRACTED if p[2] > 0 else gs.Life.DEAD
		var got := {}
		var total := 0
		for r in gs.compute_results():
			got[r.peer_id] = r.score
			total += r.score
		print("%s %s: %s (suma %d)" % ["OK " if got == c[2] else "ZLE", c[0], got, total])
	return true
