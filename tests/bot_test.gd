extends SceneTree

var failures := 0


func _initialize() -> void:
	test_profiles()
	test_observation_detached()
	test_night_visibility_boundary()
	test_night_memory_shuffle()
	test_observation_hidden_state_independence()
	test_chain_forecast()
	test_same_batch_crate_forecast()
	test_moving_bomb_forecast()
	test_hazard_forecast()
	test_route_wait_and_margin()
	test_pond_route_duration()
	test_frost_committed_slide()
	test_own_bomb_egress()
	test_unknown_and_budget()
	test_moving_blocker_stops_immediately()
	test_hazard_then_fuse_order()
	test_collision_radius_and_kick_rejection()
	test_candidate_committed_rejected()
	test_slide_blocker_arrival_uncertainty()
	test_escape_route_engine_survival()
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


func navigation():
	var script = load("res://scripts/bot_navigation.gd")
	check(script != null and script.can_instantiate(), "timed navigation contract exists")
	return script if script != null and script.can_instantiate() else null


func make_open_game(mode: String = "fixed", count: int = 2):
	var game = load("res://scripts/arena_game.gd").new()
	game.wall_mode = mode
	game.player_count = count
	game.rng.seed = 7
	game.new_round()
	for y in range(1, game.HEIGHT - 1):
		for x in range(1, game.WIDTH - 1):
			if game.board[y][x] == game.CRATE:
				game.board[y][x] = game.OPEN
	return game


func observe(game, slot: int = 0) -> Dictionary:
	return load("res://scripts/bot_observation.gd").capture(game, slot, {})


func test_bomb(tile: Vector2i, time: float, blast_range: int = 1) -> Dictionary:
	return {"tile": tile, "owner": 1, "range": blast_range, "time": time}


func has_interval(intervals: Dictionary, tile: Vector2i, start: float, end: float) -> bool:
	for span in intervals.get(tile, []):
		if is_equal_approx(span[0], start) and (span[1] == end or is_equal_approx(span[1], end)):
			return true
	return false


func engine_flame(game, tile: Vector2i) -> bool:
	for flame in game.flames:
		if flame.tile == tile:
			return true
	return false


func test_chain_forecast() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.bombs = [test_bomb(Vector2i(3, 1), 0.5, 2), test_bomb(Vector2i(5, 1), 2.5, 1)]
	var f: Dictionary = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(6, 1), 0.5, 1.0), "chain uses early fuse and complete flame lifetime")
	check(is_equal_approx(f.horizon, 1.2), "resolved chain horizon includes final flame and margin")
	game.bombs[1].time = 8.0
	f = nav.forecast(observe(game))
	check(f.complete and is_equal_approx(f.horizon, 1.2), "guaranteed early chain resolves even a fuse originally beyond cap")
	game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.bombs.is_empty() and engine_flame(game, Vector2i(6, 1)), "engine confirms early chain at 0.50")
	game = make_open_game()
	game.bombs = [test_bomb(Vector2i(3, 1), -0.2, 1)]
	f = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(4, 1), 0.0, 0.3), "remembered detonation retains only remaining flame lifetime")


func test_same_batch_crate_forecast() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.board[1][4] = game.CRATE
	game.bombs = [test_bomb(Vector2i(3, 1), 0.5, 4), test_bomb(Vector2i(2, 1), 0.5, 5)]
	var f: Dictionary = nav.forecast(observe(game))
	check(not f.danger_intervals.has(Vector2i(5, 1)), "same-batch crate blocks every ray")
	game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.board[1][4] == game.OPEN and not engine_flame(game, Vector2i(5, 1)), "engine agrees crate blocks whole batch")


