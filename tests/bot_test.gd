extends SceneTree

var failures := 0


func _initialize() -> void:
	test_profiles()
	test_observation_detached()
	test_night_visibility_boundary()
	test_night_memory_shuffle()
	test_observation_hidden_state_independence()
	print("Bot checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func test_profiles() -> void:
	var expected := {"easy": [0.60, 0.90, 0.0, 1], "medium": [0.30, 0.45, 0.0, 4], "hard": [0.15, 0.25, 0.50, 8], "extreme": [0.08, 0.15, 1.00, 12]}
	var profiles = load("res://scripts/bot_profiles.gd")
	check(profiles != null, "profile contract exists")
	if profiles == null:
		return
	for id in expected:
		var p: Dictionary = profiles.get_profile(id)
		check([p.interval_min, p.interval_max, p.prediction_seconds, p.candidate_limit] == expected[id], "exact profile " + id)
		check(profiles.is_valid(id), "valid canonical identifier " + id)
		p.interval_min = -1.0
		check(profiles.get_profile(id).interval_min == expected[id][0], "returned profile is detached " + id)
	check(profiles.get_profile("extream").is_empty(), "reject misspelled identifier")
	check(not profiles.is_valid("unknown"), "reject unknown identifier")


func observation(game, memory: Dictionary = {}) -> Dictionary:
	var adapter = load("res://scripts/bot_observation.gd")
	check(adapter != null, "fair observation adapter exists")
	return {} if adapter == null else adapter.capture(game, 0, memory)


func observation_game(mode: String = "night"):
	var game = load("res://scripts/arena_game.gd").new()
	game.wall_mode = mode
	game.rng.seed = 42
	game.new_round()
	return game


func test_observation_detached() -> void:
	var game = observation_game("fixed")
	game.place_bomb(0)
	game.flames.append({"tile": Vector2i(3, 1), "time": 0.4, "owner": 1, "distance": 1})
	game.pickups[Vector2i(4, 1)] = 2
	game.hazards.append({"kind": "flood", "tiles": [Vector2i(9, 9)], "time": 5.0})
	var rng_state = game.rng.state
	var o := observation(game)
	if o.is_empty():
		return
	check(o.self.pos == game.players[0].pos and o.self.tile == Vector2i(1, 1), "own position and tile")
	check(o.self.move_target == game.move_targets[0] and o.self.safe_bomb == Vector2i(1, 1), "own committed state")
	check(o.players.size() == 1 and not o.players[0].has("move_target"), "opponent has public state only")
	o.board[1][1] = 99
	o.terrain[1][1] = 99
	o.bombs[0].time = 99
	o.flames[0].time = 99
	o.hazards[0].tiles.clear()
	o.pickups.clear()
	o.self.pos = Vector2.ZERO
	check(game.board[1][1] != 99 and game.terrain[1][1] != 99 and game.bombs[0].time == 2.5 and game.flames[0].time == 0.4, "arrays detached from authoritative state")
	check(game.hazards[0].tiles.size() == 1 and game.pickups.size() == 1 and game.players[0].pos != Vector2.ZERO, "nested dictionaries detached")
	check(game.rng.state == rng_state, "capture never advances game RNG")
	var adapter = load("res://scripts/bot_observation.gd")
	check(adapter.capture(game, -1, {}).is_empty(), "invalid slot rejected")
	game.players[0].alive = false
	check(adapter.capture(game, 0, {}).is_empty(), "dead slot rejected")


func test_night_visibility_boundary() -> void:
	var game = observation_game()
	# Exact representable boundary avoids world-origin subtraction rounding.
	game.CELL = 10.0
	game.ORIGIN = Vector2(-15, -15)
	game.players[0].pos = Vector2.ZERO
	var edge_pos: Vector2 = game.players[0].pos + Vector2(3.4 * game.CELL, 0)
	game.players[1].pos = edge_pos
	game.pickups[Vector2i(10, 9)] = 2
	game.hazards.append({"kind": "closing_walls", "tiles": [Vector2i(10, 9)], "time": 5.0})
	game.bombs.append({"tile": Vector2i(10, 9), "owner": -1, "range": 0, "time": 5.0, "danger": true})
	var o := observation(game)
	if o.is_empty():
		return
	check(o.players.is_empty() and o.pickups.is_empty(), "fully dark opponents and pickups absent")
	check(o.hazards.size() == 1 and o.bombs.size() == 1, "announced warnings globally visible")
	check(o.board[1][5] == -1, "unseen static tile unknown")
	game.players[0].vision += 1
	o = observation(game)
	check(o.board[1][5] != -1 and o.players.size() == 1, "Sight expands cells and entity visibility")


func test_night_memory_shuffle() -> void:
	var game = observation_game()
	var memory := {}
	var o := observation(game, memory)
	if o.is_empty():
		return
	var known = o.board[1][1]
	game.players[0].pos = game.center(Vector2i(11, 9))
	game.round_elapsed = 59.0
	o = observation(game, memory)
	check(o.board[1][1] == known, "static tiles remembered outside vision")
	game.round_elapsed = 60.0
	o = observation(game, memory)
	check(o.board[1][1] == -1 and o.terrain[1][1] == -1, "first shuffle invalidates unseen interior")
	game.players[0].pos = game.center(Vector2i(1, 1))
	observation(game, memory)
	game.players[0].pos = game.center(Vector2i(11, 9))
	game.round_elapsed = 120.0
	o = observation(game, memory)
	check(o.board[1][1] == -1 and o.board[0][1] == 1, "second shuffle preserves seen boundary knowledge")


func test_observation_hidden_state_independence() -> void:
	var a = observation_game()
	var b = observation_game()
	b.board[9][10] = 2 if a.board[9][10] != 2 else 0
	b.terrain[9][10] = 2
	b.move_targets[1] = b.center(Vector2i(9, 9))
	b.players[1].safe_bomb = Vector2i(10, 9)
	b.bombs.append({"tile": Vector2i(10, 9), "owner": 1, "range": 5, "time": 1.0})
	b.pickups[Vector2i(10, 9)] = 1
	b.pending_events.append({"kind": "bomb_placed", "tile": [10, 9]})
	b.rng.seed = 999
	var first := observation(a)
	if first.is_empty():
		return
	check(first == observation(b), "hidden board bombs targets events RNG do not affect observation")
	var memory := {}
	a.place_bomb(0)
	observation(a, memory)
	a.players[0].pos = a.center(Vector2i(11, 9))
	a.bombs.clear()
	a.round_elapsed = 1.0
	var o := observation(a, memory)
	check(o.bombs.size() == 1 and is_equal_approx(o.bombs[0].time, 1.5), "hidden bomb removal does not refresh memory")
	var other_memory := memory.duplicate(true)
	var before_hidden_change := observation(a, other_memory)
	a.bombs.append({"tile": Vector2i(1, 1), "owner": 0, "range": 6, "time": 0.1, "kick_direction": Vector2i.RIGHT})
	check(observation(a, memory) == before_hidden_change, "hidden kick range fuse and existence do not refresh memory")
	a.players[0].pos = a.center(Vector2i(1, 1))
	o = observation(a, memory)
	check(o.bombs.size() == 1 and o.bombs[0].range == 6, "visible bomb merges once and refreshes allowed data")
	a.players[0].pos = a.center(Vector2i(11, 9))
	a.bombs.clear()
	a.round_elapsed = 1.5
	o = observation(a, memory)
	check(o.bombs.size() == 1 and o.bombs[0].time < 0.0, "remember bomb through projected flame lifetime")
	a.round_elapsed = 1.61
	check(observation(a, memory).bombs.is_empty(), "retire bomb after projected blast lifetime")
