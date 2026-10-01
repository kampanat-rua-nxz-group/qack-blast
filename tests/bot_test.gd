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
	test_pond_committed_water_exit_deadline()
	test_frost_committed_slide()
	test_own_bomb_egress()
	test_unknown_and_budget()
	test_moving_blocker_stops_immediately()
	test_hazard_then_fuse_order()
	test_collision_radius_and_kick_rejection()
	test_candidate_committed_rejected()
	test_slide_blocker_arrival_uncertainty()
	test_escape_route_engine_survival()
	test_seeded_reactions()
	test_no_catchup_actions()
	test_safe_placement()
	test_difficulty_tactics()
	test_controller_fairness()
	test_controller_reset()
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
	check(r.found and is_equal_approx(r.arrival_times.back(), 0.70), "Lily mixed terrain bounds whole crossing at water speed: 52/75.2 rounds up to .70")
	game.players[0].speed_bonus = 0.5
	o = observe(game)
	r = nav.find_route(o, nav.forecast(o), [Vector2i(2, 1)])
	check(r.found and is_equal_approx(r.arrival_times.back(), 0.50), "Lily speed upgrade changes safe mixed-terrain bound: 52/112.8 rounds up to .50")


func test_pond_committed_water_exit_deadline() -> void:
	var nav = navigation()
	if nav == null:
		return
	var game = make_open_game("pond")
	for y in range(1, game.HEIGHT - 1):
		for x in range(1, game.WIDTH - 1):
			game.board[y][x] = game.OPEN
			game.terrain[y][x] = 0
	game.terrain[1][1] = 1
	game.players[0].pos = game.center(Vector2i(2, 1)) - Vector2(27.75, 0)
	game.players[1].pos = game.center(Vector2i(11, 9))
	game.move_targets[0] = game.center(Vector2i(2, 1))
	var o := observe(game)
	var r: Dictionary = nav.find_route(o, nav.forecast(o), [Vector2i(2, 2)])
	check(r.found and r.arrival_times == [0.0, 0.4, 1.0], "committed water exit bounds 27.75/75.2 before dry second leg")
	game.hazards = [{"kind": "closing_walls", "tiles": [Vector2i(2, 1)], "time": 0.91}]
	o = observe(game)
	check(not nav.find_route(o, nav.forecast(o), [Vector2i(2, 2)]).found, "water exit cannot prove escape before .91 known closure")
	# The old integrated bound advertised .30 then .90 arrivals. Engine slices
	# retain their starting terrain speed, so the first leg has not ended at .30.
	game.step(0.3, [Vector2.RIGHT, Vector2.ZERO], [false, false])
	check(game.players[0].pos.distance_to(game.center(Vector2i(2, 1))) > 5.0, "actual .30 slice leaves committed water exit unfinished")
	game.step(0.6, [Vector2.DOWN, Vector2.ZERO], [false, false])
	game.step(0.011, [Vector2.DOWN, Vector2.ZERO], [false, false])
	check(not game.players[0].alive, "actual advertised .30/.90 route dies to .91 closure")


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


func controller(difficulty: String = "medium", seed_value: int = 93):
	var script = load("res://scripts/bot_controller.gd")
	check(script != null and script.can_instantiate(), "scheduled controller exists")
	if script == null or not script.can_instantiate():
		return null
	var bot = script.new()
	check(bot.configure(0, difficulty, seed_value), "configure canonical controller")
	return bot


func test_seeded_reactions() -> void:
	for difficulty in ["easy", "medium", "hard", "extreme"]:
		var a = controller(difficulty)
		var b = controller(difficulty)
		if a == null or b == null:
			return
		var game = make_open_game()
		var o := observe(game)
		var p: Dictionary = load("res://scripts/bot_profiles.gd").get_profile(difficulty)
		for i in range(12):
			check(a.advance(0.0 if i == 0 else a.diagnostics().next_decision_in, o) == b.advance(0.0 if i == 0 else b.diagnostics().next_decision_in, o), "seeded reaction commands " + difficulty)
			var d: Dictionary = a.diagnostics()
			check(d.decision_count == i + 1, "one scheduled decision " + difficulty)
			check(d.next_decision_in >= p.interval_min and d.next_decision_in <= p.interval_max, "exact sampled interval " + difficulty)
			check(d == b.diagnostics(), "seeded reaction diagnostics " + difficulty)
		var held: Dictionary = a.advance(0.0, o)
		o.hazards = [{"kind": "closing_walls", "tiles": [o.self.tile], "time": 0.01}]
		var changed: Dictionary = a.advance(0.01, o)
		check(changed.direction == held.direction and not changed.plant and changed.move_press == Vector2.ZERO, "danger cannot bypass deadline or repeat pulses")


