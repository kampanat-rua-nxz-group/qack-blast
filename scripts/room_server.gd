extends RefCounted

const RoomRegistry = preload("res://scripts/room_registry.gd")
const BotProfiles = preload("res://scripts/bot_profiles.gd")

var registry = RoomRegistry.new()
var socket := WebSocketMultiplayerPeer.new()
var snapshot_clock := 0.0


func listen(port: int, bind_address: String = "127.0.0.1") -> Error:
	registry.rng.randomize()
	socket.peer_disconnected.connect(_peer_disconnected)
	return socket.create_server(port, bind_address)


func poll(delta: float) -> void:
	socket.poll()
	while socket.get_available_packet_count() > 0:
		var peer_id := socket.get_packet_peer()
		var packet_text := socket.get_packet().get_string_from_utf8()
		var message = JSON.parse_string(packet_text)
		if message is Dictionary:
			handle(peer_id, message, packet_text)
		else:
			send_to(peer_id, {"type": "error", "message": "Invalid message"})
	registry.tick(delta)
	for room in registry.rooms.values():
		push_room_events(room)
	snapshot_clock += delta
	if snapshot_clock >= 0.05:
		snapshot_clock = 0.0
		for room in registry.rooms.values():
			push_room_state(room)


func handle(peer_id: int, message: Dictionary, raw_message: String = "") -> void:
	var kind: String = str(message.get("type", ""))
	var result: Dictionary = {}
	match kind:
		"create":
			result = registry.create_room(peer_id, str(message.get("name", "")))
		"join":
			result = registry.join_room(peer_id, str(message.get("code", "")), str(message.get("name", "")))
		"leave":
			registry.leave(peer_id)
			send_to(peer_id, {"type": "left"})
			return
		"map":
			result = {"ok": registry.choose_map(peer_id, str(message.get("mode", "")))}
		"start":
			result = {"ok": registry.start_round(peer_id)}
		"input":
			var raw = message.get("direction", [])
			var raw_press = message.get("move_press", [0, 0])
			if valid_direction_array(raw) and valid_direction_array(raw_press):
				result = {"ok": registry.set_input(peer_id, Vector2(raw[0], raw[1]), message.get("plant", false) == true, Vector2(raw_press[0], raw_press[1]))}
		"bot_add", "bot_remove", "bot_difficulty":
			result = dispatch_bot_message(peer_id, message, raw_message)
		"": 
			pass
	if not result.get("ok", false):
		if kind == "input":
			return
		send_to(peer_id, {"type": "error", "message": str(result.get("error", "Action rejected"))})
		return
	if kind in ["create", "join"]:
		send_to(peer_id, {"type": "joined", "code": result.code, "person_id": result.person_id, "name": result.name})
	if kind != "input":
		var room := registry.room_for_peer(peer_id)
		push_room_state(room)


func dispatch_bot_message(peer_id: int, message: Dictionary, raw_message: String = "") -> Dictionary:
	var kind: String = message.get("type", "") if message.get("type", "") is String else ""
	match kind:
		"bot_add":
			var difficulty: Variant = message.get("difficulty", "medium")
			if typeof(difficulty) != TYPE_STRING or not BotProfiles.is_valid(difficulty):
				return {"ok": false, "error": "Unknown bot difficulty"}
			return registry.add_bot(peer_id, difficulty)
		"bot_remove", "bot_difficulty":
			var person_id: Variant = message.get("person_id", null)
			if not valid_person_id(person_id, raw_message):
				return {"ok": false, "error": "Invalid participant ID"}
			if kind == "bot_remove":
				return registry.remove_bot(peer_id, person_id)
			var difficulty: Variant = message.get("difficulty", null)
			if typeof(difficulty) != TYPE_STRING or not BotProfiles.is_valid(difficulty):
				return {"ok": false, "error": "Unknown bot difficulty"}
			return registry.set_bot_difficulty(peer_id, person_id, difficulty)
	return {"ok": false, "error": "Action rejected"}


func valid_person_id(value: Variant, raw_message: String = "") -> bool:
	if typeof(value) == TYPE_INT:
		return value > 0
	# Godot's JSON parser represents integer tokens as floats. Preserve strict
	# protocol typing by checking the original token before converting it.
	if typeof(value) != TYPE_FLOAT or not is_finite(value) or value <= 0.0 or floorf(value) != value or raw_message.is_empty():
		return false
	var matcher := RegEx.new()
	if matcher.compile("\\\"person_id\\\"\\s*:\\s*([0-9]+)\\s*[,}]") != OK:
		return false
	var token := matcher.search(raw_message)
	return token != null and float(token.get_string(1)) == value


func valid_direction_array(raw: Variant) -> bool:
	return raw is Array and raw.size() == 2 and typeof(raw[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(raw[1]) in [TYPE_INT, TYPE_FLOAT]


func push_state(peer_id: int) -> void:
	var room := registry.room_for_peer(peer_id)
	if room.is_empty():
		return
	send_to(peer_id, registry.room_view(room))
	if room.game != null:
		send_to(peer_id, registry.game_view(room))


func push_room_events(room: Dictionary) -> void:
	var events: Array = registry.take_room_events(room)
	if events.is_empty():
		return
	var message := {"type": "events", "round_id": room.round_id, "events": events}
	for person in room.people:
		if person.peer != 0:
			send_to(person.peer, message)


func push_room_state(room: Dictionary) -> void:
	# Materialize once so every recipient sees the same sequence and authority.
	var room_snapshot: Dictionary = registry.room_view(room)
	var game_snapshot: Dictionary = registry.game_view(room) if room.game != null else {}
	for person in room.people:
		if person.peer != 0:
			send_to(person.peer, room_snapshot)
			if not game_snapshot.is_empty():
				send_to(person.peer, game_snapshot)


func send_to(peer_id: int, message: Dictionary) -> void:
	socket.set_target_peer(peer_id)
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())


func _peer_disconnected(peer_id: int) -> void:
	registry.leave(peer_id)
