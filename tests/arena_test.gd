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
	test_night_vision_pickup()
	test_night_visibility(arena)
	test_night_spotlight(arena)
	test_night_drops_vision()
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
	test_three_and_four_player_rounds()
	test_large_round_spawns()
	test_scene_accepts_four_player_state(arena)
	test_wall_modes()
	test_night_wall_layout()
	test_map_themes(arena)
	test_wall_selection_applies_next_round(arena)
	test_danger_bomb_waves()
	test_danger_bomb_crosses_walls()
	test_danger_bomb_waits_through_chain()
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


func test_three_and_four_player_rounds() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	check(game.get("player_count") != null, "game supports selecting a player count")
	if game.get("player_count") == null:
		return
	game.player_count = 3
	game.new_round()
	check(game.players.size() == 3 and game.move_targets.size() == 3, "three players have movement state")
	game.player_count = 4
	game.new_round()
	check(game.players.size() == 4 and game.scores.size() == 4, "four players have persistent score entries")
	if game.players.size() != 4 or game.scores.size() != 4:
		return
	var spawns := [Vector2i(1, 1), Vector2i(13, 11), Vector2i(13, 1), Vector2i(1, 11)]
	for i in range(4):
		check(game.tile_at(game.players[i].pos) == spawns[i], "player %d has a distinct corner spawn" % (i + 1))
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [false, false, false, false])
	check(not game.round_over, "four-player round stays active with four survivors")
	game.flames.append({"tile": game.tile_at(game.players[0].pos), "owner": 3, "distance": 1, "time": game.FLAME_TIME})
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [false, false, false, false])
	check(game.scores[3].kills == 1 and not game.round_over, "fourth player's blast can score during a four-player round")
	for i in range(3):
		game.players[i].alive = false
	game.resolve_round()
	check(game.result == "PLAYER 4 WINS" and game.scores[3].wins == 1, "last of four players gets one Win")
	game.new_round()
	check(game.scores[3].wins == 1, "four-player Win survives a rematch")
	game.player_count = 2
	game.new_round()
	check(game.score_order().size() == 2, "rankings show active players when player count changes")


func test_large_round_spawns() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	for count in [4, 5, 6]:
		game.player_count = count
		for mode in game.MAP_MODES:
			game.wall_mode = mode
			for seed_value in range(5):
				game.rng.seed = seed_value
				game.new_round()
				check(game.board.size() == 13 and game.board[0].size() == 15, "%s %d-player board grows to 15x13" % [mode, count])
				if mode == "pond":
					check(game.board[4][5] == game.WALL, "pond pillars stay centered on large board")
				elif mode == "frost":
					check(game.board[3][4] == game.WALL, "frost pillars stay centered on large board")
				check(game.players.size() == count, "%s creates %d players" % [mode, count])
				var positions := {}
				var reachable := reachable_open_tiles(game, Vector2i(1, 1))
				for player in game.players:
					var tile: Vector2i = game.tile_at(player.pos)
					positions[tile] = true
					check(reachable.has(tile), "%s %d-player seed %d connects spawn %s" % [mode, count, seed_value, tile])
				check(positions.size() == count, "%s %d-player spawns are distinct" % [mode, count])
	game.player_count = 2
	game.new_round()
	check(game.board.size() == 11 and game.board[0].size() == 13, "two-player rematch keeps original board")


func test_scene_accepts_four_player_state(arena) -> void:
	arena.game.player_count = 4
	arena.new_round()
	arena._physics_process(0.016)
	check(arena.held_directions.size() == 4 and arena.visual_facing.size() == 4, "scene state sizes match four players")
	arena.game.player_count = 2
	arena.new_round()


func test_wall_modes() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	check(game.get("wall_mode") != null, "game offers a permanent wall mode")
	if game.get("wall_mode") == null:
		return
	game.player_count = 4
	var fixed_mask := ""
	var random_masks := {}
	var fixed_maps := {}
	var crate_masks := {"fixed": {}, "random": {}, "pond": {}, "frost": {}}
	for mode in ["fixed", "random", "pond", "frost"]:
		game.wall_mode = mode
		for seed_value in range(40):
			game.rng.seed = seed_value
			game.new_round()
			var mask := wall_mask(game)
			crate_masks[mode][crate_mask(game)] = true
			if mode != "random":
				if seed_value == 0:
					fixed_mask = mask
				check(mask == fixed_mask, "%s walls stay the same across seeds" % mode)
			else:
				random_masks[mask] = true
			var reachable := reachable_open_tiles(game, game.tile_at(game.players[0].pos))
			for player in game.players:
				var spawn: Vector2i = game.tile_at(player.pos)
				check(reachable.has(spawn), "%s seed %d connects all four spawns" % [mode, seed_value])
				var exits := 0
				for direction in game.DIRECTIONS:
					var next_tile: Vector2i = spawn + direction
					if game.inside(next_tile) and game.board[next_tile.y][next_tile.x] == game.OPEN:
						exits += 1
				check(exits >= 2, "%s seed %d gives every spawn two exits" % [mode, seed_value])
		if mode != "random":
			fixed_maps[mode] = fixed_mask
	check(random_masks.size() > 1, "random permanent walls vary by seed")
	check(fixed_maps["fixed"] != fixed_maps["pond"] and fixed_maps["fixed"] != fixed_maps["frost"] and fixed_maps["pond"] != fixed_maps["frost"], "named maps have distinct permanent walls")
	for mode in crate_masks:
		check(crate_masks[mode].size() > 1, "%s crates reroll" % mode)


