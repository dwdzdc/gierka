class_name HidingSpot
extends StaticBody3D
## Szafka, w której można się schować (E). Kto w niej siedzi, trzyma GameState (host);
## ten węzeł daje tylko punkty (środek, wyjście) i kamerę "przez szpary".
## Ścieżka węzła jest identyczna u każdego peera (pokoje są deterministyczne),
## więc po sieci przesyłamy ją jako identyfikator kryjówki.

const USE_DISTANCE := 1.6


func _ready() -> void:
	add_to_group(&"hiding_spots")


## Punkt przed drzwiami szafki: tam trzeba stać, żeby wejść, i tam się wychodzi.
func front_transform() -> Transform3D:
	return $Front.global_transform


func inside_position() -> Vector3:
	return $Inside.global_position


func peek_camera() -> Camera3D:
	return $Peek


func can_use_from(position: Vector3) -> bool:
	return position.distance_to($Front.global_position) <= USE_DISTANCE
