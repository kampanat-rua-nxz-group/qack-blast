extends SceneTree

var failures := 0


func _initialize() -> void:
	check(load("res://scripts/room_server.gd").new() != null, "WebSocket server script parses")
	if not ResourceLoader.exists("res://scripts/room_registry.gd"):
		check(false, "room registry exists")
		finish()
		return
	var registry = load("res://scripts/room_registry.gd").new()
	registry.rng.seed = 7
	var created: Dictionary = registry.create_room(10, "Duck")
	check(created.ok and created.code.length() == 6, "host receives a six-character room code")
	var code: String = created.code
	check(not registry.join_room(20, "BADCODE", "Duck").ok, "unknown room code is rejected")
	check(registry.join_room(20, code, "Duck").ok, "friend joins with room code")
	check(registry.join_room(30, code, "Duck").ok, "third player joins")
	check(registry.join_room(40, code, "Duck").ok, "fourth player joins")
	check(not registry.join_room(50, code, "Duck").ok, "fifth connected player is rejected")
	var room: Dictionary = registry.rooms[code]
	check(room.people.map(func(person): return person.name) == ["Duck", "Duck#1", "Duck#2", "Duck#3"], "duplicate nicknames get distinct suffixes")
	check(not registry.choose_map(20, "random") and registry.choose_map(10, "random"), "only host selects the map")
	check(not registry.start_round(20) and registry.start_round(10), "only host can start with two to four players")
	check(room.phase == "playing" and room.game.player_count == 4 and room.game.wall_mode == "random", "round uses selected map and four players")
	var encoded := JSON.stringify(registry.game_view(room))
	check(JSON.parse_string(encoded).players.size() == 4, "authoritative snapshot can be sent as JSON")
	check(not registry.choose_map(10, "fixed"), "map cannot change during a round")
	check(registry.set_input(20, Vector2.RIGHT, true), "participant sends own input")
	registry.tick(0.016)
	check(room.game.bombs.size() == 1 and room.game.bombs[0].owner == 1, "server applies input to the matching player only")
	registry.leave(10)
	check(room.host == room.people[1].id, "host transfers to longest-connected remaining player")
	check(room.people[0].peer == 0 and room.people[0].disconnect_remaining > 0.0, "disconnected avatar waits thirty seconds")
	check(room.directions[0] == Vector2.ZERO, "disconnected avatar stays stationary")
	check(registry.join_room(50, code, "Duck").ok, "new join after disconnect is a spectator")
	check(room.people.back().name == "Duck#4" and room.people.back().slot == -1, "rejoin is a new participant with a new name")
	registry.tick(30.0)
	check(not room.game.players[0].alive, "disconnected avatar is eliminated after thirty seconds")
	check(room.people[0].scores.kills == 0, "disconnect elimination awards no Kill")
	for i in range(room.game.players.size()):
		room.game.players[i].alive = i == 2
	room.game.resolve_round()
	registry.tick(0.0)
	check(room.people[2].scores.wins == 1, "winner score persists on participant record")
	check(registry.start_round(20), "new host starts a rematch")
	check(room.game.scores[1].wins == 1, "rematch carries the surviving participant's score")
	for peer_id in [20, 30, 40, 50]:
		registry.leave(peer_id)
	check(not registry.rooms.has(code), "room and scores disappear when last peer leaves")
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Room checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
