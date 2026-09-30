extends Node2D

const COLORS = [Color("65cfc6"), Color("f58fb1"), Color("f4c66c"), Color("a995e8"), Color("7abf70"), Color("e58a5e")]

var game
var display_state: Dictionary = {}
var viewer_slot := -1
var networked := false
var visual_facing: Array = []
var walk_phase: Array = []


func present(next_game, next_display_state: Dictionary, next_viewer_slot: int) -> void:
	game = next_game
	display_state = next_display_state
	viewer_slot = next_viewer_slot
	queue_redraw()


func fit_to(region: Rect2, display_cell: float) -> void:
	var world_size: Vector2 = Vector2(game.WIDTH, game.HEIGHT) * game.CELL
	var factor: float = minf(display_cell / game.CELL, minf(region.size.x / world_size.x, region.size.y / world_size.y))
	scale = Vector2.ONE * factor
	position = region.position + (region.size - world_size * factor) * 0.5 - game.ORIGIN * factor


func player_position(i: int) -> Vector2:
	return display_state.positions[i] if display_state.has("positions") else game.players[i].pos


func player_facing(i: int) -> float:
	if display_state.has("facing"):
		return display_state.facing[i]
	return visual_facing[i] if i < visual_facing.size() else game.players[i].facing


func player_walk_phase(i: int) -> float:
	if display_state.has("walk_phase"):
		return display_state.walk_phase[i]
	return walk_phase[i] if i < walk_phase.size() else 0.0


func _draw() -> void:
	if game == null:
		return
	var colors := map_colors(game.wall_mode)
	for y in range(game.HEIGHT):
		for x in range(game.WIDTH):
			var tile := Vector2i(x, y)
			var rect := Rect2(game.ORIGIN + Vector2(x, y) * game.CELL, Vector2.ONE * game.CELL)
			draw_rect(rect, colors.floor if (x + y) % 2 == 0 else colors.floor_alt)
			if game.board[y][x] == game.DEEP_WATER:
				draw_rect(rect, Color("3b88b3"))
			elif game.terrain[y][x] == 1:
				draw_rect(rect.grow(-3.0), Color("92d9dd"))
			elif game.terrain[y][x] == 2:
				draw_rect(rect.grow(-3.0), Color("c5e9f7"))
			if game.board[y][x] == game.WALL:
				draw_wall(rect, colors)
			elif game.board[y][x] == game.CRATE:
				draw_crate(rect, colors)
			elif (x * 7 + y * 11) % 23 == 0:
				draw_circle(game.center(tile) + Vector2(13, -12), 2.5, colors.decor)
			if game.pickups.has(tile):
				draw_pickup(game.center(tile), game.pickups[tile])
	for bomb in game.bombs:
		if not bomb.get("danger", false):
			var kick_direction: Vector2i = bomb.get("kick_direction", Vector2i.ZERO)
			draw_bomb(game.center(bomb.tile) + Vector2(kick_direction) * game.CELL * bomb.get("kick_progress", 0.0), bomb.time)
	var flame_owners := {}
	for flame in game.flames:
		if not flame_owners.has(flame.tile):
			flame_owners[flame.tile] = []
		var owners: Array = flame_owners[flame.tile]
		if not owners.has(flame.owner):
			owners.append(flame.owner)
	for tile in flame_owners:
		draw_flame(game.center(tile), flame_owners[tile])
	for flame in game.flames:
		if flame.get("kind", "") == "blizzard":
			draw_line(game.center(flame.tile) + Vector2(-17, -17), game.center(flame.tile) + Vector2(17, 17), Color("ddf9ff"), 4.0, true)
		elif flame.get("kind", "") == "random_burst":
			draw_arc(game.center(flame.tile), 17.0, 0.0, TAU, 24, Color("c18cff"), 4.0, true)
	for i in range(game.players.size()):
		if game.players[i].alive:
			draw_duck(player_position(i), i, player_facing(i), player_walk_phase(i))
	if game.wall_mode == "night" and not game.round_over:
		draw_night_vision()
	if int(floor(game.round_elapsed * 2.0)) % 2 == 0:
		for hazard in game.hazards:
			var color := Color("bd89f5")
			match hazard.kind:
				"flood": color = Color("5bc9e8")
				"blizzard": color = Color("d8f6ff")
				"closing_walls": color = Color("a6abbc")
			for tile in hazard.tiles:
				var rect := Rect2(game.ORIGIN + Vector2(tile) * game.CELL, Vector2.ONE * game.CELL)
				draw_rect(rect.grow(-3.0), color, false, 5.0)
		for bomb in game.bombs:
			if not bomb.get("danger", false):
				continue
			for x in range(game.WIDTH):
				var row_rect := Rect2(game.ORIGIN + Vector2(x, bomb.tile.y) * game.CELL, Vector2.ONE * game.CELL)
				draw_rect(row_rect.grow(-3.0), Color("f5a65599"), false, 5.0)
			for y in range(game.HEIGHT):
				var column_rect := Rect2(game.ORIGIN + Vector2(bomb.tile.x, y) * game.CELL, Vector2.ONE * game.CELL)
				draw_rect(column_rect.grow(-3.0), Color("f5a65599"), false, 5.0)
	for bomb in game.bombs:
		if bomb.get("danger", false):
			draw_bomb(game.center(bomb.tile), bomb.time)