func test_wall_selection_applies_next_round(arena) -> void:
	arena.new_round()
	var current_mode: String = arena.game.wall_mode
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	arena._input(key)
	check(arena.game.wall_mode == current_mode, "map choice does not alter the active round")
	arena.new_round()
	check(arena.game.wall_mode != current_mode, "map choice applies on the next round")
	arena._input(key)
	arena.new_round()
	check(arena.game.wall_mode == "pond", "local map selection reaches pond")
	arena._input(key)
	arena.new_round()
	check(arena.game.wall_mode == "frost", "local map selection reaches frost")
	arena._input(key)
	arena.new_round()
	check(arena.game.wall_mode == "night", "local map selection reaches night")
	arena._input(key)
	arena.new_round()
	check(arena.game.wall_mode == "fixed", "local map selection wraps to classic")


func test_night_wall_layout() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.wall_mode = "night"
	game.player_count = 4
	var layouts := {}
	for seed_value in range(20):
		game.rng.seed = seed_value
		game.new_round()
		layouts[wall_mask(game)] = true
		var reachable := reachable_open_tiles(game, Vector2i(1, 1))
		for player in game.players:
			check(reachable.has(game.tile_at(player.pos)), "night seed %d connects every spawn" % seed_value)
	check(layouts.size() > 1, "night obstacles reroll each round")


func test_map_themes(arena) -> void:
	if not arena.has_method("map_colors"):
		check(false, "arena exposes map colors")
		return
	var classic: Dictionary = arena.map_colors("fixed")
	var pond: Dictionary = arena.map_colors("pond")
	var frost: Dictionary = arena.map_colors("frost")
	for part in ["floor", "wall", "crate"]:
		check(pond[part] != classic[part] and frost[part] != classic[part] and pond[part] != frost[part], "%s has distinct colors on each named map" % part)


func wall_mask(game) -> String:
	var mask := ""
	for row in game.board:
		for cell in row:
			mask += "#" if cell == game.WALL else "."
	return mask


func crate_mask(game) -> String:
	var mask := ""
	for row in game.board:
		for cell in row:
			mask += "X" if cell == game.CRATE else "."
	return mask


func reachable_open_tiles(game, start: Vector2i) -> Dictionary:
	var visited := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		for direction in game.DIRECTIONS:
			var next_tile: Vector2i = tile + direction
			if game.inside(next_tile) and game.board[next_tile.y][next_tile.x] == game.OPEN and not visited.has(next_tile):
				visited[next_tile] = true
				queue.append(next_tile)
	return visited


func test_danger_bomb_waves() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.rng.seed = 7
	game.new_round()
	clear_crates(game)
	var idle := [Vector2.ZERO, Vector2.ZERO]
	var no_bombs := [false, false]
	game.step(294.9, idle, no_bombs)
	check(game.bombs.is_empty() and game.warning_tiles().is_empty(), "danger bombs do not appear before the warning")
	game.step(0.1, idle, no_bombs)
	check(game.bombs.size() == 1 and game.bombs[0].get("danger", false), "one danger bomb appears at 4:55")
	if game.bombs.is_empty():
		return
	var bomb_tile: Vector2i = game.bombs[0].tile
	check(game.warning_tiles().has(Vector2i(0, bomb_tile.y)) and game.warning_tiles().has(Vector2i(bomb_tile.x, 0)), "warning marks the entire row and column")
	var safe_tiles: Array[Vector2i] = []
	for y in range(1, game.HEIGHT - 1):
		for x in range(1, game.WIDTH - 1):
			if game.board[y][x] == game.OPEN and x != bomb_tile.x and y != bomb_tile.y:
				safe_tiles.append(Vector2i(x, y))
	check(safe_tiles.size() >= 2, "first wave leaves space to dodge")
	if safe_tiles.size() < 2:
		return
	game.players[0].pos = game.center(safe_tiles[0])
	game.players[1].pos = game.center(safe_tiles[1])
	game.step(5.0, idle, no_bombs)
	check(game.bombs.is_empty() and game.flames.size() > 0, "danger bomb explodes at five minutes")
	check(not game.round_over and game.warning_tiles().is_empty(), "blast clears without closing tiles")
	game.step(10.0, idle, no_bombs)
	check(game.bombs.size() == 2 and game.bombs.all(func(bomb): return bomb.get("danger", false)), "second wave warns with two bombs")
	check(game.warning_tiles().size() > 0, "second wave warning appears five seconds before its blast")


