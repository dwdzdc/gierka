extends SceneTree
# Pętla rundy w jednym procesie, dwóch graczy (peer 2 dodany ręcznie):
# monety na mapie, zbieranie, śmierć gubi monety (kupka na ziemi), wyjście windą,
# koniec rundy z podziałem zero-sum, następna runda.

const Maps = preload("res://tests/test_maps.gd")
var main: Node3D
var gs
var f := 0
var log: Array[String] = []
var results := []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _say(text: String) -> void:
	log.append("t=%.1f %s" % [f / 60.0, text])

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).set_physics_process(false)
		main._spawn_player(2)
		gs = main.get_node("GameState")
		gs.round_finished.connect(func(r): results = r)
	if f == 40:
		# Same kupki monet (w łupie są też baterie i skrzynie).
		var piles = main.get_node("Loot").get_children().filter(func(n): return n.scene_file_path.ends_with("coin_pile.tscn"))
		var total := 0
		for p in piles:
			total += p.value
		_say("monet na mapie: %d kupek, razem %d" % [piles.size(), total])
		# Gracz 1 zbiera dwie kupki (teleport na nie).
		main.get_node("Players/1").global_position = piles[0].global_position
	if f == 50:
		main.get_node("Players/1").global_position = main.get_node("Loot").get_child(0).global_position
	if f == 60:
		_say("gracz 1 niesie %d" % gs.coins(1))
		# Gracz 2 też coś zbiera, potem ginie: monety lądują na ziemi.
		gs.add_coins(2, 50, Vector3.ZERO)
		var before: int = main.get_node("Loot").get_child_count()
		gs.execute(2)
		_say("gracz 2 zginął z 50 monetami; kupek przed %d" % before)
	if f == 62:
		_say("kupek po śmierci gracza 2: %d (ostatnia warta %d)" % [main.get_node("Loot").get_child_count(), main.get_node("Loot").get_children()[-1].value])
		# Gracz 1 idzie do windy i trzyma E.
		var p1 = main.get_node("Players/1")
		p1.global_position = gs.exit_position + Vector3(0.5, 0, 0)
		Input.action_press("interact")
	if f == 62 + 150:
		Input.action_release("interact")
		_say("stan gracza 1: %s, koniec rundy: %s" % [gs.Life.keys()[gs.life(1)], gs.round_over])
		for r in results:
			_say("  %s przeżył=%s wyniesione=%d wynik=%d suma=%d" % [r.name, r.survived, r.banked, r.score, r.session])
		main.request_next_round()
	if f == 62 + 200:
		_say("nowa runda: stan 1=%s 2=%s, koniec=%s, kupek %d, potworów %d, gracz 1 przy spawnie: %s" % [
			gs.Life.keys()[gs.life(1)], gs.Life.keys()[gs.life(2)], gs.round_over, main.get_node("Loot").get_child_count(),
			main.get_node("Monsters").get_child_count(), main.get_node("Players/1").global_position.distance_to(main._spawn_transform(0).origin) < 1.0])
		print("\n".join(log))
		return true
	return false