func test_moving_bomb_forecast() -> void:
	var nav = navigation()
	if nav == null:
		return
	for blocker in ["wall", "crate", "bomb", "edge"]:
		var game = make_open_game("frost")
		game.players[0].pos = game.center(Vector2i(1, 9))
		game.players[1].pos = game.center(Vector2i(11, 9))
		game.bombs = [test_bomb(Vector2i(3, 1), 1.0, 0)]
		if blocker == "wall":
			game.board[1][6] = game.WALL
		elif blocker == "crate":
			game.board[1][6] = game.CRATE
		elif blocker == "bomb":
			game.bombs.append(test_bomb(Vector2i(6, 1), 2.5, 0))
		else:
			game.bombs[0].tile = Vector2i(9, 1)
		check(game.try_kick_bomb(game.bombs[0].tile, Vector2i.RIGHT), "engine accepts fixture kick " + blocker)
		var f: Dictionary = nav.forecast(observe(game))
		var destination := Vector2i(11, 1) if blocker == "edge" else Vector2i(5, 1)
		check(has_interval(f.danger_intervals, destination, 1.0, 1.5), "kick stops at " + blocker)
		for i in range(20):
			game.step(0.05, [Vector2.ZERO, Vector2.ZERO], [false, false])
		check(engine_flame(game, destination), "actual kicked bomb agrees " + blocker)
	var game = make_open_game("frost")
	game.bombs = [test_bomb(Vector2i(3, 1), 2.5, 0), test_bomb(Vector2i(5, 3), 0.5, 2)]
	check(game.try_kick_bomb(Vector2i(3, 1), Vector2i.RIGHT), "chain fixture kick starts")
	var f: Dictionary = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(5, 1), 0.5, 1.0), "moving bomb chains at its predicted tile")
	for i in range(10):
		game.step(0.05, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.bombs.is_empty() and engine_flame(game, Vector2i(5, 1)), "actual kicked bomb chains at predicted tile")


func test_hazard_forecast() -> void:
	var nav = navigation()
	if nav == null:
		return
	for kind in ["random_burst", "blizzard", "flood", "closing_walls"]:
		var game = make_open_game()
		game.bombs = [test_bomb(Vector2i(3, 1), 2.5, 1)]
		game.hazards = [{"kind": kind, "tiles": [Vector2i(3, 1)], "time": 0.5}]
		var f: Dictionary = nav.forecast(observe(game))
		game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
		if kind in ["flood", "closing_walls"]:
			check(has_interval(f.blocked_intervals, Vector2i(3, 1), 0.5, INF), "closure remains blocked " + kind)
			check(not f.danger_intervals.has(Vector2i(4, 1)) and game.bombs.is_empty(), "closure removes bomb without blast " + kind)
		else:
			check(has_interval(f.danger_intervals, Vector2i(4, 1), 0.5, 1.0), "hazard triggers adjacent blast " + kind)
			check(game.bombs.is_empty() and engine_flame(game, Vector2i(4, 1)), "engine confirms hazard chain " + kind)
	var game = make_open_game()
	game.board[1][4] = game.WALL
	game.bombs = [{"tile": Vector2i(3, 1), "owner": -1, "range": 0, "time": 0.5, "danger": true}]
	var f: Dictionary = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(12, 1), 0.5, 1.0), "neutral Classic ray crosses walls and reaches edge")
	game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(engine_flame(game, Vector2i(12, 1)), "engine confirms neutral geometry")


func test_route_wait_and_margin() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.players[0].pos = game.center(Vector2i(1, 1))
	game.flames = [{"tile": Vector2i(2, 1), "time": 0.4, "owner": 1, "distance": 0}]
	var o := observe(game)
	var f: Dictionary = nav.forecast(o)
	var r: Dictionary = nav.find_route(o, f, [Vector2i(2, 1)])
	check(r.found and r.arrival_times.back() >= 0.6, "wait until route across flame is safe")
	check(r.tiles.size() > 2 and r.tiles[0] == r.tiles[1], "wait represented by repeated tile")
	game.flames.clear()
	game.bombs = [test_bomb(Vector2i(2, 1), 0.15, 0)]
	o = observe(game)
	f = nav.forecast(o)
	r = nav.find_route(o, f, [Vector2i(2, 1)])
	check(r.found and r.arrival_times.back() > 0.65, "reject early arrival in a future active blast")
	f = nav.forecast(o, {"tile": Vector2i(1, 1), "owner": 0, "range": 1, "time": 2.5})
	check(is_equal_approx(f.horizon, 3.2), "placement proof includes 0.20 second margin")
	game.flames = [{"tile": Vector2i(1, 1), "time": 0.1, "owner": 1, "distance": 0}]
	o = observe(game)
	check(not nav.find_route(o, nav.forecast(o), [Vector2i(1, 2)]).found, "route cannot cross active flame at its start")


