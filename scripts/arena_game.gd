extends RefCounted

var WIDTH := 13
var HEIGHT := 11
var CELL := 52.0
var ORIGIN := Vector2(142, 82)
const SPEED = 188.0
const RADIUS = 15.0
const FUSE = 2.5
const FLAME_TIME = 0.5
const WALL = 1
const CRATE = 2
const OPEN = 0
const PICKUP_BOMB_CAPACITY = 0
const PICKUP_BLAST_RANGE = 1
const PICKUP_VISION = 2
const PICKUP_MYSTERY = 3
const PICKUP_SPEED = 4
const PICKUP_BOMB_KICK = 5
const DEEP_WATER = 3
const SUDDEN_DEATH_START = 180.0
const HAZARD_INTERVAL = 15.0
const HAZARD_WARNING = 5.0
const DANGER_START = SUDDEN_DEATH_START + HAZARD_WARNING
const DANGER_INTERVAL = HAZARD_INTERVAL
const DANGER_WARNING = HAZARD_WARNING
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MAP_MODES = ["fixed", "random", "pond", "frost", "night"]
const MAP_NAMES = {"fixed": "Classic", "random": "Random", "pond": "Lily Pond", "frost": "Frost Garden", "night": "Nightfall"}

var board: Array = []
var terrain: Array = []
var players: Array = []
var bombs: Array = []
var hazards: Array = []
var flames: Array = []
var pickups: Dictionary = {}
var player_count := 2
var wall_mode := "fixed"
var round_elapsed := 0.0
var danger_waves := 0
var next_danger_at := DANGER_START
var next_hazard_at := SUDDEN_DEATH_START
var hazard_waves := 0
var next_night_shuffle_at := 60.0
var scores := [{"wins": 0, "kills": 0}, {"wins": 0, "kills": 0}]
var round_over := false
var result := ""
var rng := RandomNumberGenerator.new()
var move_targets := [Vector2.ZERO, Vector2.ZERO]
var slide_active: Array[bool] = []


func new_round() -> void:
	configure_map(player_count)
	board.clear()
	terrain.clear()
	bombs.clear()
	hazards.clear()
	flames.clear()
	pickups.clear()
	move_targets.clear()
	slide_active.clear()
	for i in range(player_count):
		move_targets.append(Vector2.ZERO)
		slide_active.append(false)
	while scores.size() < player_count:
		scores.append({"wins": 0, "kills": 0})
	round_over = false
	result = ""
	round_elapsed = 0.0
	danger_waves = 0
	next_danger_at = DANGER_START
	next_hazard_at = SUDDEN_DEATH_START
	hazard_waves = 0
	next_night_shuffle_at = 60.0
	for y in range(HEIGHT):
		var row: Array = []
		var terrain_row: Array = []
		for x in range(WIDTH):
			var edge := x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1
			var pillar := false
			var layout_x := x - (WIDTH - 13) / 2
			var layout_y := y - (HEIGHT - 11) / 2
			match wall_mode:
				"fixed":
					pillar = x % 2 == 0 and y % 2 == 0
				"pond":
					pillar = (layout_x in [4, 8] and layout_y in [3, 5, 7]) or (layout_x == 6 and layout_y in [2, 5, 8]) or (layout_y == 5 and layout_x in [2, 10])
				"frost":
					pillar = layout_x in [3, 6, 9] and layout_y in [2, 4, 6, 8]
			row.append(WALL if edge or pillar else OPEN)
			terrain_row.append(0)
		board.append(row)
		terrain.append(terrain_row)
	var spawns := [Vector2i(1, 1), Vector2i(WIDTH - 2, HEIGHT - 2), Vector2i(WIDTH - 2, 1), Vector2i(1, HEIGHT - 2), Vector2i(WIDTH / 2, 1), Vector2i(WIDTH / 2, HEIGHT - 2)]
	spawns.resize(player_count)
	if wall_mode in ["random", "night"]:
		generate_random_walls(spawns)
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			if board[y][x] == OPEN and rng.randf() < 0.57:
				board[y][x] = CRATE
	for tile in spawns:
		for clear_tile in [tile, tile + Vector2i.RIGHT, tile + Vector2i.LEFT, tile + Vector2i.UP, tile + Vector2i.DOWN]:
			if inside(clear_tile) and board[clear_tile.y][clear_tile.x] != WALL:
				board[clear_tile.y][clear_tile.x] = OPEN
	for i in range(1, spawns.size()):
		ensure_spawn_route(spawns[0], spawns[i])
	if wall_mode == "pond":
		for y in range(3, HEIGHT - 2):
			for x in range(1, WIDTH - 1):
				if absi(x - WIDTH / 2) <= 2 and y % 2 == 1 and board[y][x] == OPEN:
					terrain[y][x] = 1
	elif wall_mode == "frost":
		for y in range(3, HEIGHT - 2):
			for x in range(1, WIDTH - 1):
				if absi(x - WIDTH / 2) <= 3 and y % 2 == 1 and board[y][x] == OPEN:
					terrain[y][x] = 2
	players = []
	for tile in spawns:
		players.append({"pos": center(tile), "alive": true, "bomb_limit": 1, "range": 1, "vision": 1, "speed_bonus": 0.0, "can_kick": false, "safe_bomb": Vector2i(-1, -1), "facing": 0.0})


