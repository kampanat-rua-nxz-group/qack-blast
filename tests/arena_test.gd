extends SceneTree

var failures := 0


func _initialize() -> void:
	test_game_runs_without_scene()
	var scene := load("res://scenes/arena.tscn")
	check(scene != null, "arena scene loads")
	if scene == null:
		quit(1)
		return
	var arena = scene.instantiate()
	check(arena.has_method("new_round"), "arena script parses and loads")
	if not arena.has_method("new_round"):
		quit(1)
		return
	root.add_child(arena)
	arena.new_round()
	var game = arena.game
	test_spawn_routes(game)
	test_bomb_exit(game)
	test_one_press_moves_one_tile(arena)
	test_hold_repeats_at_tile_centers(arena)
	test_facing_tracks_actual_movement(game)
	test_initial_blast_range(game)
	test_simultaneous_blasts(game)
	test_simultaneous_deaths_are_draw(game)
	test_pickup_after_simultaneous_blasts(game)
	test_pickup_caps()
	test_win_and_kill_persist()
	test_chain_kill_belongs_to_triggered_bomb()
	test_closer_blast_gets_kill()
	test_equal_blast_distances_get_no_kill()
	test_self_kill_gets_no_credit()
	test_one_bomb_draw_awards_one_kill()
	test_chain_can_award_reciprocal_kills()
	test_chain_with_self_blast_awards_one_kill()
	test_simultaneous_kills_get_no_wins()
	test_score_order_uses_wins_then_kills()
	print("Arena checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func test_game_runs_without_scene() -> void:
	if not ResourceLoader.exists("res://scripts/arena_game.gd"):
		check(false, "game rules load without an arena scene")
		return
	var game = load("res://scripts/arena_game.gd").new()
	game.rng.seed = 7
	game.new_round()
	check(game.players.size() == 2, "game creates two players without an arena scene")
	game.flames.append({"tile": Vector2i(1, 1), "owner": 1, "distance": 1, "time": game.FLAME_TIME})
	game.flames.append({"tile": Vector2i(11, 9), "owner": 0, "distance": 1, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.round_over and game.result == "DRAW", "game resolves simultaneous deaths without an arena scene")


func test_spawn_routes(game) -> void:
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_round()
		var start := Vector2i(1, 1)
		var target := Vector2i(game.WIDTH - 2, game.HEIGHT - 2)
		var visited := {}
		visited[start] = true
		var queue := [start]
		while not queue.is_empty():
			var tile: Vector2i = queue.pop_front()
			for direction in game.DIRECTIONS:
				var next_tile: Vector2i = tile + direction
				if game.inside(next_tile) and game.board[next_tile.y][next_tile.x] == game.OPEN and not visited.has(next_tile):
					visited[next_tile] = true
					queue.append(next_tile)
		check(visited.has(target), "seed %d connects the spawns" % seed_value)


func test_bomb_exit(game) -> void:
	game.new_round()
	game.place_bomb(0)
	var spawn := Vector2i(1, 1)
	var crossed: Vector2 = game.center(spawn) + Vector2(game.CELL * 0.51, 0.0)
	game.players[0].pos = crossed
	game.update_safe_bomb(0)
	check(game.players[0].safe_bomb == spawn, "placer stays exempt while body overlaps bomb tile")
	check(game.can_stand(crossed + Vector2(3, 0), 0), "placer can keep moving away from bomb")
	game.players[0].pos = game.center(spawn) + Vector2(game.CELL * 0.9, 0.0)
	game.update_safe_bomb(0)
	check(game.players[0].safe_bomb != spawn, "bomb blocks re-entry after player fully exits")
	check(not game.can_stand(crossed, 0), "placer cannot overlap bomb again after exiting")


func test_simultaneous_blasts(game) -> void:
	game.new_round()
	clear_crates(game)
	game.board[3][5] = game.CRATE
	game.bombs = [
		{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0},
		{"tile": Vector2i(7, 3), "owner": 1, "range": 4, "time": 0.0},
	]
	game.update_bombs(0.016)
	check(not has_flame(game, Vector2i(4, 3), 1), "second blast stops at crate destroyed in same tick")


func test_simultaneous_deaths_are_draw(game) -> void:
	game.new_round()
	for i in range(game.players.size()):
		game.flames.append({"tile": game.tile_at(game.players[i].pos), "owner": 1 - i, "distance": 1, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(not game.players[0].alive and not game.players[1].alive, "both players die in the same frame")
	check(game.round_over and game.result == "DRAW", "simultaneous deaths end in a draw")


func test_win_and_kill_persist() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	var scores = game.get("scores")
	check(scores != null, "game keeps a score for each player")
	if scores == null:
		return
	game.flames.append({"tile": Vector2i(11, 9), "owner": 0, "distance": 1, "time": game.FLAME_TIME})
	game.flames.append({"tile": Vector2i(11, 9), "owner": 0, "distance": 2, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(scores[0].wins == 1 and scores[0].kills == 1, "survivor gets one Win and one Kill per victim")
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(scores[0].wins == 1 and scores[0].kills == 1, "finished round cannot award scores twice")
	game.new_round()
	check(scores[0].wins == 1 and scores[0].kills == 1, "score survives a rematch")
	game.flames.append({"tile": Vector2i(11, 9), "owner": 0, "distance": 1, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(scores[0].wins == 2 and scores[0].kills == 2, "Wins and Kills accumulate across rounds")


func test_chain_kill_belongs_to_triggered_bomb() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(7, 3))
	game.bombs = [
		{"tile": Vector2i(3, 3), "owner": 0, "range": 2, "time": 0.0},
		{"tile": Vector2i(5, 3), "owner": 1, "range": 3, "time": game.FUSE},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.scores[1].kills == 1 and game.scores[0].kills == 0, "triggered bomb owner gets the chain Kill")


func test_closer_blast_gets_kill() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(5, 3))
	game.bombs = [
		{"tile": Vector2i(2, 3), "owner": 0, "range": 3, "time": 0.0},
		{"tile": Vector2i(7, 3), "owner": 1, "range": 2, "time": 0.0},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.scores[1].kills == 1 and game.scores[0].kills == 0, "closer blast gets Kill regardless of flame order")


func test_equal_blast_distances_get_no_kill() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(5, 3))
	game.bombs = [
		{"tile": Vector2i(7, 3), "owner": 1, "range": 2, "time": 0.0},
		{"tile": Vector2i(3, 3), "owner": 0, "range": 2, "time": 0.0},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.scores[0].kills == 0 and game.scores[1].kills == 0, "equal-distance blasts give no Kill")


func test_self_kill_gets_no_credit() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	game.flames.append({"tile": Vector2i(1, 1), "owner": 0, "distance": 0, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.scores[0].kills == 0 and game.scores[1].wins == 1, "self-elimination gives no Kill but survivor gets Win")


func test_one_bomb_draw_awards_one_kill() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(3, 3))
	game.players[1].pos = game.center(Vector2i(4, 3))
	game.bombs = [{"tile": Vector2i(3, 3), "owner": 0, "range": 1, "time": 0.0}]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.result == "DRAW", "one bomb can eliminate both players")
	check(game.scores[0].kills == 1 and game.scores[1].kills == 0, "bomb owner gets one Kill for opponent but none for self")


func test_chain_can_award_reciprocal_kills() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(7, 3))
	game.players[1].pos = game.center(Vector2i(3, 5))
	game.bombs = [
		{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0},
		{"tile": Vector2i(5, 3), "owner": 1, "range": 4, "time": game.FUSE},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.result == "DRAW", "triggered chain eliminates both players")
	check(game.scores[0].kills == 1 and game.scores[1].kills == 1, "each bomb owner gets a Kill when its blast is closest to the opponent")


func test_chain_with_self_blast_awards_one_kill() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(7, 3))
	game.players[1].pos = game.center(Vector2i(5, 3))
	game.bombs = [
		{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0},
		{"tile": Vector2i(5, 3), "owner": 1, "range": 4, "time": game.FUSE},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.result == "DRAW", "chain with overlapping self-blast eliminates both players")
	check(game.scores[0].kills == 0 and game.scores[1].kills == 1, "self-blast at the bomb tile prevents opponent Kill credit")


func test_simultaneous_kills_get_no_wins() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	game.flames = [
		{"tile": Vector2i(1, 1), "owner": 1, "distance": 1, "time": game.FLAME_TIME},
		{"tile": Vector2i(11, 9), "owner": 0, "distance": 1, "time": game.FLAME_TIME},
	]
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.result == "DRAW" and game.scores[0].wins == 0 and game.scores[1].wins == 0, "simultaneous deaths award no Wins")
	check(game.scores[0].kills == 1 and game.scores[1].kills == 1, "both bomb owners can get Kills in a drawn round")


func test_score_order_uses_wins_then_kills() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	check(game.has_method("score_order"), "game provides score ranking")
	if not game.has_method("score_order"):
		return
	game.scores[0] = {"wins": 1, "kills": 0}
	game.scores[1] = {"wins": 0, "kills": 9}
	check(game.score_order() == [0, 1], "Wins rank before Kills")
	game.scores[1].wins = 1
	check(game.score_order() == [1, 0], "Kills break equal Wins")
	game.scores[0].kills = 9
	check(game.score_order() == [0, 1], "equal scores keep player order")


func test_one_press_moves_one_tile(arena) -> void:
	var game = arena.game
	arena.new_round()
	clear_crates(game)
	var start: Vector2 = game.center(Vector2i(3, 3))
	game.players[0].pos = start
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	arena._input(key)
	var early_turn := InputEventKey.new()
	early_turn.keycode = KEY_W
	early_turn.pressed = true
	arena._input(early_turn)
	early_turn.pressed = false
	arena._input(early_turn)
	key.pressed = false
	arena._input(key)
	arena._physics_process(0.016)
	check(game.players[0].pos.x > start.x and game.players[0].pos.y == start.y, "movement stays on the tile centerline")
	for frame in range(40):
		arena._physics_process(0.016)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "one press finishes at the next tile center")
	for frame in range(40):
		arena._physics_process(0.016)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "one press never starts a second tile")
	key.pressed = false
	arena._input(key)
	key.pressed = true
	arena._input(key)
	key.pressed = false
	arena._input(key)
	for frame in range(40):
		arena._physics_process(0.016)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, 0), "another press moves exactly one more tile")
	game.board[3][6] = game.CRATE
	key.pressed = true
	arena._input(key)
	for frame in range(40):
		arena._physics_process(0.016)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, 0), "blocked press leaves player at tile center")


