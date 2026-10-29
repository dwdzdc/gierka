extends Node
## Połączenie sieciowe (autoload "Net"). Model host-client po ENet (UDP):
## jeden gracz hostuje i jest jednocześnie serwerem (peer id 1), reszta łączy się po IP.
## Ten węzeł zna tylko połączenie. Co się dzieje w grze po połączeniu, decyduje main.gd.

signal connected  # lokalny gracz jest w sesji (host wystartował albo klient się połączył)
signal disconnected(reason: String)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 4  # host + 4 = 5 graczy (więcej wymaga skalowania trudności, patrz progress.md)

## Powód ostatniego rozłączenia. Autoload przeżywa przeładowanie sceny, więc menu może go pokazać.
var last_disconnect_reason := ""


func _ready() -> void:
	multiplayer.connected_to_server.connect(connected.emit)
	multiplayer.connection_failed.connect(_drop.bind("Nie udało się połączyć"))
	multiplayer.server_disconnected.connect(_drop.bind("Host zakończył grę"))


func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	connected.emit()
	return OK


## Asynchroniczne: wynik przychodzi sygnałem `connected` albo `disconnected`.
func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Adres z pola "Dołącz" -> [host, port]. Port opcjonalny ("host:port"), bo tunele typu
## playit.gg dają losowy port zamiast 7777. Goły IPv6 ma kilka dwukropków, więc port
## tylko w nawiasach: "[::1]:7777".
static func parse_address(text: String) -> Array:
	text = text.strip_edges()
	var port := DEFAULT_PORT
	if text.begins_with("["):
		var end := text.find("]")
		if end != -1:
			var rest := text.substr(end + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				port = rest.substr(1).to_int()
			return [text.substr(1, end - 1), port]
	elif text.count(":") == 1:
		var colon := text.find(":")
		if text.substr(colon + 1).is_valid_int():
			return [text.left(colon), text.substr(colon + 1).to_int()]
	return [text, port]


## Adresy IPv4 tego komputera w sieci lokalnej: to podajesz koledze do "Dołącz".
func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


func _drop(reason: String) -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()  # wraca do trybu offline
	last_disconnect_reason = reason
	disconnected.emit(reason)