func configure_map(count: int) -> void:
	WIDTH = 15 if count >= 4 else 13
	HEIGHT = 13 if count >= 4 else 11
	CELL = 44.0 if count >= 4 else 52.0
	ORIGIN = Vector2(150, 82) if count >= 4 else Vector2(142, 82)


func generate_random_walls(spawns: Array) -> void:
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var tile := Vector2i(x, y)
			var near_spawn := false
			for spawn in spawns:
				if absi(tile.x - spawn.x) + absi(tile.y - spawn.y) <= 1:
					near_spawn = true
					break
			if near_spawn or rng.randf() >= 0.25:
				continue
			board[y][x] = WALL
			if not open_tiles_connected():
				board[y][x] = OPEN


func open_tiles_connected() -> bool:
	var start := Vector2i(1, 1)
	var visited := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next_tile: Vector2i = tile + direction
			if inside(next_tile) and board[next_tile.y][next_tile.x] != WALL and not visited.has(next_tile):
				visited[next_tile] = true
				queue.append(next_tile)
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			if board[y][x] != WALL and not visited.has(Vector2i(x, y)):
				return false
	return true


func inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < WIDTH and tile.y >= 0 and tile.y < HEIGHT


func ensure_spawn_route(start: Vector2i, target: Vector2i) -> void:
	var queue := [start]
	var previous := {}
	previous[start] = start
	while not queue.is_empty() and not previous.has(target):
		var tile: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next_tile: Vector2i = tile + direction
			if inside(next_tile) and board[next_tile.y][next_tile.x] != WALL and not previous.has(next_tile):
				previous[next_tile] = tile
				queue.append(next_tile)
	var path_tile := target
	while path_tile != start:
		board[path_tile.y][path_tile.x] = OPEN
		path_tile = previous[path_tile]


func center(tile: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(tile) + Vector2(0.5, 0.5)) * CELL


func tile_at(pos: Vector2) -> Vector2i:
	var local := (pos - ORIGIN) / CELL
	return Vector2i(floori(local.x), floori(local.y))


func solid(tile: Vector2i, player_index: int) -> bool:
	if not inside(tile) or board[tile.y][tile.x] != OPEN:
		return true
	for bomb in bombs:
		if bomb.tile == tile and players[player_index].safe_bomb != tile:
			return true
	return false


func can_stand(pos: Vector2, player_index: int) -> bool:
	for dx in [-RADIUS, RADIUS]:
		for dy in [-RADIUS, RADIUS]:
			if solid(tile_at(pos + Vector2(dx, dy)), player_index):
				return false
	return true


func overlaps_tile(pos: Vector2, tile: Vector2i) -> bool:
	for dx in [-RADIUS, RADIUS]:
		for dy in [-RADIUS, RADIUS]:
			if tile_at(pos + Vector2(dx, dy)) == tile:
				return true
	return false


