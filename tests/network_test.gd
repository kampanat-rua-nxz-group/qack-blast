extends SceneTree

const RoomServer = preload("res://scripts/room_server.gd")

var server = RoomServer.new()
var clients := [WebSocketMultiplayerPeer.new(), WebSocketMultiplayerPeer.new()]
var inbox := [[], []]
var phase := 0
var elapsed := 0.0
var room_code := ""
var failures := 0
var countdown_seen := [false, false]
var countdown_input_sent := false
var frozen_positions: Array = []


func _initialize() -> void:
	test_input_commands()
	test_client_event_handling()
	if failures:
		quit(1)
		return
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
			for i in range(2):
				for message in inbox[i]:
					if message.get("type") == "room" and message.phase == "countdown":
						countdown_seen[i] = true
			var prepared: Dictionary = server.registry.rooms[room_code]
			if prepared.phase == "countdown":
				if not countdown_input_sent:
					frozen_positions = prepared.game.players.map(func(player): return player.pos)
					request(1, {"type": "input", "direction": [-1, 0], "plant": true, "move_press": [-1, 0]})
					countdown_input_sent = true
				check(prepared.game.round_elapsed == 0.0 and prepared.game.bombs.is_empty() and prepared.game.players.map(func(player): return player.pos) == frozen_positions, "two-client countdown freezes movement bombs and clock")
				return false
			check(countdown_seen == [true, true] and prepared.round_id == 1, "both WebSocket clients observe the same single countdown start")
			inbox[1] = inbox[1].filter(func(message): return message.get("type") != "game" or message.round_elapsed > 0.0)
			for message in inbox[1]:
				if message.get("type") == "game" and message.players.size() == 2:
					var room: Dictionary = server.registry.rooms[room_code]
					room.game.board[9][10] = 0
					request(1, {"type": "input", "direction": [-1, 0], "move_press": [-1, 0]})
					request(1, {"type": "input", "direction": [0, 0], "plant": true})
					phase = 4
					inbox[1].clear()
					break
		4:
			for message in inbox[1]:
				if message.get("type") == "game" and message.bombs.size() == 1 and message.bombs[0].owner == 1:
					for inbox_index in range(2):
						var placed := 0
						for event_message in inbox[inbox_index]:
							if event_message.get("type") == "events" and int(event_message.round_id) == 1:
								for event in event_message.events:
									if event.kind == "bomb_placed" and int(event.owner) == 1:
										placed += 1
						check(placed == 1, "client %d receives the placement event exactly once over WebSocket" % inbox_index)
					var room = server.registry.rooms[room_code]
					if room.game.players[1].pos.x >= room.game.center(Vector2i(11, 9)).x:
						fail("WebSocket short press survives release before next server tick")
						return false
					room.phase = "results"
					inbox[1].clear()
					request(1, {"type": "input", "direction": [0, 0], "plant": false})
					request(1, {"type": "join", "code": room_code, "name": "Duck"})
					phase = 5
					break
		5:
			for message in inbox[1]:
				if message.get("type") == "error":
					if message.message != "Already in a room":
						fail("late gameplay input shows an error on results: %s" % message.message)
						return false
					print("Network checks: %d failure(s)" % failures)
					server.socket.close()
					for client in clients:
						client.close()
					quit(1 if failures else 0)
					break
	return false