func test_no_catchup_actions() -> void:
	var bot = controller()
	if bot == null:
		return
	var o := observe(make_open_game())
	bot.advance(0.0, o)
	var before: int = bot.diagnostics().decision_count
	bot.advance(5.0, o)
	check(bot.diagnostics().decision_count == before + 1 and bot.diagnostics().next_decision_in > 0.0, "five second delta has no catchup actions")


func test_safe_placement() -> void:
	var trapped = make_open_game()
	trapped.players[0].pos = trapped.center(Vector2i(1, 1))
	trapped.board[1][2] = trapped.CRATE
	trapped.board[2][1] = trapped.WALL
	var bot = controller("extreme")
	if bot == null:
		return
	check(not bot.advance(0.0, observe(trapped)).plant, "dead end placement refused")
	for mode in ["fixed", "pond", "frost"]:
		for difficulty in ["easy", "medium", "hard", "extreme"]:
			var game = make_open_game(mode)
			game.players[0].pos = game.center(Vector2i(1, 1))
			game.players[1].pos = game.center(Vector2i(11, 9))
			game.board[2][1] = game.CRATE
			game.terrain[1][1] = 0
			game.terrain[1][2] = 1 if mode == "pond" else (2 if mode == "frost" else 0)
			game.terrain[1][3] = 0
			bot = controller(difficulty)
			var command: Dictionary = bot.advance(0.0, observe(game))
			if mode == "pond" and difficulty == "easy":
				check(not command.plant, "slow Lily reaction cannot prove this escape")
				continue
			check(command.plant, "proven scheduled placement " + mode + difficulty)
			var planted := 0
			for tick in range(350):
				if tick > 0:
					command = bot.advance(0.01, observe(game))
				if command.plant:
					planted += 1
				game.step(0.01, [command.direction, Vector2.ZERO], [command.plant, false], [command.move_press, Vector2.ZERO])
			check(game.players[0].alive and planted >= 1, "actual controller commands escape through full flames " + mode + difficulty)
	# Speed upgrades on dry Lily ground can make the same slow profile safe.
	var upgraded = make_open_game("pond")
	upgraded.players[0].pos = upgraded.center(Vector2i(3, 3))
	upgraded.players[0].speed_bonus = 0.5
	upgraded.board[4][3] = upgraded.CRATE
	for y in range(1, upgraded.HEIGHT - 1):
		for x in range(1, upgraded.WIDTH - 1):
			upgraded.terrain[y][x] = 0
	bot = controller("easy", 93)
	var lily_command: Dictionary = bot.advance(0.0, observe(upgraded))
	check(lily_command.plant, "Easy can prove upgraded dry Lily escape using sampled deadline")
	for tick in range(350):
		if tick > 0:
			lily_command = bot.advance(0.01, observe(upgraded))
		upgraded.step(0.01, [lily_command.direction, Vector2.ZERO], [lily_command.plant, false], [lily_command.move_press, Vector2.ZERO])
	check(upgraded.players[0].alive, "Easy actual upgraded Lily commands survive")
	# Capacity and a changing complete forecast never authorize a second bomb.
	var full = make_open_game()
	full.board[2][1] = full.CRATE
	full.place_bomb(0)
	bot = controller("extreme")
	check(not bot.advance(0.0, observe(full)).plant, "known own bombs conservatively exhaust capacity")
	var moving = make_open_game("frost")
	moving.board[2][1] = moving.CRATE
	moving.move_targets[0] = moving.center(Vector2i(2, 1))
	moving.slide_active[0] = true
	bot = controller("extreme")
	check(not bot.advance(0.0, observe(moving)).plant, "no placement during move or slide")