func step(delta: float, directions: Array, plant_requests: Array) -> void:
	if round_over:
		return
	var previous_elapsed := round_elapsed
	round_elapsed += delta
	schedule_hazards(previous_elapsed)
	for i in range(players.size()):
		if not players[i].alive:
			continue
		move_player(i, delta, directions[i])
		if plant_requests[i]:
			place_bomb(i)
	for flame in flames.duplicate():
		flame.time -= delta
		if flame.time <= 0.0:
			flames.erase(flame)
	update_moving_bombs(delta)
	update_bombs(delta)
	for hazard in hazards.duplicate():
		hazard.time -= delta
		if hazard.time <= 0.0:
			hazards.erase(hazard)
			resolve_hazard(hazard)
	for i in range(players.size()):
		if not players[i].alive:
			continue
		var tile: Vector2i = tile_at(players[i].pos)
		if pickups.has(tile):
			var kind: int = pickups[tile]
			match kind:
				PICKUP_BOMB_CAPACITY:
					players[i].bomb_limit = mini(players[i].bomb_limit + 1, 5)
				PICKUP_BLAST_RANGE:
					players[i].range = mini(players[i].range + 1, 6)
				PICKUP_VISION:
					players[i].vision += 1
				PICKUP_MYSTERY:
					var can_add_bomb: bool = players[i].bomb_limit < 5
					var can_add_range: bool = players[i].range < 6
					if can_add_bomb and (not can_add_range or rng.randi_range(0, 1) == 0):
						players[i].bomb_limit += 1
					elif can_add_range:
						players[i].range += 1
				PICKUP_SPEED:
					players[i].speed_bonus = minf(players[i].speed_bonus + 0.25, 0.5)
				PICKUP_BOMB_KICK:
					players[i].can_kick = true
			pickups.erase(tile)
		var closest_distance := 1_000_000
		var closest_owner := -1
		var tied := false
		for flame in flames:
			if flame.tile != tile:
				continue
			players[i].alive = false
			if flame.distance < closest_distance:
				closest_distance = flame.distance
				closest_owner = flame.owner
				tied = false
			elif flame.distance == closest_distance and flame.owner != closest_owner:
				tied = true
		if not players[i].alive and not tied and closest_owner >= 0 and closest_owner != i:
			scores[closest_owner].kills += 1
	resolve_round()


func schedule_hazards(previous_elapsed: float) -> void:
	if wall_mode == "fixed":
		schedule_danger_bombs(previous_elapsed)
	elif wall_mode == "random":
		while round_elapsed >= next_hazard_at:
			hazard_waves += 1
			var available: Array[Vector2i] = []
			for y in range(1, HEIGHT - 1):
				for x in range(1, WIDTH - 1):
					if board[y][x] == OPEN:
						available.append(Vector2i(x, y))
			var tiles: Array[Vector2i] = []
			for i in range(mini(1 << (hazard_waves - 1), available.size())):
				tiles.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
			hazards.append({"kind": "random_burst", "tiles": tiles, "time": next_hazard_at + HAZARD_WARNING - previous_elapsed})
			next_hazard_at += HAZARD_INTERVAL
	elif wall_mode == "pond":
		while round_elapsed >= next_hazard_at:
			var ring: int = hazard_waves + 1
			hazard_waves += 1
			var tiles: Array[Vector2i] = []
			for y in range(1, HEIGHT - 1):
				for x in range(1, WIDTH - 1):
					if mini(mini(x, WIDTH - 1 - x), mini(y, HEIGHT - 1 - y)) == ring:
						tiles.append(Vector2i(x, y))
			hazards.append({"kind": "flood", "tiles": tiles, "time": next_hazard_at + HAZARD_WARNING - previous_elapsed})
			next_hazard_at += HAZARD_INTERVAL
	elif wall_mode == "frost":
		while round_elapsed >= next_hazard_at:
			hazard_waves += 1
			var available_rows: Array[int] = []
			for y in range(1, HEIGHT - 1):
				available_rows.append(y)
			var tiles: Array[Vector2i] = []
			for i in range(mini(1 << (hazard_waves - 1), available_rows.size())):
				var y: int = available_rows.pop_at(rng.randi_range(0, available_rows.size() - 1))
				for x in range(WIDTH):
					tiles.append(Vector2i(x, y))
			hazards.append({"kind": "blizzard", "tiles": tiles, "time": next_hazard_at + HAZARD_WARNING - previous_elapsed})
			next_hazard_at += HAZARD_INTERVAL
	elif wall_mode == "night":
		while next_night_shuffle_at < SUDDEN_DEATH_START and round_elapsed >= next_night_shuffle_at:
			reshuffle_night_walls()
			next_night_shuffle_at += 60.0
		while round_elapsed >= next_hazard_at:
			var ring: int = hazard_waves + 1
			hazard_waves += 1
			var tiles: Array[Vector2i] = []
			for y in range(1, HEIGHT - 1):
				for x in range(1, WIDTH - 1):
					if mini(mini(x, WIDTH - 1 - x), mini(y, HEIGHT - 1 - y)) == ring:
						tiles.append(Vector2i(x, y))
			hazards.append({"kind": "closing_walls", "tiles": tiles, "time": next_hazard_at + HAZARD_WARNING - previous_elapsed})
			next_hazard_at += HAZARD_INTERVAL


