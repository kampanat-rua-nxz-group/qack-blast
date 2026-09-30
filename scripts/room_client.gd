extends Node

signal transport_result(attempt_id: int, connected: bool)
signal room_result(attempt_id: int, message: Dictionary)
signal transport_connected
signal room_changed(room: Dictionary)
signal game_changed(game: Dictionary)
signal error_received(message: String)
signal left_room
signal transport_disconnected

var socket := WebSocketMultiplayerPeer.new()
var connected := false
var connecting := false
var transport_generation := -1
var server_url := ""
var person_id := 0
var room: Dictionary = {}
var game: Dictionary = {}

const DEFAULT_SERVER_URL = "ws://127.0.0.1:9080"


static func resolve_server_url(args: PackedStringArray, web_value: String, public_url: String = "") -> String:
	if not web_value.strip_edges().is_empty():
		return web_value.strip_edges()
	for arg in args:
		if arg.begins_with("--server="):
			return arg.trim_prefix("--server=")
	if not public_url.strip_edges().is_empty():
		return public_url.strip_edges()
	return DEFAULT_SERVER_URL


func connect_to_server(url: String, generation: int = 0) -> void:
	close_transport(transport_generation)
	server_url = url
	transport_generation = generation
	connecting = true
	socket = WebSocketMultiplayerPeer.new()
	var error := socket.create_client(url)
	if error != OK:
		connecting = false
		transport_result.emit(generation, false)


func close_transport(generation: int) -> void:
	if generation != transport_generation:
		return
	socket.close()
	transport_generation = -1
	connected = false
	connecting = false
	person_id = 0
	room = {}
	game = {}


func _process(_delta: float) -> void:
	if transport_generation < 0:
		return
	var polled_socket := socket
	var generation := transport_generation
	polled_socket.poll()
	var status := polled_socket.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED and not connected:
		connecting = false
		connected = true
		transport_result.emit(generation, true)
		if generation != transport_generation or socket != polled_socket:
			return
		transport_connected.emit()
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and connected:
		connected = false
		person_id = 0
		room = {}
		game = {}
		transport_disconnected.emit()
		transport_result.emit(generation, false)
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and connecting:
		connecting = false
		transport_result.emit(generation, false)
	while generation == transport_generation and socket == polled_socket and polled_socket.get_available_packet_count() > 0:
		var message = JSON.parse_string(polled_socket.get_packet().get_string_from_utf8())
		if message is Dictionary:
			accept(message, generation)


func accept(message: Dictionary, generation: int = -1) -> void:
	if generation >= 0 and generation != transport_generation:
		return
	if str(message.get("type", "")) in ["joined", "error"]:
		room_result.emit(transport_generation if generation < 0 else generation, message)
		if generation >= 0 and generation != transport_generation:
			return
	match str(message.get("type", "")):
		"joined":
			person_id = int(message.person_id)
		"room":
			room = message
			room_changed.emit(room)
		"game":
			var next_round := int(message.round_id)
			if next_round < int(room.get("round_id", -1)):
				return
			if not game.is_empty() and (next_round < int(game.round_id) or (next_round == int(game.round_id) and int(message.snapshot_seq) <= int(game.snapshot_seq))):
				return
			game = message
			game_changed.emit(game)
		"left":
			person_id = 0
			room = {}
			game = {}
			left_room.emit()
		"error":
			error_received.emit(str(message.get("message", "Server error")))


func send(message: Dictionary) -> void:
	if not connected:
		return
	socket.set_target_peer(1)
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())
