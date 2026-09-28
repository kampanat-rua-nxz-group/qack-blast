extends SceneTree

const RoomServer = preload("res://scripts/room_server.gd")

var server = RoomServer.new()
var clients := [WebSocketMultiplayerPeer.new(), WebSocketMultiplayerPeer.new()]
var inbox := [[], []]
var phase := 0
var elapsed := 0.0
var room_code := ""


func _initialize() -> void:
	var error := server.listen(19087)
	if error != OK:
		fail("server listens on localhost: %d" % error)
		return
	for client in clients:
		error = client.create_client("ws://127.0.0.1:19087")
		if error != OK:
			fail("client connects: %d" % error)
			return


func _process(delta: float) -> bool:
	server.poll(delta)
	for i in range(clients.size()):
		var client: WebSocketMultiplayerPeer = clients[i]
		client.poll()
		while client.get_available_packet_count() > 0:
			var message = JSON.parse_string(client.get_packet().get_string_from_utf8())
			if message is Dictionary:
				inbox[i].append(message)
	elapsed += delta
	if elapsed > 8.0:
		fail("network handshake timed out at phase %d" % phase)
		return false
	match phase:
		0:
			if clients[0].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and clients[1].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				request(0, {"type": "create", "name": "Duck"})
				phase = 1
		1:
			for message in inbox[0]:
				if message.get("type") == "joined":
					room_code = message.code
					request(1, {"type": "join", "code": room_code, "name": "Duck"})
					phase = 2
					break
		2:
			for message in inbox[1]:
				if message.get("type") == "room" and message.people.size() == 2:
					request(0, {"type": "start"})
					phase = 3
					break
		3:
			for message in inbox[1]:
				if message.get("type") == "game" and message.players.size() == 2:
					request(1, {"type": "input", "direction": [0, 0], "plant": true})
					phase = 4
					inbox[1].clear()
					break
		4:
			for message in inbox[1]:
				if message.get("type") == "game" and message.bombs.size() == 1 and message.bombs[0].owner == 1:
					print("Network checks: 0 failure(s)")
					server.socket.close()
					for client in clients:
						client.close()
					quit(0)
					break
	return false


func request(i: int, message: Dictionary) -> void:
	clients[i].set_target_peer(1)
	clients[i].put_packet(JSON.stringify(message).to_utf8_buffer())


func fail(message: String) -> void:
	push_error(message)
	print("Network checks: 1 failure(s)")
	server.socket.close()
	for client in clients:
		client.close()
	quit(1)