func test_input_commands() -> void:
	var input_server = RoomServer.new()
	var registry = input_server.registry
	registry.create_room(10, "A")
	var room: Dictionary = registry.room_for_peer(10)
	registry.join_room(20, room.code, "B")
	registry.start_round(10)
	check(registry.room_for_peer(10).phase == "countdown", "start enters authoritative countdown")
	registry.tick(3.0)
	var game = room.game
	game.board[1][2] = 0
	game.board[1][3] = 0
	var start: Vector2 = game.players[0].pos
	for invalid in [[1, 1], [2, 0], ["1", 0], [1], null, true]:
		input_server.handle(10, {"type": "input", "direction": [1, 0], "plant": true, "move_press": invalid})
	registry.tick(0.016)
	check(game.players[0].pos == start and game.bombs.is_empty(), "malformed and diagonal network press reject entire command")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	game.bombs.clear()
	registry.set_input(10, Vector2.ZERO, false)
	input_server.handle(10, {"type": "input", "direction": [1, 0], "move_press": [1, 0], "slot": 1})
	input_server.handle(10, {"type": "input", "direction": [0, 0]})
	registry.tick(0.016)
	check(game.players[0].pos.x > start.x and game.players[1].pos == game.center(Vector2i(11, 9)), "network short press moves only sender's duck")
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "network short press moves exactly one tile")
	input_server.handle(10, {"type": "input", "direction": [1, 0]})
	registry.tick(0.016)
	input_server.handle(10, {"type": "input", "direction": [0, 0], "move_press": [1, 0]})
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, 0), "network press while moving does not queue a tile")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	input_server.handle(10, {"type": "input", "direction": [1, 0]})
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "network held input expires without heartbeat")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		print("Network input failure: %s" % message)


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


func test_client_event_handling() -> void:
	var received: Array = []
	var client = load("res://scripts/room_client.gd").new()
	client.events_received.connect(func(round_id, events): received.append([round_id, events.map(func(event): return event.event_id)]))
	var game := {"type": "game", "round_id": 1, "snapshot_seq": 1, "event_cursor": 0}
	client.accept({"type": "events", "round_id": 1, "events": [{"event_id": 1, "kind": "bomb_placed"}]})
	check(received.is_empty(), "events before matching game state are queued")
	client.accept(game)
	check(received == [[1, [1]]], "queued events flush once the round state arrives")
	client.accept({"type": "events", "round_id": 1, "events": [{"event_id": 1, "kind": "bomb_placed"}, {"event_id": 2, "kind": "bomb_exploded"}]})
	check(received == [[1, [1]], [1, [2]]], "duplicate (round, event) ids are dropped")
	client.accept({"type": "events", "round_id": 1, "events": [{"event_id": 2, "kind": "bomb_exploded"}]})
	check(received.size() == 2, "fully duplicate batch emits nothing")
	client.accept({"type": "events", "round_id": 2, "events": [{"event_id": 1, "kind": "bomb_placed"}]})
	check(received.size() == 2, "next-round events wait for matching state")
	client.accept({"type": "game", "round_id": 2, "snapshot_seq": 1, "event_cursor": 0})
	check(received.size() == 3 and received[2] == [2, [1]], "round boundary flushes queue and resets id space")
	client.accept({"type": "events", "round_id": 1, "events": [{"event_id": 9, "kind": "bomb_placed"}]})
	check(received.size() == 3, "stale-round events are ignored")
	for i in range(30):
		client.accept({"type": "events", "round_id": 5, "events": [{"event_id": i + 1, "kind": "bomb_placed"}]})
	check(client.pending_events.size() <= client.MAX_PENDING_EVENT_MESSAGES, "pending event queue is bounded")
	client.accept({"type": "left"})
	check(client.pending_events.is_empty(), "queue clears when leaving the room")
	received.clear()
	var late = load("res://scripts/room_client.gd").new()
	late.events_received.connect(func(round_id, events): received.append([round_id, events.map(func(event): return event.event_id)]))
	late.accept({"type": "game", "round_id": 3, "snapshot_seq": 40, "event_cursor": 5})
	late.accept({"type": "events", "round_id": 3, "events": [{"event_id": 4, "kind": "bomb_exploded"}, {"event_id": 5, "kind": "player_eliminated"}, {"event_id": 6, "kind": "round_ended"}]})
	check(received == [[3, [6]]], "late join starts at the snapshot cursor without replaying history")
	client.free()
	late.free()