func reshuffle_night_walls() -> void:
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			if board[y][x] == WALL:
				board[y][x] = OPEN
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var tile := Vector2i(x, y)
			if board[y][x] != OPEN or rng.randf() >= 0.25:
				continue
			var protected := pickups.has(tile)
			for bomb in bombs:
				if bomb.tile == tile:
					protected = true
			for flame in flames:
				if flame.tile == tile:
					protected = true
			for i in range(players.size()):
				if players[i].alive and (overlaps_tile(players[i].pos, tile) or (move_targets[i] != Vector2.ZERO and tile_at(move_targets[i]) == tile)):
					protected = true
			if protected:
				continue
			board[y][x] = WALL
			if not open_tiles_connected():
				board[y][x] = OPEN


func resolve_hazard(hazard: Dictionary) -> void:
	if hazard.kind in ["random_burst", "blizzard"]:
		var triggered: Array = []
		for tile in hazard.tiles:
			blast_cell(tile, -1, 0, triggered)
			if board[tile.y][tile.x] == CRATE:
				board[tile.y][tile.x] = OPEN
		for bomb in triggered:
			bomb.time = 0.0
		if not triggered.is_empty():
			update_bombs(0.0)
	elif hazard.kind == "flood":
		for tile in hazard.tiles:
			board[tile.y][tile.x] = DEEP_WATER
			pickups.erase(tile)
			for bomb in bombs.duplicate():
				if bomb.tile == tile:
					bombs.erase(bomb)
			for i in range(players.size()):
				if players[i].alive and overlaps_tile(players[i].pos, tile):
					players[i].alive = false
	elif hazard.kind == "closing_walls":
		for tile in hazard.tiles:
			board[tile.y][tile.x] = WALL
			pickups.erase(tile)
			for bomb in bombs.duplicate():
				if bomb.tile == tile:
					bombs.erase(bomb)
			for i in range(players.size()):
				if players[i].alive and overlaps_tile(players[i].pos, tile):
					players[i].alive = false
				if move_targets[i] != Vector2.ZERO and tile_at(move_targets[i]) == tile:
					move_targets[i] = Vector2.ZERO


func schedule_danger_bombs(previous_elapsed: float) -> void:
	while round_elapsed >= next_danger_at - DANGER_WARNING:
		danger_waves += 1
		var available: Array[Vector2i] = []
		for y in range(1, HEIGHT - 1):
			for x in range(1, WIDTH - 1):
				var tile := Vector2i(x, y)
				if board[y][x] != OPEN:
					continue
				var occupied := false
				for bomb in bombs:
					if bomb.tile == tile:
						occupied = true
						break
				if not occupied:
					available.append(tile)
		for i in range(mini(1 << (danger_waves - 1), available.size())):
			var index := rng.randi_range(0, available.size() - 1)
			bombs.append({"tile": available.pop_at(index), "owner": -1, "range": 0, "time": next_danger_at - previous_elapsed, "danger": true})
		next_danger_at += DANGER_INTERVAL


