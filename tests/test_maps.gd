extends RefCounted
## Stałe układy map dla testów (zamiast losowych). Użycie w teście:
##   const Maps = preload("res://tests/test_maps.gd")
##   main.map_layout = Maps.CLASSIC
## CLASSIC: hala (środek x=0) -> korytarz (x=16.4) -> magazyn (x=34.8), wszystko wzdłuż +X.

const CLASSIC := [
	["res://rooms/corridor.tscn", "East", "West"],
	["res://rooms/storage.tscn", "East", "West"],
]

## KITE: hala -> atrium z fontanną (do testu biegania w kółko wokół przeszkody).
const KITE := [
	["res://rooms/atrium.tscn", "East", "West"],
]
