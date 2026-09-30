extends RefCounted

const RoomRegistry = preload("res://scripts/room_registry.gd")

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
		var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if message is Dictionary:
			handle(peer_id, message)
		else:
			send_to(peer_id, {"type": "error", "message": "Invalid message"})
	registry.tick(delta)
	snapshot_clock += delta
	if snapshot_clock >= 0.05:
		snapshot_clock = 0.0
		for peer_id in registry.peer_rooms:
			push_state(peer_id)


func handle(peer_id: int, message: Dictionary) -> void:
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
		for person in room.people:
			if person.peer != 0:
				push_state(person.peer)


func valid_direction_array(raw: Variant) -> bool:
	return raw is Array and raw.size() == 2 and typeof(raw[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(raw[1]) in [TYPE_INT, TYPE_FLOAT]


func push_state(peer_id: int) -> void:
	var room := registry.room_for_peer(peer_id)
	if room.is_empty():
		return
	send_to(peer_id, registry.room_view(room))
	if room.game != null:
		send_to(peer_id, registry.game_view(room))


func send_to(peer_id: int, message: Dictionary) -> void:
	socket.set_target_peer(peer_id)
	socket.put_packet(JSON.stringify(message).to_utf8_buffer())


func _peer_disconnected(peer_id: int) -> void:
	registry.leave(peer_id)