func test_pond_route_duration() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("pond")
	game.players[0].pos = game.center(Vector2i(1, 1))
	game.terrain[1][1] = 0
	game.terrain[1][2] = 1
	var o := observe(game)
	var r: Dictionary = nav.find_route(o, nav.forecast(o), [Vector2i(2, 1)])
	check(r.found and is_equal_approx(r.arrival_times.back(), 0.65), "Lily split dry/water duration rounds 26/94 + 26/75.2 up to .65")
	game.players[0].speed_bonus = 0.5
	o = observe(game)
	r = nav.find_route(o, nav.forecast(o), [Vector2i(2, 1)])
	check(r.found and is_equal_approx(r.arrival_times.back(), 0.45), "Lily speed upgrade changes both halves of the crossing")


func test_frost_committed_slide() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("frost")
	game.players[0].pos = game.center(Vector2i(1, 1)) + Vector2(26, 0)
	game.move_targets[0] = game.center(Vector2i(2, 1))
	game.terrain[1][2] = 2
	game.terrain[1][3] = 2
	var o := observe(game)
	var r: Dictionary = nav.find_route(o, nav.forecast(o), [Vector2i(3, 1)])
	check(r.found and r.tiles.slice(0, 3) == [Vector2i(2, 1), Vector2i(2, 1), Vector2i(3, 1)], "committed remainder precedes compulsory extra tile")
	check(r.found and is_equal_approx(r.arrival_times[1], 0.15) and is_equal_approx(r.arrival_times[2], 0.45), "committed half move and full slide round upward")
	game.flames = [{"tile": Vector2i(3, 1), "time": 0.5, "owner": 1, "distance": 0}]
	o = observe(game)
	check(not nav.find_route(o, nav.forecast(o), [Vector2i(1, 1)]).found, "cannot redirect or wait out unsafe compulsory slide")
	game.flames.clear()
	game.slide_active[0] = true
	o = observe(game)
	r = nav.find_route(o, nav.forecast(o), [Vector2i(2, 1)])
	check(r.found and r.tiles.size() == 2, "already sliding move does not recursively slide")


func test_own_bomb_egress() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.players[0].pos = game.center(Vector2i(1, 1))
	game.place_bomb(0)
	var o := observe(game)
	var f: Dictionary = nav.forecast(o)
	var r: Dictionary = nav.find_route(o, f, [Vector2i(3, 1)])
	check(r.found and r.tiles[1] == Vector2i(2, 1), "own bomb permits egress")
	game.players[0].pos = game.center(Vector2i(2, 1))
	game.update_safe_bomb(0)
	o = observe(game)
	r = nav.find_route(o, nav.forecast(o), [Vector2i(1, 1)])
	check(r.found and r.arrival_times.back() > 3.0, "left bomb blocks re-entry through complete flame lifetime")
	game.bombs.clear()
	game.players[0].pos = game.center(Vector2i(1, 1))
	o = observe(game)
	f = nav.forecast(o, {"tile": Vector2i(1, 1), "owner": 0, "range": 1, "time": 2.5})
	check(nav.find_route(o, f, [Vector2i(3, 1)]).found, "hypothetical own bomb also permits egress")


func test_unknown_and_budget() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.players[0].pos = game.center(Vector2i(1, 1))
	var o := observe(game)
	o.board[1][2] = -1
	var f: Dictionary = nav.forecast(o)
	check(not nav.find_route(o, f, [Vector2i(2, 1)]).found, "unknown cells never form route")
	var r: Dictionary = nav.find_route(o, f, [Vector2i(11, 9)], 3)
	check(not r.found and r.expanded_nodes <= 3, "search fails closed at requested expansion budget")
	o.bombs.append(test_bomb(Vector2i(3, 1), 8.0, 3))
	f = nav.forecast(o)
	check(not f.complete and f.horizon == 6.0, "long known fuse makes capped forecast incomplete")
	check(not nav.find_route(o, f, [Vector2i(1, 1)]).found, "incomplete forecast never proves escape")
	o.bombs[0].time = 1.0
	f = nav.forecast(o)
	check(not f.danger_intervals.has(Vector2i(1, 1)), "unknown tile blocks outgoing ordinary ray")