func rounded_box(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2)), color)
	for offset in [Vector2(radius, radius), Vector2(rect.size.x - radius, radius), Vector2(radius, rect.size.y - radius), Vector2(rect.size.x - radius, rect.size.y - radius)]:
		draw_circle(rect.position + offset, radius, color)


func centered_text(value: String, baseline: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func map_colors(mode: String) -> Dictionary:
	match mode:
		"night":
			return {"frame": Color("354460"), "floor": Color("63728b"), "floor_alt": Color("586880"), "wall": Color("3d5072"), "wall_shadow": Color("263752"), "wall_highlight": Color("788da9"), "wall_dot": Color("a8b9cc"), "crate": Color("917d8c"), "crate_shadow": Color("5c5065"), "crate_detail": Color("cbb6bb"), "crate_dot": Color("e2ccd0"), "decor": Color("c1d3ec")}
		"pond":
			return {"frame": Color("8cbca9"), "floor": Color("d8f1e6"), "floor_alt": Color("c9e9df"), "wall": Color("60aa91"), "wall_shadow": Color("397e70"), "wall_highlight": Color("a9dfbb"), "wall_dot": Color("398a78"), "crate": Color("e6be81"), "crate_shadow": Color("a77a55"), "crate_detail": Color("fff0bb"), "crate_dot": Color("a87848"), "decor": Color("6ebaa1")}
		"frost":
			return {"frame": Color("a5b6d4"), "floor": Color("e7f5fb"), "floor_alt": Color("d6ebf6"), "wall": Color("9dc9e8"), "wall_shadow": Color("648bb9"), "wall_highlight": Color("f3fbff"), "wall_dot": Color("77a9cf"), "crate": Color("b5a8d8"), "crate_shadow": Color("8178ad"), "crate_detail": Color("e8ddfa"), "crate_dot": Color("8f81b7"), "decor": Color("9ccde4")}
		_:
			return {"frame": Color("d8d2df"), "floor": Color("e9f7ed"), "floor_alt": Color("f2faef"), "wall": Color("bbc8e1"), "wall_shadow": Color("9ba6c7"), "wall_highlight": Color("e4ecf7"), "wall_dot": Color("a6b7d5"), "crate": Color("e9ad83"), "crate_shadow": Color("b97763"), "crate_detail": Color("fff1d2"), "crate_dot": Color("c67f66"), "decor": Color("d3ebd8")}


func visible_tile(tile: Vector2i) -> bool:
	return vision_darkness(game.center(tile)) < 1.0


func vision_darkness(point: Vector2) -> float:
	if game.wall_mode != "night" or game.round_over:
		return 0.0
	if networked and (viewer_slot < 0 or not game.players[viewer_slot].alive):
		return 0.0
	var darkness := 1.0
	for i in range(game.players.size()):
		if networked and i != viewer_slot:
			continue
		if not game.players[i].alive:
			continue
		var radius: float = (game.players[i].vision + 0.9) * game.CELL
		var fade_start: float = radius - game.CELL * 0.5
		var fade: float = clampf((point.distance_to(player_position(i)) - fade_start) / (radius - fade_start), 0.0, 1.0)
		darkness = minf(darkness, fade * fade * (3.0 - 2.0 * fade))
	return darkness


func draw_night_vision() -> void:
	var step: float = game.CELL / 4.0
	for y in range(game.HEIGHT):
		for x in range(game.WIDTH):
			var origin: Vector2 = game.ORIGIN + Vector2(x, y) * game.CELL
			var corners := [vision_darkness(origin), vision_darkness(origin + Vector2(game.CELL, 0)), vision_darkness(origin + Vector2.ONE * game.CELL), vision_darkness(origin + Vector2(0, game.CELL)), vision_darkness(origin + Vector2.ONE * game.CELL * 0.5)]
			if corners.max() <= 0.0:
				continue
			if corners.min() >= 1.0:
				draw_rect(Rect2(origin, Vector2.ONE * game.CELL), Color("111727"))
				continue
			for row in range(4):
				for column in range(4):
					var top_left: Vector2 = origin + Vector2(column, row) * step
					var top_right: Vector2 = top_left + Vector2(step, 0)
					var bottom_right: Vector2 = top_left + Vector2(step, step)
					var bottom_left: Vector2 = top_left + Vector2(0, step)
					var alphas := [vision_darkness(top_left), vision_darkness(top_right), vision_darkness(bottom_right), vision_darkness(bottom_left)]
					if alphas.max() <= 0.0:
						continue
					if alphas.min() >= 1.0:
						draw_rect(Rect2(top_left, Vector2.ONE * step), Color("111727"))
						continue
					var colors := PackedColorArray()
					for alpha in alphas:
						colors.append(Color(Color("111727"), alpha))
					draw_polygon(PackedVector2Array([top_left, top_right, bottom_right, bottom_left]), colors)


func draw_wall(rect: Rect2, colors: Dictionary) -> void:
	rounded_box(Rect2(rect.position + Vector2(0, 3), rect.size).grow(-2.0), colors.wall_shadow, 8.0)
	rounded_box(rect.grow(-3.0), colors.wall, 8.0)
	draw_line(rect.position + Vector2(11, 11), rect.position + Vector2(37, 11), colors.wall_highlight, 3.0, true)
	draw_circle(rect.position + Vector2(39, 35), 3.0, colors.wall_dot)


func draw_crate(rect: Rect2, colors: Dictionary) -> void:
	rounded_box(Rect2(rect.position + Vector2(0, 3), rect.size).grow(-3.0), colors.crate_shadow, 9.0)
	rounded_box(rect.grow(-4.0), colors.crate, 9.0)
	draw_line(rect.position + Vector2(11, 14), rect.position + Vector2(40, 37), colors.crate_detail, 5.0, true)
	draw_line(rect.position + Vector2(40, 14), rect.position + Vector2(11, 37), colors.crate_detail, 5.0, true)
	for dot in [Vector2(12, 12), Vector2(39, 12), Vector2(12, 39), Vector2(39, 39)]:
		draw_circle(rect.position + dot, 2.0, colors.crate_dot)


func draw_pickup(pos: Vector2, kind: int) -> void:
	draw_circle(pos + Vector2(0, 3), 17.0, Color("b5cbbd"))
	if kind == game.PICKUP_MYSTERY:
		draw_circle(pos, 17.0, Color("f4accb"))
		draw_circle(pos, 12.0, Color("ffe4f0"))
		centered_text("?", pos + Vector2(0, 7), 21, Color("944d75"))
		return
	if kind == game.PICKUP_SPEED:
		draw_circle(pos, 17.0, Color("88dbac"))
		draw_circle(pos, 12.0, Color("ddffe9"))
		draw_line(pos + Vector2(-7, 4), pos + Vector2(7, -4), Color("438566"), 4.0, true)
		return
	if kind == game.PICKUP_BOMB_KICK:
		draw_circle(pos, 17.0, Color("a9d6f2"))
		draw_circle(pos, 12.0, Color("e5f6ff"))
		draw_circle(pos + Vector2(-4, 0), 5.0, Color("49799c"))
		draw_line(pos + Vector2(2, 0), pos + Vector2(9, 0), Color("49799c"), 3.0, true)
		return
	if kind == game.PICKUP_VISION:
		draw_circle(pos, 17.0, Color("a2dbef"))
		draw_circle(pos, 12.0, Color("e3f8ff"))
		draw_arc(pos, 8.0, 0.0, TAU, 24, Color("39769b"), 2.5, true)
		draw_circle(pos, 3.5, Color("39769b"))
		return
	draw_circle(pos, 17.0, Color("ffe2a0") if kind == game.PICKUP_BOMB_CAPACITY else Color("d9c6f6"))
	draw_circle(pos, 12.0, Color("fff5d5") if kind == game.PICKUP_BOMB_CAPACITY else Color("f3e9ff"))
	if kind == game.PICKUP_BOMB_CAPACITY:
		draw_line(pos + Vector2(-7, 0), pos + Vector2(7, 0), Color("aa714f"), 4.0, true)
		draw_line(pos + Vector2(0, -7), pos + Vector2(0, 7), Color("aa714f"), 4.0, true)
	else:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(-8, 3), pos + Vector2(0, -7), pos + Vector2(8, 3), pos + Vector2(3, 3), pos + Vector2(3, 8), pos + Vector2(-3, 8), pos + Vector2(-3, 3)]), Color("9d72c9"))


