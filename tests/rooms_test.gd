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
	check(registry.join_room(50, code, "Duck").ok, "fifth player joins")
	check(registry.join_room(60, code, "Duck").ok, "sixth player joins")
	check(not registry.join_room(70, code, "Duck").ok, "seventh connected player is rejected")
	var room: Dictionary = registry.rooms[code]
	check(room.people.map(func(person): return person.name) == ["Duck", "Duck#1", "Duck#2", "Duck#3", "Duck#4", "Duck#5"], "duplicate nicknames get distinct suffixes")
	check(not registry.choose_map(20, "random") and registry.choose_map(10, "random"), "only host selects the map")
	check(registry.choose_map(10, "pond") and registry.choose_map(10, "frost"), "host can select both new maps")
	check(not registry.choose_map(10, "unknown"), "unknown maps are rejected")
	check(registry.choose_map(10, "random"), "host can return to random map")
	check(not registry.start_round(20) and registry.start_round(10), "only host can start with two to six players")
	check(room.phase == "playing" and room.game.player_count == 6 and room.game.wall_mode == "random", "round uses selected map and six players")
	var encoded := JSON.stringify(registry.game_view(room))
	check(JSON.parse_string(encoded).players.size() == 6, "authoritative snapshot can be sent as JSON")
	var danger_bomb := {"tile": Vector2i(3, 3), "owner": -1, "range": 0, "time": 5.0, "danger": true}
	room.game.bombs.append(danger_bomb)
	check(JSON.parse_string(JSON.stringify(registry.game_view(room))).bombs[0].get("danger", false), "snapshot marks neutral danger bombs")
	room.game.bombs.erase(danger_bomb)
	check(not registry.choose_map(10, "fixed"), "map cannot change during a round")
	check(registry.set_input(20, Vector2.RIGHT, true), "participant sends own input")
	registry.tick(0.016)
	check(room.game.bombs.size() == 1 and room.game.bombs[0].owner == 1, "server applies input to the matching player only")
	registry.leave(10)
	check(room.host == room.people[1].id, "host transfers to longest-connected remaining player")
	check(room.people[0].peer == 0 and room.people[0].disconnect_remaining > 0.0, "disconnected avatar waits thirty seconds")
	check(room.directions[0] == Vector2.ZERO, "disconnected avatar stays stationary")
	check(registry.join_room(70, code, "Duck").ok, "new join after disconnect is a spectator")
	check(room.people.back().name == "Duck#6" and room.people.back().slot == -1, "rejoin is a new participant with a new name")
	registry.tick(30.0)
	check(not room.game.players[0].alive, "disconnected avatar is eliminated after thirty seconds")
	check(room.people[0].scores.kills == 0, "disconnect elimination awards no Kill")
	for i in range(room.game.players.size()):
		room.game.players[i].alive = i == 2
	room.game.resolve_round()
	registry.tick(0.0)
	check(room.people[2].scores.wins == 1, "winner score persists on participant record")
	check(not registry.choose_map(30, "frost") and not registry.start_round(30), "guest cannot change map or replay during results")
	check(registry.choose_map(20, "frost"), "new host changes map during results")
	check(registry.start_round(20), "new host starts a rematch")
	check(room.code == code and room.people.size() == 7 and room.game.wall_mode == "frost", "rematch keeps room and uses chosen map")
	check(room.game.scores[1].wins == 1, "rematch carries the surviving participant's score")
	for peer_id in [20, 30, 40, 50, 60, 70]:
		registry.leave(peer_id)
	check(not registry.rooms.has(code), "room and scores disappear when last peer leaves")
	test_input_press_intent()
	test_map_round_snapshots()
	finish()


func test_map_round_snapshots() -> void:
	var Registry = load("res://scripts/room_registry.gd")
	for mode in ["fixed", "random", "pond", "frost", "night"]:
		var registry = Registry.new()
		var created: Dictionary = registry.create_room(100, "A")
		registry.join_room(200, created.code, "B")
		check(registry.choose_map(100, mode) and registry.start_round(100), "%s starts through host selection" % mode)
		var room: Dictionary = registry.rooms[created.code]
		var game = room.game
		var special: int = {"fixed": 0, "random": 3, "pond": 4, "frost": 5, "night": 2}[mode]
		game.pickups[game.tile_at(game.players[0].pos)] = special
		game.round_elapsed = 180.0
		game.schedule_hazards(180.0)
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
		check(snapshot.pickups.any(func(pickup): return pickup.kind == special), "%s special pickup reaches snapshot" % mode)
		check(not snapshot.bombs.is_empty() if mode == "fixed" else not snapshot.hazards.is_empty(), "%s sudden-death warning reaches snapshot" % mode)
		registry.tick(0.0)
		check(room.phase == "playing", "%s round continues with multiple ducks alive" % mode)
		game.players[0].alive = false
		game.resolve_round()
		registry.tick(0.0)
		check(room.phase == "results" and game.result == "PLAYER 2 WINS", "%s resolves after one survivor" % mode)
		check(registry.start_round(100), "%s starts rematch" % mode)
		room.game.players[0].alive = false
		room.game.players[1].alive = false
		room.game.resolve_round()
		registry.tick(0.0)
		check(room.phase == "results" and room.game.result == "DRAW", "%s draws when last ducks die together" % mode)


func test_input_press_intent() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	registry.create_room(10, "A")
	var room: Dictionary = registry.room_for_peer(10)
	registry.join_room(20, room.code, "B")
	registry.start_round(10)
	var game = room.game
	game.board[1][2] = 0
	game.board[1][3] = 0
	var start: Vector2 = game.players[0].pos
	check(not registry.set_input(10, Vector2.RIGHT, true, Vector2(1, 1)), "diagonal press rejects entire input")
	check(not registry.set_input(10, Vector2.RIGHT, true, Vector2(2, 0)), "noncardinal press rejects entire input")
	registry.tick(0.016)
	check(game.players[0].pos == start and game.bombs.is_empty(), "invalid press cannot move or plant")
	check(registry.set_input(10, Vector2.RIGHT, false, Vector2.RIGHT), "cardinal press accepted")
	registry.set_input(10, Vector2.ZERO, false)
	registry.tick(0.016)
	check(game.players[0].pos.x > start.x, "press then release between ticks starts movement from rest")
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "short press produces exactly one tile step")
	registry.set_input(10, Vector2.RIGHT, false)
	registry.tick(0.016)
	registry.set_input(10, Vector2.ZERO, false, Vector2.RIGHT)
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, 0), "press during movement does not queue another step")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	registry.set_input(10, Vector2.RIGHT, false)
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "expired held input stops after current tile")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	registry.set_input(10, Vector2.UP, false, Vector2.UP)
	registry.set_input(10, Vector2.ZERO, false)
	registry.tick(0.016)
	check(game.players[0].pos == start, "press intent respects wall collision")
	registry.set_input(10, Vector2.RIGHT, false, Vector2.RIGHT)
	registry.leave(10)
	registry.tick(0.016)
	check(game.players[0].pos == start, "disconnect clears pending press before next tick")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Room checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
