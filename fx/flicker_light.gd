extends OmniLight3D
## Migocząca żarówka: przez większość czasu świeci stabilnie, czasem przygasa seriami.

@export var flicker_chance := 0.35  # szansa na serię mignięć na sekundę

@onready var _base_energy := light_energy
var _flicker_left := 0.0


func _process(delta: float) -> void:
	if _flicker_left > 0.0:
		_flicker_left -= delta
		light_energy = _base_energy * randf_range(0.05, 1.0)
	else:
		light_energy = _base_energy
		if randf() < flicker_chance * delta:
			_flicker_left = randf_range(0.1, 0.6)
