extends Node

signal transport_connected
signal room_changed(room: Dictionary)
signal game_changed(game: Dictionary)
signal error_received(message: String)
signal left_room
signal transport_disconnected

var socket := WebSocketMultiplayerPeer.new()
var connected := false
var connecting := false
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


func connect_to_server(url: String) -> void:
	if connected:
		transport_connected.emit()
		return
	server_url = url
	connecting = true
	socket.close()
	socket = WebSocketMultiplayerPeer.new()
	var error := socket.create_client(url)
	if error != OK:
		connecting = false
		error_received.emit("Cannot reach %s. Start the Godot room server and try again." % server_url)


func _process(_delta: float) -> void:
	socket.poll()
	var status := socket.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED and not connected:
		connecting = false
		connected = true
		transport_connected.emit()
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and connected:
		connected = false
		person_id = 0
		room = {}
		game = {}
		transport_disconnected.emit()
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and connecting:
		connecting = false
		error_received.emit("Cannot reach %s. Start the Godot room server and try again." % server_url)
	while socket.get_available_packet_count() > 0:
		var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if message is Dictionary:
			accept(message)


func accept(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"joined":
			person_id = int(message.person_id)
		"room":
			room = message
			room_changed.emit(room)
		"game":
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
