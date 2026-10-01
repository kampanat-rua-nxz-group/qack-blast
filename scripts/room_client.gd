extends Node

signal transport_result(attempt_id: int, connected: bool)
signal room_result(attempt_id: int, message: Dictionary)
signal transport_connected
signal room_changed(room: Dictionary)
signal game_changed(game: Dictionary)
signal error_received(message: String)
signal events_received(round_id: int, events: Array)
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
const MAX_PENDING_EVENT_MESSAGES = 8

var pending_events: Array = []
var event_round := -1
var event_cursor := 0
var event_floor := 0
var events_synced := false


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
	reset_events()


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
		reset_events()
		transport_disconnected.emit()
		transport_result.emit(generation, false)
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and connecting:
		connecting = false
		transport_result.emit(generation, false)
	while generation == transport_generation and socket == polled_socket and polled_socket.get_available_packet_count() > 0:
		var message = JSON.parse_string(polled_socket.get_packet().get_string_from_utf8())
		if message is Dictionary:
			accept(message, generation)


static func valid_snapshot_geometry(snapshot: Dictionary) -> bool:
	var geometry = snapshot.get("geometry")
	if not geometry is Dictionary:
		return false
	for key in ["width", "height", "cell"]:
		if not typeof(geometry.get(key)) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(geometry[key])):
			return false
	var width := int(geometry.width)
	var height := int(geometry.height)
	if width != float(geometry.width) or height != float(geometry.height) or width < 3 or height < 3 or width > 19 or height > 17 or float(geometry.cell) <= 0.0:
		return false
	if not Vector3(width, height, float(geometry.cell)) in [Vector3(13, 11, 52), Vector3(15, 13, 44), Vector3(17, 15, 44), Vector3(19, 17, 44)]:
		return false
	var origin = geometry.get("origin")
	if not origin is Array or origin.size() != 2:
		return false
	for value in origin:
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	for key in ["board", "terrain"]:
		var rows = snapshot.get(key, [])
		if not rows is Array or rows.size() != height:
			return false
		for row in rows:
			if not row is Array or row.size() != width:
				return false
			for tile in row:
				if not typeof(tile) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(tile)):
					return false
	return true


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
			flush_pending_events()
		"game":
			if not valid_snapshot_geometry(message):
				return
			var next_round := int(message.round_id)
			if next_round < int(room.get("round_id", -1)):
				return
			if not game.is_empty() and (next_round < int(game.round_id) or (next_round == int(game.round_id) and int(message.snapshot_seq) <= int(game.snapshot_seq))):
				return
			game = message
			sync_event_round(game)
			game_changed.emit(game)
			flush_pending_events()
		"events":
			accept_events(message)
		"left":
			person_id = 0
			room = {}
			game = {}
			reset_events()
			left_room.emit()
		"error":
			error_received.emit(str(message.get("message", "Server error")))


func reset_events() -> void:
	pending_events.clear()
	event_round = -1
	event_cursor = 0
	event_floor = 0
	events_synced = false


func sync_event_round(snapshot: Dictionary) -> void:
	var round_id := int(snapshot.round_id)
	if round_id == event_round:
		return
	event_round = round_id
	# First state after joining or reconnecting starts at the server cursor; later rounds start fresh.
	event_cursor = 0 if events_synced else int(snapshot.get("event_cursor", 0))
	event_floor = event_cursor
	events_synced = true


func accept_events(message: Dictionary) -> void:
	var round_id := int(message.get("round_id", -1))
	if round_id < int(room.get("round_id", -1)):
		return
	if game.is_empty() or round_id > int(game.round_id) or round_id > int(room.get("round_id", -1)):
		pending_events.append(message)
		while pending_events.size() > MAX_PENDING_EVENT_MESSAGES:
			pending_events.pop_front()
	elif round_id == int(game.round_id):
		deliver_events(round_id, message.get("events", []))


func flush_pending_events() -> void:
	if game.is_empty():
		return
	var waiting := pending_events
	pending_events = []
	for message in waiting:
		var round_id := int(message.get("round_id", -1))
		if round_id < int(room.get("round_id", -1)):
			continue
		if round_id > int(game.round_id) or round_id > int(room.get("round_id", -1)):
			pending_events.append(message)
		elif round_id == int(game.round_id):
			deliver_events(round_id, message.get("events", []))


func deliver_events(round_id: int, events: Array) -> void:
	var fresh: Array = []
	for event in events:
		var event_id := int(event.get("event_id", 0))
		if event_id > event_cursor:
			event_cursor = event_id
			fresh.append(event)
	if not fresh.is_empty():
		events_received.emit(round_id, fresh)


func send(message: Dictionary) -> void:
	if not connected:
		return
	socket.set_target_peer(1)
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())
