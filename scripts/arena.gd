extends Node2D

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
const COLORS = [Color("65cfc6"), Color("f58fb1")]
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var board: Array = []
var players: Array = []
var bombs: Array = []
var flames: Array = []
var pickups: Dictionary = {}
var round_over := false
var result := ""
var rng := RandomNumberGenerator.new()
var previous_drop := [false, false]
var move_targets := [Vector2.ZERO, Vector2.ZERO]
var held_directions := [[], []]


func _ready() -> void:
	rng.randomize()
	new_round()


func new_round() -> void:
	board.clear()
	bombs.clear()
	flames.clear()
	pickups.clear()
	previous_drop = [false, false]
	move_targets = [Vector2.ZERO, Vector2.ZERO]
	held_directions = [[], []]
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
		players.append({"pos": center(tile), "alive": true, "bomb_limit": 1, "range": 1, "safe_bomb": Vector2i(-1, -1), "facing": 0.0, "visual_facing": 0.0, "walk_phase": 0.0})
	queue_redraw()


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


func _physics_process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and round_over:
		new_round()
	if round_over:
		return
	for i in range(players.size()):
		if not players[i].alive:
			continue
		var old_pos: Vector2 = players[i].pos
		move_player(i, delta)
		players[i].visual_facing = lerp_angle(players[i].visual_facing, players[i].facing, minf(1.0, delta * 12.0))
		players[i].walk_phase = players[i].walk_phase + delta * 18.0 if players[i].pos != old_pos else 0.0
		var drop := Input.is_key_pressed(KEY_SPACE if i == 0 else KEY_ENTER)
		if drop and not previous_drop[i]:
			place_bomb(i)
		previous_drop[i] = drop
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
		for flame in flames:
			if flame.tile == tile:
				players[i].alive = false
				break
	resolve_round()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var player_index := -1
	var direction := Vector2.ZERO
	match event.keycode:
		KEY_A, KEY_LEFT:
			player_index = 0 if event.keycode == KEY_A else 1
			direction = Vector2.LEFT
		KEY_D, KEY_RIGHT:
			player_index = 0 if event.keycode == KEY_D else 1
			direction = Vector2.RIGHT
		KEY_W, KEY_UP:
			player_index = 0 if event.keycode == KEY_W else 1
			direction = Vector2.UP
		KEY_S, KEY_DOWN:
			player_index = 0 if event.keycode == KEY_S else 1
			direction = Vector2.DOWN
	if player_index < 0:
		return
	held_directions[player_index].erase(direction)
	if event.pressed:
		held_directions[player_index].append(direction)
		if not round_over and players[player_index].alive and move_targets[player_index] == Vector2.ZERO:
			start_move(player_index, direction)


func start_move(i: int, direction: Vector2) -> void:
	var next_tile := tile_at(players[i].pos) + Vector2i(direction)
	var target := center(next_tile)
	if can_stand(target, i):
		move_targets[i] = target
		players[i].facing = direction.angle() - PI / 2.0


func move_player(i: int, delta: float) -> void:
	var target: Vector2 = move_targets[i]
	if target == Vector2.ZERO:
		if held_directions[i].is_empty():
			return
		start_move(i, held_directions[i].back())
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
		blast_cell(bomb.tile, bomb.owner, queue)
		for direction in DIRECTIONS:
			for distance in range(1, bomb.range + 1):
				var tile: Vector2i = bomb.tile + direction * distance
				if not inside(tile) or board[tile.y][tile.x] == WALL:
					break
				var hit_crate: bool = crates_at_start.has(tile)
				blast_cell(tile, bomb.owner, queue)
				if hit_crate:
					if board[tile.y][tile.x] == CRATE:
						board[tile.y][tile.x] = OPEN
						destroyed_crates.append(tile)
					break
	for tile in destroyed_crates:
		if rng.randf() < 0.2:
			pickups[tile] = PICKUP_BOMB_CAPACITY if rng.randi_range(0, 1) == 0 else PICKUP_BLAST_RANGE


func blast_cell(tile: Vector2i, bomb_owner: int, queue: Array) -> void:
	pickups.erase(tile)
	flames.append({"tile": tile, "owner": bomb_owner, "time": FLAME_TIME})
	for bomb in bombs:
		if bomb.tile == tile and not queue.has(bomb):
			queue.append(bomb)