func test_hold_repeats_at_tile_centers(arena) -> void:
	var game = arena.game
	arena.new_round()
	clear_crates(game)
	var start: Vector2 = game.center(Vector2i(3, 3))
	game.players[0].pos = start
	var right := InputEventKey.new()
	right.keycode = KEY_D
	right.pressed = true
	arena._input(right)
	for frame in range(20):
		arena._physics_process(0.016)
	check(game.players[0].pos.x > start.x + game.CELL, "holding starts another tile after reaching center")
	var up := InputEventKey.new()
	up.keycode = KEY_W
	up.pressed = true
	arena._input(up)
	right.pressed = false
	arena._input(right)
	for frame in range(10):
		arena._physics_process(0.016)
	check(game.players[0].pos.y == start.y, "new direction does not turn before tile center")
	for frame in range(10):
		arena._physics_process(0.016)
	check(game.players[0].pos.x == start.x + game.CELL * 2 and game.players[0].pos.y < start.y, "held direction turns at next tile center")
	up.pressed = false
	arena._input(up)
	for frame in range(40):
		arena._physics_process(0.016)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, -game.CELL), "release after turning stops at center")


func test_facing_tracks_actual_movement(game) -> void:
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(3, 3))
	game.start_move(0, Vector2.RIGHT)
	check(is_equal_approx(game.players[0].get("facing", 0.0), -PI / 2.0), "duck faces right when moving right")
	game.move_targets[0] = Vector2.ZERO
	game.board[2][3] = game.CRATE
	game.start_move(0, Vector2.UP)
	check(is_equal_approx(game.players[0].get("facing", 0.0), -PI / 2.0), "blocked movement does not turn the duck")


