extends Node

## Session layer. One player hosts and simulates, the other joins with a room code.
## The code is the host's LAN IPv4 packed into base32, so joining works on the same
## network (or with the port forwarded). LOCAL is a debug-only split-keyboard mode.

signal partner_joined
signal partner_left
signal join_failed(reason: String)
signal session_closed(reason: String)

enum Mode { NONE, LOCAL, HOST, CLIENT }

const PORT := 24565
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var mode: Mode = Mode.NONE
var room_code: String = ""
var stage_seed: int = 1
var partner_present: bool = false
var in_game: bool = false
var last_message: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_authority() -> bool:
	return mode == Mode.LOCAL or mode == Mode.HOST


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func host() -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	stage_seed = randi() % 1000000 + 1
	room_code = encode_code(_local_ipv4())
	return OK


func join(code: String) -> Error:
	close()
	var address := decode_code(code)
	if address.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	room_code = code.strip_edges().to_upper()
	return OK


func start_local(seed_value: int = 0) -> void:
	close()
	mode = Mode.LOCAL
	stage_seed = seed_value if seed_value != 0 else randi() % 1000000 + 1
	partner_present = true
	_enter_game()


func close() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	partner_present = false
	in_game = false


func leave_to_menu(message: String = "") -> void:
	close()
	last_message = message
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE)


func encode_code(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var value := 0
	for p in parts:
		value = (value << 8) | (int(p) & 255)
	var chars := ""
	for _i in 7:
		chars = CODE_ALPHABET[value & 31] + chars
		value >>= 5
	return chars.substr(0, 4) + "-" + chars.substr(4)


## Accepts a room code, a dotted IPv4 address, or "localhost".
func decode_code(code: String) -> String:
	var clean := code.strip_edges()
	if clean.to_lower() == "localhost":
		return "127.0.0.1"
	if clean.is_valid_ip_address():
		return clean
	clean = clean.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if clean.length() != 7:
		return ""
	var value := 0
	for c in clean:
		var digit := CODE_ALPHABET.find(c)
		if digit < 0:
			return ""
		value = (value << 5) | digit
	if value >= (1 << 32):
		return ""
	return "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]


func _local_ipv4() -> String:
	var fallback := "127.0.0.1"
	for address in IP.get_local_addresses():
		if not address.is_valid_ip_address() or address.contains(":"):
			continue
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var second := int(address.split(".")[1])
			if second >= 16 and second <= 31:
				return address
		if not address.begins_with("127.") and not address.begins_with("169.254."):
			fallback = address
	return fallback


func _on_peer_connected(_id: int) -> void:
	if mode != Mode.HOST:
		return
	partner_present = true
	# A partner coming back mid-climb gets the same mountain; the game resyncs them.
	_start_game.rpc(stage_seed)
	if not in_game:
		_enter_game()
	partner_joined.emit()


func _on_peer_disconnected(_id: int) -> void:
	if mode != Mode.HOST:
		return
	partner_present = false
	partner_left.emit()


func _on_connected_to_server() -> void:
	partner_present = true


func _on_connection_failed() -> void:
	close()
	join_failed.emit("Could not reach that room.")


func _on_server_disconnected() -> void:
	var was_in_game := in_game
	close()
	session_closed.emit("The host left the mountain.")
	if was_in_game:
		leave_to_menu("The host left the mountain.")


@rpc("authority", "call_remote", "reliable")
func _start_game(seed_value: int) -> void:
	stage_seed = seed_value
	_enter_game()


func _enter_game() -> void:
	in_game = true
	get_tree().call_deferred("change_scene_to_file", GAME_SCENE)
