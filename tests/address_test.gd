extends SceneTree
# Pole "Dołącz": adres z opcjonalnym portem (tunele typu playit.gg dają losowy port).
#   godot --headless --path . -s tests/address_test.gd

const Network = preload("res://net/network.gd")


func _initialize() -> void:
	var cases := {
		"192.168.1.20": ["192.168.1.20", 7777],
		" 192.168.1.20 ": ["192.168.1.20", 7777],
		"cos.at.ply.gg:12345": ["cos.at.ply.gg", 12345],
		"localhost:7778": ["localhost", 7778],
		"[::1]:9000": ["::1", 9000],
		"[::1]": ["::1", 7777],
		"fe80::1": ["fe80::1", 7777],
		"host:abc": ["host:abc", 7777],
	}
	var ok := true
	for text in cases:
		var got: Array = Network.parse_address(text)
		if got != cases[text]:
			ok = false
			print("ZLE  '%s' -> %s, oczekiwano %s" % [text, got, cases[text]])
	print("OK" if ok else "BLAD")
	quit(0 if ok else 1)