func test_initial_blast_range(game) -> void:
	game.new_round()
	clear_crates(game)
	game.players[0].pos = game.center(Vector2i(3, 3))
	game.place_bomb(0)
	game.update_bombs(game.FUSE)
	check(has_flame(game, Vector2i(4, 3), 0), "initial blast reaches the adjacent tile")
	check(not has_flame(game, Vector2i(5, 3), 0), "initial blast stops before the second tile")


func test_pickup_after_simultaneous_blasts(game) -> void:
	var crate := Vector2i(5, 3)
	for seed_value in range(50):
		var drops := []
		for bomb_count in [1, 2]:
			game.new_round()
			clear_crates(game)
			game.board[crate.y][crate.x] = game.CRATE
			game.rng.seed = seed_value
			game.bombs = [{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0}]
			if bomb_count == 2:
				game.bombs.append({"tile": Vector2i(7, 3), "owner": 1, "range": 4, "time": 0.0})
			game.update_bombs(0.016)
			drops.append(game.pickups.has(crate))
		if drops[0] != drops[1]:
			check(false, "crate pickup survives a second blast in the same tick (seed %d)" % seed_value)
			return


func test_pickup_caps() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	var spawn := Vector2i(1, 1)
	var idle := [Vector2.ZERO, Vector2.ZERO]
	var no_bombs := [false, false]
	game.players[0].bomb_limit = 4
	game.pickups[spawn] = game.PICKUP_BOMB_CAPACITY
	game.step(0.016, idle, no_bombs)
	check(game.players[0].bomb_limit == 5 and not game.pickups.has(spawn), "bomb pickup reaches cap and is consumed")
	game.pickups[spawn] = game.PICKUP_BOMB_CAPACITY
	game.step(0.016, idle, no_bombs)
	check(game.players[0].bomb_limit == 5 and not game.pickups.has(spawn), "extra bomb pickup cannot exceed cap")
	game.players[0].range = 5
	game.pickups[spawn] = game.PICKUP_BLAST_RANGE
	game.step(0.016, idle, no_bombs)
	check(game.players[0].range == 6 and not game.pickups.has(spawn), "range pickup reaches cap and is consumed")
	game.pickups[spawn] = game.PICKUP_BLAST_RANGE
	game.step(0.016, idle, no_bombs)
	check(game.players[0].range == 6 and not game.pickups.has(spawn), "extra range pickup cannot exceed cap")


func clear_crates(game) -> void:
	for y in range(1, game.HEIGHT - 1):
		for x in range(1, game.WIDTH - 1):
			if game.board[y][x] != game.WALL:
				game.board[y][x] = game.OPEN


func has_flame(game, tile: Vector2i, owner: int) -> bool:
	for flame in game.flames:
		if flame.tile == tile and flame.owner == owner:
			return true
	return false
