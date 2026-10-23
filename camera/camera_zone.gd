class_name CameraZone
extends Area3D
## Strefa ujęcia. Gdy gracz w nią wejdzie, CameraDirector może przełączyć się
## na kamerę-dziecko `Camera`. Strefy sąsiednich ujęć powinny na siebie
## nachodzić (~0.5–1 m): to daje histerezę na granicy.

## Przy nakładaniu się stref wygrywa wyższy priorytet (np. mała wnęka w dużym pokoju).
@export var camera_priority := 0

@onready var camera: FixedCamera = $Camera


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	get_tree().call_group(&"camera_director", &"on_zone_entered", self, body)


func _on_body_exited(body: Node3D) -> void:
	get_tree().call_group(&"camera_director", &"on_zone_exited", self, body)
