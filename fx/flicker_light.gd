extends OmniLight3D
## Migocząca żarówka: przez większość czasu świeci stabilnie, czasem przygasa seriami.
## Jej oprawa (sąsiedni węzeł `FixtureN` przy `LightN`) przygasa razem z nią, inaczej przy
## zgaszonej żarówce w ciemności zostaje świecący prostokąt.
## Generator mapy dokleja ten skrypt w trakcie gry, już po `_ready`, dlatego stan
## inicjuje się leniwie w `_process`, a generator sam włącza przetwarzanie.

@export var flicker_chance := 0.35  # szansa na serię mignięć na sekundę

var _base_energy := -1.0
var _flicker_left := 0.0
var _fixture_material: StandardMaterial3D
var _fixture_emission := 0.0


func _process(delta: float) -> void:
	if _base_energy < 0.0:
		_setup()
	if _flicker_left > 0.0:
		_flicker_left -= delta
		light_energy = _base_energy * randf_range(0.05, 1.0)
	else:
		light_energy = _base_energy
		if randf() < flicker_chance * delta:
			_flicker_left = randf_range(0.1, 0.6)
	if _fixture_material:
		_fixture_material.emission_energy_multiplier = _fixture_emission * light_energy / _base_energy


func _setup() -> void:
	_base_energy = light_energy
	var fixture := get_parent().get_node_or_null(NodePath(name.replace("Light", "Fixture"))) as MeshInstance3D
	if fixture == null or fixture.mesh == null:
		return
	# Własna kopia materiału: wspólny materiał przygasiłby wszystkie oprawy na mapie naraz.
	_fixture_material = fixture.mesh.surface_get_material(0).duplicate()
	_fixture_emission = _fixture_material.emission_energy_multiplier
	fixture.material_override = _fixture_material