func test_moving_blocker_stops_immediately() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("frost")
	game.players[0].pos = game.center(Vector2i(1, 9))
	game.players[1].pos = game.center(Vector2i(11, 9))
	# A leading bomb moves first in the engine's array, but neither moves a tile
	# in the next frame. The follower must stop before the leader vacates its tile.
	game.bombs = [test_bomb(Vector2i(4, 1), 0.5, 0), test_bomb(Vector2i(3, 1), 0.5, 0)]
	for bomb in game.bombs:
		bomb.kick_direction = Vector2i.RIGHT
		bomb.kick_progress = 0.0
	var f: Dictionary = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(3, 1), 0.5, 1.0), "moving follower stops at initially occupied next tile")
	check(not f.danger_intervals.has(Vector2i(5, 1)), "follower cannot pass through leader's prior occupancy")
	check(not f.complete and not nav.find_route(observe(game), f, [Vector2i(1, 9)]).found, "multiple moving bombs cannot certify escape across engine slice orders")
	var batched = make_open_game("frost")
	batched.players[0].pos = batched.center(Vector2i(1, 9))
	batched.players[1].pos = batched.center(Vector2i(11, 9))
	batched.bombs = game.bombs.duplicate(true)
	batched.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(engine_flame(batched, Vector2i(5, 1)), "single large engine slice changes interacting follower destination")
	for i in range(10):
		game.step(0.05, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(engine_flame(game, Vector2i(3, 1)) and engine_flame(game, Vector2i(6, 1)), "engine confirms follower stop and leader movement")
	game = make_open_game("frost")
	game.bombs = [test_bomb(Vector2i(3, 1), 0.125, 0)]
	game.bombs[0].kick_direction = Vector2i.RIGHT
	game.bombs[0].kick_progress = 0.5
	f = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(4, 1), 0.125, 0.625), "observed partial kick progress moves before coincident fuse")