func resolve_round() -> void:
	var alive: Array = []
	for i in range(players.size()):
		if players[i].alive:
			alive.append(i)
	if alive.size() > 1:
		return
	round_over = true
	result = "DRAW" if alive.is_empty() else "PLAYER %d WINS" % (alive[0] + 1)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 704)), Color("fff7ed"))
	draw_circle(Vector2(30, 35), 104.0, Color("ffe8d9"))
	draw_circle(Vector2(934, 678), 140.0, Color("e4f5ed"))
	draw_string(font, Vector2(142, 43), "QACK BLAST", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("403d57"))
	draw_string(font, Vector2(143, 66), "a tiny bomb battle for two", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("867f91"))
	rounded_box(Rect2(704, 24, 114, 38), Color("ffe1a6"), 19.0)
	centered_text("LOCAL  2P", Vector2(761, 49), 15, Color("73512d"))
	rounded_box(Rect2(136, 76, 688, 584), Color("d8d2df"), 13.0)
	rounded_box(Rect2(138, 78, 684, 580), Color("fffdf6"), 11.0)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var tile := Vector2i(x, y)
			var rect := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2.ONE * CELL)
			draw_rect(rect, Color("e9f7ed") if (x + y) % 2 == 0 else Color("f2faef"))
			if board[y][x] == WALL:
				draw_wall(rect)
			elif board[y][x] == CRATE:
				draw_crate(rect)
			elif (x * 7 + y * 11) % 23 == 0:
				draw_circle(center(tile) + Vector2(13, -12), 2.5, Color("d3ebd8"))
			if pickups.has(tile):
				draw_pickup(center(tile), pickups[tile])
	for bomb in bombs:
		draw_bomb(center(bomb.tile), bomb.time)
	for flame in flames:
		var spot: Vector2 = center(flame.tile)
		rounded_box(Rect2(spot - Vector2(23, 23), Vector2(46, 46)), Color("ff9b5e"), 16.0)
		draw_circle(spot, 18.0, Color("ffd36d"))
		draw_circle(spot, 10.0, Color("fff3bd"))
	for i in range(players.size()):
		if players[i].alive:
			draw_duck(players[i].pos, i, players[i].visual_facing, players[i].walk_phase)
	for i in range(players.size()):
		draw_player_card(i)
	rounded_box(Rect2(142, 667, 259, 29), Color("e7f2ed"), 14.0)
	rounded_box(Rect2(416, 667, 402, 29), Color("f9e8ed"), 14.0)
	centered_text("P1  WASD  +  SPACE", Vector2(271, 687), 14, Color("366b68"))
	centered_text("P2  ARROWS  +  ENTER     |     R  REMATCH", Vector2(617, 687), 14, Color("92536b"))
	if round_over:
		draw_rect(Rect2(ORIGIN, Vector2(WIDTH * CELL, HEIGHT * CELL)), Color("44395488"))
		rounded_box(Rect2(273, 258, 414, 166), Color("b4a5b8"), 25.0)
		rounded_box(Rect2(269, 253, 414, 166), Color("fffaf0"), 25.0)
		centered_text("ROUND OVER", Vector2(476, 292), 16, Color("aa8a89"))
		centered_text("IT'S A DRAW!" if result == "DRAW" else "PLAYER %d WINS!" % (1 if result == "PLAYER 1 WINS" else 2), Vector2(476, 347), 32, Color("403d57"))
		rounded_box(Rect2(352, 368, 248, 36), Color("ffe1a6"), 18.0)
		centered_text("PRESS R TO PLAY AGAIN", Vector2(476, 392), 16, Color("73512d"))


func rounded_box(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2)), color)
	for offset in [Vector2(radius, radius), Vector2(rect.size.x - radius, radius), Vector2(radius, rect.size.y - radius), Vector2(rect.size.x - radius, rect.size.y - radius)]:
		draw_circle(rect.position + offset, radius, color)


