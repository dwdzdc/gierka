extends SceneTree

const Maps = preload("res://tests/test_maps.gd")
# Krwawienie: trafienie z krwawieniem, potem HP spada o 2/s, aż do powalenia.

var main: Node3D
var gs
var frames := 0
var log: Array[String] = []

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.map_layout = Maps.CLASSIC
	root.add_child.call_deferred(main)

func _physics_process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_connected()
		main.get_node("Monsters").get_child(0).queue_free()
		gs = main.get_node("GameState")
		seed(1)
		while not gs.is_bleeding(1):
			gs.reset_player(1)
			gs.damage(1, 50)
		log.append("po trafieniu hp=%d krwawi=%s" % [gs.hp(1), gs.is_bleeding(1)])
	if frames > 2 and frames % 300 == 0:
		log.append("t=%ds hp=%d krwawi=%s stan=%s" % [frames / 60, gs.hp(1), gs.is_bleeding(1), gs.Life.keys()[gs.life(1)]])
	if frames == 60 * 30:
		print("\n".join(log))
		return true
	return false
