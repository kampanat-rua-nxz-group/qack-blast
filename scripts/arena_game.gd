extends RefCounted

const WIDTH = 13
const HEIGHT = 11
const CELL = 52.0
const ORIGIN = Vector2(142, 82)
const SPEED = 188.0
const RADIUS = 15.0
const FUSE = 2.5
const FLAME_TIME = 0.5
const WALL = 1
const CRATE = 2
const OPEN = 0
const PICKUP_BOMB_CAPACITY = 0
const PICKUP_BLAST_RANGE = 1
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var board: Array = []
var players: Array = []
var bombs: Array = []
var flames: Array = []
var pickups: Dictionary = {}
var scores := [{"wins": 0, "kills": 0}, {"wins": 0, "kills": 0}]
var round_over := false
var result := ""
var rng := RandomNumberGenerator.new()
var move_targets := [Vector2.ZERO, Vector2.ZERO]


func new_round() -> void:
	board.clear()
	bombs.clear()
	flames.clear()
	pickups.clear()
	move_targets = [Vector2.ZERO, Vector2.ZERO]
	round_over = false
	result = ""
	for y in range(HEIGHT):
		var row: Array = []
		for x in range(WIDTH):
			var edge := x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1
			var pillar := x % 2 == 0 and y % 2 == 0
			row.append(WALL if edge or pillar else (CRATE if rng.randf() < 0.57 else OPEN))
		board.append(row)
	var spawns := [Vector2i(1, 1), Vector2i(WIDTH - 2, HEIGHT - 2)]
	for tile in spawns:
		for clear_tile in [tile, tile + Vector2i.RIGHT, tile + Vector2i.LEFT, tile + Vector2i.UP, tile + Vector2i.DOWN]:
			if inside(clear_tile) and board[clear_tile.y][clear_tile.x] != WALL:
				board[clear_tile.y][clear_tile.x] = OPEN
	ensure_spawn_route(spawns[0], spawns[1])
	players = []
	for tile in spawns:
		players.append({"pos": center(tile), "alive": true, "bomb_limit": 1, "range": 1, "safe_bomb": Vector2i(-1, -1), "facing": 0.0})


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
	for i in range(players.size()):
		if not players[i].alive:
			continue
		move_player(i, delta, directions[i])
		if plant_requests[i]:
			place_bomb(i)
	update_bombs(delta)
	for flame in flames.duplicate():
		flame.time -= delta
		if flame.time <= 0.0:
			flames.erase(flame)
	for i in range(players.size()):
		if not players[i].alive:
			continue
		var tile: Vector2i = tile_at(players[i].pos)
		if pickups.has(tile):
			var kind: int = pickups[tile]
			if kind == PICKUP_BOMB_CAPACITY:
				players[i].bomb_limit = mini(players[i].bomb_limit + 1, 5)
			else:
				players[i].range = mini(players[i].range + 1, 6)
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
		if not players[i].alive and not tied and closest_owner != i:
			scores[closest_owner].kills += 1
	resolve_round()


func start_move(i: int, direction: Vector2) -> void:
	var next_tile := tile_at(players[i].pos) + Vector2i(direction)
	var target := center(next_tile)
	if can_stand(target, i):
		move_targets[i] = target
		players[i].facing = direction.angle() - PI / 2.0


func move_player(i: int, delta: float, direction: Vector2) -> void:
	var target: Vector2 = move_targets[i]
	if target == Vector2.ZERO:
		if direction == Vector2.ZERO:
			return
		start_move(i, direction)
		target = move_targets[i]
		if target == Vector2.ZERO:
			return
	players[i].pos = players[i].pos.move_toward(target, SPEED * delta)
	update_safe_bomb(i)
	if players[i].pos == target:
		move_targets[i] = Vector2.ZERO


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


func update_bombs(delta: float) -> void:
	var queue: Array = []
	for bomb in bombs:
		bomb.time -= delta
		if bomb.time <= 0.0:
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
			pickups[tile] = PICKUP_BOMB_CAPACITY if rng.randi_range(0, 1) == 0 else PICKUP_BLAST_RANGE


func blast_cell(tile: Vector2i, bomb_owner: int, distance: int, queue: Array) -> void:
	pickups.erase(tile)
	flames.append({"tile": tile, "owner": bomb_owner, "distance": distance, "time": FLAME_TIME})
	for bomb in bombs:
		if bomb.tile == tile and not queue.has(bomb):
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
	for i in range(scores.size()):
		order.append(i)
	order.sort_custom(_score_before)
	return order


func _score_before(a: int, b: int) -> bool:
	if scores[a].wins != scores[b].wins:
		return scores[a].wins > scores[b].wins
	if scores[a].kills != scores[b].kills:
		return scores[a].kills > scores[b].kills
	return a < b