func centered_text(value: String, baseline: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_wall(rect: Rect2) -> void:
	rounded_box(Rect2(rect.position + Vector2(0, 3), rect.size).grow(-2.0), Color("9ba6c7"), 8.0)
	rounded_box(rect.grow(-3.0), Color("bbc8e1"), 8.0)
	draw_line(rect.position + Vector2(11, 11), rect.position + Vector2(37, 11), Color("e4ecf7"), 3.0, true)
	draw_circle(rect.position + Vector2(39, 35), 3.0, Color("a6b7d5"))


func draw_crate(rect: Rect2) -> void:
	rounded_box(Rect2(rect.position + Vector2(0, 3), rect.size).grow(-3.0), Color("b97763"), 9.0)
	rounded_box(rect.grow(-4.0), Color("e9ad83"), 9.0)
	draw_line(rect.position + Vector2(11, 14), rect.position + Vector2(40, 37), Color("fff1d2"), 5.0, true)
	draw_line(rect.position + Vector2(40, 14), rect.position + Vector2(11, 37), Color("fff1d2"), 5.0, true)
	for dot in [Vector2(12, 12), Vector2(39, 12), Vector2(12, 39), Vector2(39, 39)]:
		draw_circle(rect.position + dot, 2.0, Color("c67f66"))


func draw_pickup(pos: Vector2, kind: int) -> void:
	draw_circle(pos + Vector2(0, 3), 17.0, Color("b5cbbd"))
	draw_circle(pos, 17.0, Color("ffe2a0") if kind == PICKUP_BOMB_CAPACITY else Color("d9c6f6"))
	draw_circle(pos, 12.0, Color("fff5d5") if kind == PICKUP_BOMB_CAPACITY else Color("f3e9ff"))
	if kind == PICKUP_BOMB_CAPACITY:
		draw_line(pos + Vector2(-7, 0), pos + Vector2(7, 0), Color("aa714f"), 4.0, true)
		draw_line(pos + Vector2(0, -7), pos + Vector2(0, 7), Color("aa714f"), 4.0, true)
	else:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(-8, 3), pos + Vector2(0, -7), pos + Vector2(8, 3), pos + Vector2(3, 3), pos + Vector2(3, 8), pos + Vector2(-3, 8), pos + Vector2(-3, 3)]), Color("9d72c9"))


func draw_bomb(pos: Vector2, fuse: float) -> void:
	var pulse := 1.0 + 0.07 * sin(Time.get_ticks_msec() * 0.013)
	draw_circle(pos + Vector2(0, 5), 18.0, Color("c0c6ce"))
	draw_circle(pos, 17.0 * pulse, Color("49475f"))
	draw_circle(pos + Vector2(-6, -6), 5.0, Color("77758c"))
	draw_line(pos + Vector2(9, -12), pos + Vector2(14, -20), Color("f7d292"), 3.0, true)
	draw_circle(pos + Vector2(15, -21), 4.0 if fuse > 0.6 else 5.5, Color("ffae69"))


func draw_duck(pos: Vector2, player_index: int, angle: float = 0.0, phase: float = 0.0) -> void:
	var color: Color = COLORS[player_index]
	draw_circle(pos + Vector2(0, 8), 18.0, Color("78978a55"))
	var bounce := -absf(sin(phase)) * 2.5
	var wing_spread := absf(sin(phase)) * 2.0
	draw_set_transform(pos + Vector2(0, bounce), angle, Vector2.ONE)
	draw_circle(Vector2(-13 - wing_spread, 1), 8.0, color.darkened(0.12))
	draw_circle(Vector2(13 + wing_spread, 1), 8.0, color.darkened(0.12))
	draw_circle(Vector2.ZERO, 17.0, color)
	draw_circle(Vector2(-7, -5), 6.0, color.lightened(0.35))
	draw_circle(Vector2(-5, -4), 2.5, Color("403d57"))
	draw_circle(Vector2(6, -4), 2.5, Color("403d57"))
	draw_colored_polygon(PackedVector2Array([Vector2(-5, 3), Vector2(5, 3), Vector2(0, 10)]), Color("ffca79"))
	draw_circle(Vector2(-11, 4), 2.5, Color("f9a8a0"))
	draw_circle(Vector2(11, 4), 2.5, Color("f9a8a0"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_player_card(i: int) -> void:
	var x := 10.0 if i == 0 else 830.0
	var tint := Color("ddf2ed") if i == 0 else Color("fce3eb")
	rounded_box(Rect2(x, 110, 120, 176), Color("e3d8d5"), 17.0)
	rounded_box(Rect2(x, 107, 120, 176), Color("fffdf7"), 17.0)
	rounded_box(Rect2(x + 8, 115, 104, 65), tint, 12.0)
	draw_duck(Vector2(x + 60, 147), i)
	centered_text("PLAYER %d" % (i + 1), Vector2(x + 60, 208), 17, Color("403d57"))
	centered_text("READY!" if players[i].alive else "OUT!", Vector2(x + 60, 229), 13, Color("5f9b80") if players[i].alive else Color("c77c83"))
	centered_text("BOMB %d   FIRE %d" % [players[i].bomb_limit, players[i].range], Vector2(x + 60, 260), 12, Color("827b8b"))
