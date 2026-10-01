extends SceneTree

const RoomServer = preload("res://scripts/room_server.gd")
var server = RoomServer.new()
var clients: Array = []
var inbox: Array = []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if server.listen(19090) != OK:
		check(false, "ten-client loopback listens")
		quit(1)
		return
	for i in range(11):
		var client := WebSocketMultiplayerPeer.new()
		clients.append(client)
		inbox.append([])
		check(client.create_client("ws://127.0.0.1:19090") == OK, "client %d opens socket" % i)
		await pump(0.1)
	for attempt in range(100):
		await pump(0.02)
		if clients.all(func(client): return client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED):
			break
	check(clients.all(func(client): return client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "all eleven sockets finish handshake")
	request(0, {"type": "create", "name": "Duck"})
	var joined: Dictionary = await receive(0, "joined")
	if joined.is_empty():
		finish()
		return
	var code: String = joined.code
	for i in range(1, 10):
		request(i, {"type": "join", "code": code, "name": "Duck"})
		var admitted: Dictionary = await receive(i, "joined")
		check(not admitted.is_empty() and admitted.get("name", "") == "Duck#%d" % i, "client %d admitted with nickname suffix" % (i + 1))
	request(10, {"type": "join", "code": code, "name": "Overflow"})
	var rejected: Dictionary = await receive(10, "error")
	check(rejected.get("message", "") == "Room is full", "eleventh WebSocket receives full-room error")
	var room: Dictionary = server.registry.rooms[code]
	if room.people.size() != 10:
		finish()
		return
	request(0, {"type": "start"})
	await pump(0.1)
	check(room.phase == "countdown" and room.game.players.size() == 10, "ten-client countdown prepares ten ducks")
	for i in range(10):
		check(inbox[i].any(func(m): return m.get("type") == "room" and m.phase == "countdown"), "client %d receives countdown" % i)
	request(9, {"type": "input", "direction": [1, 0], "plant": true})
	await pump(0.1)
	check(room.game.bombs.is_empty() and room.game.round_elapsed == 0.0, "slot 9 countdown input leaves game frozen")
	request(9, {"type": "leave"})
	await receive(9, "left")
	await pump(0.1)
	check(room.phase == "lobby" and room.game == null, "tenth participant departure cancels countdown")
	request(9, {"type": "join", "code": code, "name": "Duck"})
	await receive(9, "joined")
	request(0, {"type": "start"})
	await pump(3.15)
	check(room.phase == "playing" and room.round_id == 2, "fresh ten-client countdown starts exactly one new round")
	var identities: Array = room.lineup.duplicate()
	var avatars: Array = room.game.players.map(func(p): return p.avatar_id)
	var game = room.game
	var start: Vector2 = game.players[9].pos
	var tile: Vector2i = game.tile_at(start)
	game.board[tile.y][tile.x + 1] = game.OPEN
	request(9, {"type": "input", "direction": [1, 0], "move_press": [1, 0], "slot": 0})
	request(9, {"type": "input", "direction": [0, 0], "plant": true})
	await pump(0.45)
	check(game.players[9].pos == start + Vector2(game.CELL, 0), "slot 9 short press moves exactly one tile over socket")
	check(game.bombs.size() == 1 and game.bombs[0].owner == 9, "tenth client plants bomb owned by slot 9")
	for i in range(10):
		check(inbox[i].any(func(m): return m.get("type") == "game" and m.bombs.any(func(b): return int(b.owner) == 9)), "client %d receives slot 9 bomb snapshot" % i)
		check(inbox[i].any(func(m): return m.get("type") == "events" and m.events.any(func(e): return e.kind == "bomb_placed" and int(e.owner) == 9)), "client %d receives slot 9 placement feedback" % i)
	request(0, {"type": "leave"})
	await receive(0, "left")
	await pump(0.1)
	check(room.host == identities[1] and game.players[0].alive, "host departure transfers host while preserving grace duck")
	request(10, {"type": "join", "code": code, "name": "Spectator"})
	await receive(10, "joined")
	check(room.people.back().slot == -1 and game.players.size() == 10 and room.lineup == identities, "replacement spectates without changing ten-duck lineup")
	request(10, {"type": "input", "direction": [1, 0], "plant": true})
	await pump(0.1)
	check(game.bombs.size() == 1 and game.players.map(func(p): return p.avatar_id) == avatars, "spectator cannot plant and retains visual identities")
	game.bombs.clear()
	# Resolve authority deterministically; transport and client observations use real sockets.
	for i in range(10):
		game.scores[i].kills = i
		game.players[i].alive = i == 9
	game.resolve_round()
	await pump(0.1)
	check(room.phase == "results" and game.scores[9].wins == 1, "tenth duck wins and reaches authoritative results")
	for i in range(1, 11):
		check(inbox[i].any(func(m): return m.get("type") == "room" and m.phase == "results"), "connected client %d observes results" % i)
	request(1, {"type": "start"})
	await pump(0.1)
	check(room.phase == "countdown" and room.game.players.size() == 10 and room.round_id == 3, "new host starts ten-client rematch")
	for i in range(1, 10):
		var slot: int = room.lineup.find(identities[i])
		check(slot == i - 1 and room.game.players[slot].avatar_id == avatars[i] and room.game.scores[slot].kills == i, "rematch preserves participant %d identity and score after slot change" % i)
	check(room.game.scores[8].wins == 1 and room.people.back().slot == 9, "winner retains Win and spectator joins slot 9")
	await pump(3.1)
	for i in range(1, 11):
		check(inbox[i].any(func(m): return m.get("type") == "game" and int(m.round_id) == 3 and m.players.size() == 10), "client %d receives ten-duck rematch" % i)
	finish()

func pump(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	var previous := Time.get_ticks_msec()
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_msec()
		server.poll(float(now - previous) / 1000.0)
		previous = now
		for i in range(clients.size()):
			clients[i].poll()
			while clients[i].get_available_packet_count() > 0:
				var message = JSON.parse_string(clients[i].get_packet().get_string_from_utf8())
				if message is Dictionary:
					inbox[i].append(message)

func receive(i: int, kind: String) -> Dictionary:
	for attempt in range(60):
		await pump(0.02)
		for j in range(inbox[i].size()):
			if inbox[i][j].get("type") == kind:
				var message: Dictionary = inbox[i][j]
				inbox[i].remove_at(j)
				return message
	check(false, "client %d receives %s before timeout" % [i, kind])
	return {}

func request(i: int, message: Dictionary) -> void:
	clients[i].set_target_peer(1)
	clients[i].put_packet(JSON.stringify(message).to_utf8_buffer())

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func finish() -> void:
	server.socket.close()
	for client in clients:
		client.close()
	print("Ten-client network checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