func draw_flame(pos: Vector2, owners: Array) -> void:
	var rect := Rect2(pos - Vector2(23, 23), Vector2(46, 46))
	if owners.size() == 1:
		var color: Color = Color("f5a655") if owners[0] == -1 else COLORS[owners[0]]
		rounded_box(rect, color.darkened(0.18), 16.0)
		draw_circle(pos, 18.0, color)
		draw_circle(pos, 10.0, color.lightened(0.45))
	else:
		rounded_box(rect, Color("fff2d6"), 16.0)
		var offsets := [Vector2(-11, -10), Vector2(11, -10), Vector2(-11, 10), Vector2(11, 10), Vector2(0, -12), Vector2(0, 12), Vector2.ZERO]
		for index in range(owners.size()):
			var color: Color = Color("f5a655") if owners[index] == -1 else COLORS[owners[index]]
			draw_circle(pos + offsets[index], 12.0, color)
			draw_circle(pos + offsets[index], 5.0, color.lightened(0.45))


func draw_bomb(pos: Vector2, fuse: float) -> void:
	var pulse := 1.0 + 0.07 * sin(Time.get_ticks_msec() * 0.013)
	draw_circle(pos + Vector2(0, 5), 18.0, Color("c0c6ce"))
	draw_circle(pos, 17.0 * pulse, Color("49475f"))
	draw_circle(pos + Vector2(-6, -6), 5.0, Color("77758c"))
	draw_line(pos + Vector2(9, -12), pos + Vector2(14, -20), Color("f7d292"), 3.0, true)
	draw_circle(pos + Vector2(15, -21), 4.0 if fuse > 0.6 else 5.5, Color("ffae69"))


