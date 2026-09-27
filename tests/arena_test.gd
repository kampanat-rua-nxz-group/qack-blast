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
	test_turn_buffer(arena)
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


func test_turn_buffer(arena) -> void:
	arena.new_round()
	clear_crates(arena)
	arena.players[0].pos = arena.center(Vector2i(2, 3)) + Vector2(15, 0)
	arena.travel_direction[0] = Vector2.RIGHT
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	arena._input(key)
	var start_y: float = arena.players[0].pos.y
	var start_x: float = arena.players[0].pos.x
	arena.move_player(0, 0.016)
	check(arena.players[0].pos.x > start_x and arena.players[0].pos.y == start_y, "early turn keeps moving toward junction")
	for frame in range(14):
		arena.move_player(0, 0.016)
	check(arena.players[0].pos.x > start_x + 10.0 and arena.players[0].pos.y < start_y, "early turn input executes at next open junction")


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
