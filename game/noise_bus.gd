extends Node
## Autoload "NoiseBus": hałasy w świecie, które może usłyszeć potwór.
## Działa tylko u hosta, bo tam żyje AI. U klientów `emit_noise` nic nie robi.
##
## `radius` = z jakiej odległości (m) hałas jest słyszalny. Kroki ~4 m, bieg ~10 m.

signal noise_made(position: Vector3, radius: float, source: Node)

## Do debugowania: ostatnie hałasy (pozycja, promień, czas).
var recent: Array[Dictionary] = []


func emit_noise(position: Vector3, radius: float, source: Node = null) -> void:
	if not multiplayer.is_server():
		return
	recent.append({"position": position, "radius": radius, "time": Time.get_ticks_msec()})
	if recent.size() > 32:
		recent.pop_front()
	noise_made.emit(position, radius, source)