func draw_duck(pos: Vector2, player_index: int, angle: float = 0.0, phase: float = 0.0, canvas: CanvasItem = self) -> void:
	var color: Color = COLORS[player_index]
	canvas.draw_circle(pos + Vector2(0, 8), 18.0, Color("78978a55"))
	var bounce := -absf(sin(phase)) * 2.5
	var wing_spread := absf(sin(phase)) * 2.0
	canvas.draw_set_transform(pos + Vector2(0, bounce), angle, Vector2.ONE)
	canvas.draw_circle(Vector2(-13 - wing_spread, 1), 8.0, color.darkened(0.12))
	canvas.draw_circle(Vector2(13 + wing_spread, 1), 8.0, color.darkened(0.12))
	canvas.draw_circle(Vector2.ZERO, 17.0, color)
	canvas.draw_circle(Vector2(-7, -5), 6.0, color.lightened(0.35))
	canvas.draw_circle(Vector2(-5, -4), 2.5, Color("403d57"))
	canvas.draw_circle(Vector2(6, -4), 2.5, Color("403d57"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-5, 3), Vector2(5, 3), Vector2(0, 10)]), Color("ffca79"))
	canvas.draw_circle(Vector2(-11, 4), 2.5, Color("f9a8a0"))
	canvas.draw_circle(Vector2(11, 4), 2.5, Color("f9a8a0"))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