func warning_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for hazard in hazards:
		if hazard.time > 0.0:
			for tile in hazard.tiles:
				if not tiles.has(tile):
					tiles.append(tile)
	for bomb in bombs:
		if not bomb.get("danger", false) or bomb.time <= 0.0:
			continue
		for x in range(WIDTH):
			var row_tile := Vector2i(x, bomb.tile.y)
			if not tiles.has(row_tile):
				tiles.append(row_tile)
		for y in range(HEIGHT):
			var column_tile := Vector2i(bomb.tile.x, y)
			if not tiles.has(column_tile):
				tiles.append(column_tile)
	return tiles


func start_move(i: int, direction: Vector2) -> void:
	var next_tile := tile_at(players[i].pos) + Vector2i(direction)
	var target := center(next_tile)
	if wall_mode == "frost" and players[i].can_kick:
		try_kick_bomb(next_tile, Vector2i(direction))
	if can_stand(target, i):
		move_targets[i] = target
		players[i].facing = direction.angle() - PI / 2.0


func try_kick_bomb(tile: Vector2i, direction: Vector2i) -> bool:
	for bomb in bombs:
		if bomb.tile != tile or bomb.get("danger", false):
			continue
		var next_tile: Vector2i = tile + direction
		if not inside(next_tile) or board[next_tile.y][next_tile.x] != OPEN:
			return false
		for other in bombs:
			if other != bomb and other.tile == next_tile:
				return false
		bomb.tile = next_tile
		bomb.kick_direction = direction
		bomb.kick_progress = 0.0
		return true
	return false


func move_player(i: int, delta: float, direction: Vector2) -> void:
	var target: Vector2 = move_targets[i]
	if target == Vector2.ZERO:
		if direction == Vector2.ZERO:
			return
		start_move(i, direction)
		target = move_targets[i]
		if target == Vector2.ZERO:
			return
	var speed: float = SPEED * (1.0 + players[i].speed_bonus)
	if terrain[tile_at(players[i].pos).y][tile_at(players[i].pos).x] == 1:
		speed *= 0.8
	var travel_direction := Vector2i(int(sign(target.x - players[i].pos.x)), int(sign(target.y - players[i].pos.y)))
	players[i].pos = players[i].pos.move_toward(target, speed * delta)
	update_safe_bomb(i)
	if players[i].pos == target:
		move_targets[i] = Vector2.ZERO
		if slide_active[i]:
			slide_active[i] = false
		elif wall_mode == "frost" and terrain[tile_at(target).y][tile_at(target).x] == 2:
			var slide_target := center(tile_at(target) + travel_direction)
			if can_stand(slide_target, i):
				move_targets[i] = slide_target
				slide_active[i] = true


func update_safe_bomb(i: int) -> void:
	# A trailing edge can still overlap the bomb after the centre enters the next tile.
	if not overlaps_tile(players[i].pos, players[i].safe_bomb):
		players[i].safe_bomb = Vector2i(-1, -1)


func place_bomb(i: int) -> void:
	if not players[i].alive:
		return
	var tile: Vector2i = tile_at(players[i].pos)
	var active := 0
	for bomb in bombs:
		if bomb.owner == i:
			active += 1
		if bomb.tile == tile:
			return
	if active >= players[i].bomb_limit:
		return
	bombs.append({"tile": tile, "owner": i, "range": players[i].range, "time": FUSE})
	players[i].safe_bomb = tile


func update_moving_bombs(delta: float) -> void:
	for bomb in bombs:
		var direction: Vector2i = bomb.get("kick_direction", Vector2i.ZERO)
		if direction == Vector2i.ZERO:
			continue
		bomb.kick_progress = bomb.get("kick_progress", 0.0) + minf(delta, maxf(bomb.time, 0.0)) * 4.0
		while bomb.kick_progress >= 1.0:
			var next_tile: Vector2i = bomb.tile + direction
			var blocked: bool = not inside(next_tile) or board[next_tile.y][next_tile.x] != OPEN
			if not blocked:
				for other in bombs:
					if other != bomb and other.tile == next_tile:
						blocked = true
						break
			if blocked:
				bomb.kick_direction = Vector2i.ZERO
				bomb.kick_progress = 0.0
				break
			bomb.tile = next_tile
			bomb.kick_progress -= 1.0


