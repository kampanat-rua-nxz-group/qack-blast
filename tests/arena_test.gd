extends SceneTree

var failures := 0


func _initialize() -> void:
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
	test_spawn_routes(arena)
	test_bomb_exit(arena)
	test_one_press_moves_one_tile(arena)
	test_hold_repeats_at_tile_centers(arena)
	test_initial_blast_range(arena)
	test_simultaneous_blasts(arena)
	test_pickup_after_simultaneous_blasts(arena)
	print("Arena checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func test_spawn_routes(arena) -> void:
	for seed_value in range(100):
		arena.rng.seed = seed_value
		arena.new_round()
		var start := Vector2i(1, 1)
		var target := Vector2i(arena.WIDTH - 2, arena.HEIGHT - 2)
		var visited := {}
		visited[start] = true
		var queue := [start]
		while not queue.is_empty():
			var tile: Vector2i = queue.pop_front()
			for direction in arena.DIRECTIONS:
				var next_tile: Vector2i = tile + direction
				if arena.inside(next_tile) and arena.board[next_tile.y][next_tile.x] == arena.OPEN and not visited.has(next_tile):
					visited[next_tile] = true
					queue.append(next_tile)
		check(visited.has(target), "seed %d connects the spawns" % seed_value)


func test_bomb_exit(arena) -> void:
	arena.new_round()
	arena.place_bomb(0)
	var spawn := Vector2i(1, 1)
	var crossed: Vector2 = arena.center(spawn) + Vector2(arena.CELL * 0.51, 0.0)
	arena.players[0].pos = crossed
	arena.update_safe_bomb(0)
	check(arena.players[0].safe_bomb == spawn, "placer stays exempt while body overlaps bomb tile")
	check(arena.can_stand(crossed + Vector2(3, 0), 0), "placer can keep moving away from bomb")
	arena.players[0].pos = arena.center(spawn) + Vector2(arena.CELL * 0.9, 0.0)
	arena.update_safe_bomb(0)
	check(arena.players[0].safe_bomb != spawn, "bomb blocks re-entry after player fully exits")
	check(not arena.can_stand(crossed, 0), "placer cannot overlap bomb again after exiting")


func test_simultaneous_blasts(arena) -> void:
	arena.new_round()
	clear_crates(arena)
	arena.board[3][5] = arena.CRATE
	arena.bombs = [
		{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0},
		{"tile": Vector2i(7, 3), "owner": 1, "range": 4, "time": 0.0},
	]
	arena.update_bombs(0.016)
	check(not has_flame(arena, Vector2i(4, 3), 1), "second blast stops at crate destroyed in same tick")


func test_one_press_moves_one_tile(arena) -> void:
	arena.new_round()
	clear_crates(arena)
	var start: Vector2 = arena.center(Vector2i(3, 3))
	arena.players[0].pos = start
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
	arena.move_player(0, 0.016)
	check(arena.players[0].pos.x > start.x and arena.players[0].pos.y == start.y, "movement stays on the tile centerline")
	for frame in range(40):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos == start + Vector2(arena.CELL, 0), "one press finishes at the next tile center")
	for frame in range(40):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos == start + Vector2(arena.CELL, 0), "one press never starts a second tile")
	key.pressed = false
	arena._input(key)
	key.pressed = true
	arena._input(key)
	key.pressed = false
	arena._input(key)
	for frame in range(40):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos == start + Vector2(arena.CELL * 2, 0), "another press moves exactly one more tile")
	arena.board[3][6] = arena.CRATE
	key.pressed = true
	arena._input(key)
	for frame in range(40):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos == start + Vector2(arena.CELL * 2, 0), "blocked press leaves player at tile center")


func test_hold_repeats_at_tile_centers(arena) -> void:
	arena.new_round()
	clear_crates(arena)
	var start: Vector2 = arena.center(Vector2i(3, 3))
	arena.players[0].pos = start
	var right := InputEventKey.new()
	right.keycode = KEY_D
	right.pressed = true
	arena._input(right)
	for frame in range(20):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos.x > start.x + arena.CELL, "holding starts another tile after reaching center")
	var up := InputEventKey.new()
	up.keycode = KEY_W
	up.pressed = true
	arena._input(up)
	right.pressed = false
	arena._input(right)
	for frame in range(10):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos.y == start.y, "new direction does not turn before tile center")
	for frame in range(10):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos.x == start.x + arena.CELL * 2 and arena.players[0].pos.y < start.y, "held direction turns at next tile center")
	up.pressed = false
	arena._input(up)
	for frame in range(40):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos == start + Vector2(arena.CELL * 2, -arena.CELL), "release after turning stops at center")


func test_initial_blast_range(arena) -> void:
	arena.new_round()
	clear_crates(arena)
	arena.players[0].pos = arena.center(Vector2i(3, 3))
	arena.place_bomb(0)
	arena.update_bombs(arena.FUSE)
	check(has_flame(arena, Vector2i(4, 3), 0), "initial blast reaches the adjacent tile")
	check(not has_flame(arena, Vector2i(5, 3), 0), "initial blast stops before the second tile")


func test_pickup_after_simultaneous_blasts(arena) -> void:
	var crate := Vector2i(5, 3)
	for seed_value in range(50):
		var drops := []
		for bomb_count in [1, 2]:
			arena.new_round()
			clear_crates(arena)
			arena.board[crate.y][crate.x] = arena.CRATE
			arena.rng.seed = seed_value
			arena.bombs = [{"tile": Vector2i(3, 3), "owner": 0, "range": 4, "time": 0.0}]
			if bomb_count == 2:
				arena.bombs.append({"tile": Vector2i(7, 3), "owner": 1, "range": 4, "time": 0.0})
			arena.update_bombs(0.016)
			drops.append(arena.pickups.has(crate))
		if drops[0] != drops[1]:
			check(false, "crate pickup survives a second blast in the same tick (seed %d)" % seed_value)
			return


func clear_crates(arena) -> void:
	for y in range(1, arena.HEIGHT - 1):
		for x in range(1, arena.WIDTH - 1):
			if arena.board[y][x] != arena.WALL:
				arena.board[y][x] = arena.OPEN


func has_flame(arena, tile: Vector2i, owner: int) -> bool:
	for flame in arena.flames:
		if flame.tile == tile and flame.owner == owner:
			return true
	return false