func test_difficulty_tactics() -> void:
	var game = make_open_game()
	game.players[0].pos = game.center(Vector2i(3, 3))
	game.players[1].pos = game.center(Vector2i(4, 2))
	game.players[0].range = 3
	game.board[4][3] = game.CRATE
	# Current tile clears a crate but leaves every opponent exit open. The
	# adjacent right candidate reaches the opponent and pressures its exits.
	game.board[2][4] = game.OPEN
	game.board[2][3] = game.WALL
	game.board[2][5] = game.WALL
	for difficulty in ["easy", "medium", "hard", "extreme"]:
		var bot = controller(difficulty)
		if bot == null:
			return
		var command: Dictionary = bot.advance(0.0, observe(game))
		var limit: int = load("res://scripts/bot_profiles.gd").get_profile(difficulty).candidate_limit
		check(bot.diagnostics().candidate_count <= limit, "bounded candidates " + difficulty)
		if difficulty == "easy":
			check(bot.diagnostics().candidate_count == 1, "Easy evaluates one nearby position")
		if difficulty in ["hard", "extreme"]:
			check(not command.plant and command.move_press == Vector2.RIGHT, "exit pressure preferred over crate " + difficulty)

	var pressure_bot = controller("hard")
	var pressure_observation := observe(game)
	var positions: Array = [[Vector2i(4, 2)]]
	var without: float = pressure_bot.placement_score(pressure_observation, Vector2i(4, 3), positions)
	pressure_observation.bombs = [{"tile": Vector2i(4, 1), "owner": 1, "range": 0, "time": 2.0}]
	var combined: float = pressure_bot.placement_score(pressure_observation, Vector2i(4, 3), positions)
	check(combined > without, "existing visible bomb reduces exits for coordinated new placement")


func test_controller_fairness() -> void:
	var a = observation_game("night")
	var b = observation_game("night")
	b.players[1].pos += Vector2(2, 3)
	b.rng.seed = 9001
	b.pickups[Vector2i(10, 9)] = 1
	b.board[8][10] = b.WALL
	b.move_targets[1] = b.center(Vector2i(9, 9))
	var ma := {}
	var mb := {}
	var ca = controller("extreme")
	var cb = controller("extreme")
	if ca == null or cb == null:
		return
	var before: Dictionary = {"board": a.board.duplicate(true), "players": a.players.duplicate(true), "bombs": a.bombs.duplicate(true)}
	var rng_before: int = a.rng.state
	for tick in range(30):
		check(ca.advance(0.05, observation(a, ma)) == cb.advance(0.05, observation(b, mb)), "hidden state equal controller sequence")
	check({"board": a.board, "players": a.players, "bombs": a.bombs} == before and a.rng.state == rng_before, "controller never mutates game or game RNG")


func test_controller_reset() -> void:
	var bot = controller("hard")
	if bot == null:
		return
	var o := observe(make_open_game())
	bot.advance(0.0, o)
	for invalid in [{}, {"self": {"alive": false}}, {"round_over": true}]:
		check(bot.advance(1.0, invalid) == {"direction": Vector2.ZERO, "move_press": Vector2.ZERO, "plant": false}, "invalid dead or round-over neutral")
	bot.reset()
	var fresh = controller("hard")
	check(bot.diagnostics().decision_count == 0 and bot.advance(0.0, o) == fresh.advance(0.0, o) and bot.diagnostics() == fresh.diagnostics(), "reset drops old intent history and clock")
	check(not bot.configure(0, "extream", 1), "controller rejects invalid profile")
	# Prediction branches at legal intersections and forgets a vanished duck.
	bot = controller("extreme")
	o.players = [{"slot": 1, "pos": o.geometry.origin + Vector2(3.5, 3.5) * o.geometry.cell}]
	bot.opponent_tiles(o)
	o.round_elapsed += 0.25
	o.players[0].pos += Vector2.RIGHT * 47.0
	var predictions: Array = bot.opponent_tiles(o)
	check(predictions[0].size() > 2, "visible displacement branches through Extreme horizon")
	o.players.clear()
	check(bot.opponent_tiles(o).is_empty(), "invisible opponent forgotten")
	o.players = [{"slot": 1, "pos": o.geometry.origin + Vector2(3.5, 3.5) * o.geometry.cell}]
	check(bot.opponent_tiles(o)[0].size() == 1, "reappearing duck has no stale velocity")