func test_danger_bomb_crosses_walls() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	game.board[5][3] = game.WALL
	game.players[0].pos = game.center(Vector2i(5, 5))
	game.players[1].pos = game.center(Vector2i(7, 7))
	game.bombs.append({"tile": Vector2i(1, 5), "owner": -1, "range": 0, "time": 5.0, "danger": true})
	check(game.warning_tiles().has(Vector2i(5, 5)), "full-cross warning passes through a wall")
	game.step(5.0, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(has_flame(game, Vector2i(5, 5), -1), "danger blast reaches beyond a permanent wall")
	check(game.result == "PLAYER 2 WINS" and game.scores[1].wins == 1, "survivor wins after a danger bomb blast")
	check(game.scores[0].kills == 0 and game.scores[1].kills == 0, "neutral danger bomb awards no Kill")


func test_danger_bomb_waits_through_chain() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	clear_crates(game)
	var danger_bomb := {"tile": Vector2i(3, 3), "owner": -1, "range": 0, "time": 5.0, "danger": true}
	game.bombs.append(danger_bomb)
	game.bombs.append({"tile": Vector2i(3, 4), "owner": 0, "range": 1, "time": 0.0})
	game.update_bombs(0.1)
	check(game.bombs.has(danger_bomb) and not has_flame(game, Vector2i(8, 3), -1), "player bomb cannot trigger danger bomb before its warning ends")


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


func test_night_vision_pickup() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.wall_mode = "night"
	game.rng.seed = 4
	game.new_round()
	check(game.players[0].vision == 1, "night players start with one tile of sight")
	var spawn := Vector2i(1, 1)
	game.pickups[spawn] = game.PICKUP_VISION
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.players[0].vision == 2 and not game.pickups.has(spawn), "vision pickup adds one tile and is consumed")
	game.pickups[spawn] = game.PICKUP_VISION
	game.step(0.016, [Vector2.ZERO, Vector2.ZERO], [false, false])
	check(game.players[0].vision == 3, "vision pickups stack")


func test_night_visibility(arena) -> void:
	arena.selected_wall_mode = "night"
	arena.new_round()
	check(arena.visible_tile(Vector2i(2, 2)), "diagonal tile inside first ring is visible")
	check(not arena.visible_tile(Vector2i(3, 3)), "second ring begins hidden")
	arena.game.players[0].vision = 2
	check(arena.visible_tile(Vector2i(3, 3)), "vision upgrade reveals second ring")
	arena.game.players[0].vision = 3
	check(not arena.visible_tile(Vector2i(4, 4)), "spotlight excludes distant diagonal corners")
	arena.networked = true
	arena.viewer_slot = 0
	check(not arena.visible_tile(Vector2i(11, 9)), "online opponent region stays hidden")
	arena.viewer_slot = 1
	check(arena.visible_tile(Vector2i(11, 9)), "online viewer sees own region")
	arena.game.players[1].alive = false
	check(arena.visible_tile(Vector2i(1, 1)), "eliminated player can watch the rest of the round")
	arena.game.players[1].alive = true
	arena.networked = false
	arena.viewer_slot = -1
	check(arena.visible_tile(Vector2i(1, 1)) and arena.visible_tile(Vector2i(11, 9)), "local players share visible regions")
	arena.selected_wall_mode = "fixed"
	arena.new_round()


func test_night_spotlight(arena) -> void:
	arena.selected_wall_mode = "night"
	arena.new_round()
	arena.networked = true
	arena.viewer_slot = 0
	var center: Vector2 = arena.game.players[0].pos
	var cell: float = arena.game.CELL
	check(is_zero_approx(arena.vision_darkness(center)), "spotlight center is clear")
	var edge: Vector2 = center + Vector2(1.65 * cell, 0)
	var edge_darkness: float = arena.vision_darkness(edge)
	check(edge_darkness > 0.0 and edge_darkness < 1.0, "spotlight edge fades")
	check(is_equal_approx(arena.vision_darkness(center + Vector2(1.65, 1.65) * cell), 1.0), "spotlight is circular")
	arena.game.players[0].vision = 2
	check(is_zero_approx(arena.vision_darkness(edge)), "sight pickup widens spotlight")
	arena.game.players[0].alive = false
	check(is_zero_approx(arena.vision_darkness(edge)), "spectator sees entire map")
	arena.networked = false
	arena.viewer_slot = -1
	arena.selected_wall_mode = "fixed"
	arena.new_round()


func test_night_drops_vision() -> void:
	var game = load("res://scripts/arena_game.gd").new()
	game.wall_mode = "night"
	var found_vision := false
	for seed_value in range(100):
		game.rng.seed = seed_value
		game.new_round()
		game.board[1][2] = game.CRATE
		game.place_bomb(0)
		game.update_bombs(game.FUSE)
		found_vision = game.pickups.get(Vector2i(2, 1), -1) == game.PICKUP_VISION
		if found_vision:
			break
	check(found_vision, "night map can drop vision items")


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