func update_bombs(delta: float) -> void:
	var queue: Array = []
	for bomb in bombs:
		bomb.time -= delta
		if bomb.time <= 0.00001:
			queue.append(bomb)
	if queue.is_empty():
		return
	var crates_at_start := {}
	var destroyed_crates: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			if board[y][x] == CRATE:
				crates_at_start[Vector2i(x, y)] = true
	while not queue.is_empty():
		var bomb: Dictionary = queue.pop_front()
		if not bombs.has(bomb):
			continue
		bombs.erase(bomb)
		if bomb.get("danger", false):
			for x in range(WIDTH):
				var row_tile := Vector2i(x, bomb.tile.y)
				blast_cell(row_tile, -1, absi(x - bomb.tile.x), queue)
				if board[row_tile.y][row_tile.x] == CRATE:
					board[row_tile.y][row_tile.x] = OPEN
					destroyed_crates.append(row_tile)
			for y in range(HEIGHT):
				if y == bomb.tile.y:
					continue
				var column_tile := Vector2i(bomb.tile.x, y)
				blast_cell(column_tile, -1, absi(y - bomb.tile.y), queue)
				if board[column_tile.y][column_tile.x] == CRATE:
					board[column_tile.y][column_tile.x] = OPEN
					destroyed_crates.append(column_tile)
			continue
		blast_cell(bomb.tile, bomb.owner, 0, queue)
		for direction in DIRECTIONS:
			for distance in range(1, bomb.range + 1):
				var tile: Vector2i = bomb.tile + direction * distance
				if not inside(tile) or board[tile.y][tile.x] == WALL:
					break
				var hit_crate: bool = crates_at_start.has(tile)
				blast_cell(tile, bomb.owner, distance, queue)
				if hit_crate:
					if board[tile.y][tile.x] == CRATE:
						board[tile.y][tile.x] = OPEN
						destroyed_crates.append(tile)
					break
	for tile in destroyed_crates:
		if rng.randf() < 0.2:
			var kinds := [PICKUP_BOMB_CAPACITY, PICKUP_BLAST_RANGE]
			match wall_mode:
				"night":
					kinds.append(PICKUP_VISION)
				"random":
					kinds.append(PICKUP_MYSTERY)
				"pond":
					kinds.append(PICKUP_SPEED)
				"frost":
					kinds.append(PICKUP_BOMB_KICK)
			pickups[tile] = kinds[rng.randi_range(0, kinds.size() - 1)]


func blast_cell(tile: Vector2i, bomb_owner: int, distance: int, queue: Array) -> void:
	pickups.erase(tile)
	flames.append({"tile": tile, "owner": bomb_owner, "distance": distance, "time": FLAME_TIME})
	for bomb in bombs:
		if bomb.tile == tile and not bomb.get("danger", false) and not queue.has(bomb):
			queue.append(bomb)


func resolve_round() -> void:
	if round_over:
		return
	var alive: Array = []
	for i in range(players.size()):
		if players[i].alive:
			alive.append(i)
	if alive.size() > 1:
		return
	round_over = true
	if alive.size() == 1:
		scores[alive[0]].wins += 1
	result = "DRAW" if alive.is_empty() else "PLAYER %d WINS" % (alive[0] + 1)


func score_order() -> Array[int]:
	var order: Array[int] = []
	for i in range(players.size()):
		order.append(i)
	order.sort_custom(_score_before)
	return order


func _score_before(a: int, b: int) -> bool:
	if scores[a].wins != scores[b].wins:
		return scores[a].wins > scores[b].wins
	if scores[a].kills != scores[b].kills:
		return scores[a].kills > scores[b].kills
	return a < b