func test_hazard_then_fuse_order() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	game.board[1][4] = game.CRATE
	game.bombs = [test_bomb(Vector2i(3, 1), 0.5, 4)]
	game.hazards = [{"kind": "random_burst", "tiles": [Vector2i(4, 1)], "time": 0.5}]
	var f: Dictionary = nav.forecast(observe(game))
	check(has_interval(f.danger_intervals, Vector2i(5, 1), 0.5, 1.0), "hazard removes crate before coincident natural fuse batch")
	game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(engine_flame(game, Vector2i(5, 1)), "engine confirms hazard-before-fuse crate order")
	game = make_open_game()
	game.board[1][4] = game.CRATE
	game.bombs = [test_bomb(Vector2i(3, 1), 2.5, 4), test_bomb(Vector2i(2, 1), 0.5, 5)]
	game.hazards = [{"kind": "blizzard", "tiles": [Vector2i(3, 1)], "time": 0.5}]
	f = nav.forecast(observe(game))
	check(not f.danger_intervals.has(Vector2i(5, 1)), "hazard-triggered chain shares crate snapshot within its batch")
	game.step(0.5, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(not engine_flame(game, Vector2i(5, 1)), "engine confirms hazard chain batch crate shielding")


func test_collision_radius_and_kick_rejection() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game()
	# The centre has crossed into x=2, but the trailing collision edge is still
	# on x=1 when a closure hits. Checking only centre tiles would permit escape.
	game.players[0].pos = game.center(Vector2i(1, 1)) + Vector2(28, 0)
	game.move_targets[0] = game.center(Vector2i(2, 1))
	game.hazards = [{"kind": "closing_walls", "tiles": [Vector2i(1, 1)], "time": 0.01}]
	var o := observe(game)
	check(not nav.find_route(o, nav.forecast(o), [Vector2i(3, 1)]).found, "trailing radius closure blocks committed escape proof")
	game.step(0.01, [Vector2.RIGHT, Vector2.ZERO], [false, false])
	check(not game.players[0].alive, "engine confirms trailing-radius closure elimination")
	game = make_open_game("frost")
	game.players[0].pos = game.center(Vector2i(1, 1))
	game.players[0].can_kick = true
	game.board[2][1] = game.WALL
	game.bombs = [test_bomb(Vector2i(2, 1), 2.5, 3)]
	o = observe(game)
	check(not nav.find_route(o, nav.forecast(o), [Vector2i(4, 1)]).found, "kick ability does not authorize planned kick through trapped corridor")


func test_candidate_committed_rejected() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("frost")
	game.players[0].pos = game.center(Vector2i(1, 1)) + Vector2(10, 0)
	game.move_targets[0] = game.center(Vector2i(2, 1))
	var o := observe(game)
	var f: Dictionary = nav.forecast(o, {"tile": Vector2i(1, 1), "owner": 0, "range": 1, "time": 2.5})
	check(not nav.find_route(o, f, [Vector2i(3, 1)]).found, "candidate placement during committed motion never yields a proof")


func test_slide_blocker_arrival_uncertainty() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("frost", 4)
	game.players[0].pos = game.center(Vector2i(1, 1))
	game.terrain[1][2] = 2
	game.terrain[1][3] = 0
	game.board[2][3] = game.OPEN
	game.bombs = [test_bomb(Vector2i(3, 2), 0.7, 0)]
	game.bombs[0].kick_direction = Vector2i.UP
	game.bombs[0].kick_progress = 0.04
	game.move_targets[0] = game.center(Vector2i(2, 1))
	var o := observe(game)
	var f: Dictionary = nav.forecast(o)
	check(not nav.find_route(o, f, [Vector2i(2, 1)]).found, "arrival rounding cannot suppress a slide started before a moving blocker arrives")
	game.step(0.235, [Vector2.RIGHT, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [false, false, false, false])
	check(game.slide_active[0], "engine starts mandatory slide before .24 bomb crossing")
	for i in range(48):
		game.step(0.01, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [false, false, false, false])
	check(not game.players[0].alive, "engine confirms suppressed-slide proof would die on bomb tile")


func test_escape_route_engine_survival() -> void:
	var nav = navigation()
	if nav == null:
		return
	for mode in ["fixed", "pond", "frost"]:
		var game = make_open_game(mode)
		game.players[0].pos = game.center(Vector2i(1, 1))
		game.players[1].pos = game.center(Vector2i(11, 9))
		game.terrain[1][1] = 0
		game.terrain[1][2] = 1 if mode == "pond" else (2 if mode == "frost" else 0)
		game.terrain[1][3] = 0
		var o := observe(game)
		var f: Dictionary = nav.forecast(o, {"tile": Vector2i(1, 1), "owner": 0, "range": 1, "time": 2.5})
		var r: Dictionary = nav.find_route(o, f, [Vector2i(3, 1)])
		check(r.found, "engine playback escape proof exists " + mode)
		if not r.found:
			continue
		game.place_bomb(0)
		for i in range(1, r.tiles.size()):
			var target: Vector2 = game.center(r.tiles[i])
			while game.round_elapsed < r.arrival_times[i] - 0.00001:
				var direction := Vector2.ZERO
				if game.players[0].pos.distance_to(target) > 0.01:
					direction = (target - game.players[0].pos).normalized()
				game.step(minf(0.01, r.arrival_times[i] - game.round_elapsed), [direction, Vector2.ZERO], [false, false])
		while game.round_elapsed < f.horizon - 0.00001:
			game.step(minf(0.01, f.horizon - game.round_elapsed), [Vector2.ZERO, Vector2.ZERO], [false, false])
		check(game.players[0].alive and game.tile_at(game.players[0].pos) == Vector2i(3, 1), "route playback survives actual bomb and complete flame lifetime " + mode)
