extends Node2D

const ArenaGame = preload("res://scripts/arena_game.gd")
const ArenaBoard = preload("res://scripts/arena_board.gd")
const COLORS = ArenaBoard.COLORS
const BOARD_REGION = Rect2(142, 82, 676, 572)

var board:
	get:
		return $Board
var background:
	get:
		return $Background

var game = ArenaGame.new()
var previous_drop := [false, false]
var held_directions := [[], []]
var visual_facing := [0.0, 0.0]
var walk_phase := [0.0, 0.0]
var selected_wall_mode := "fixed"
var networked := false
var viewer_slot := -1
var player_names: Array[String] = []
var countdown_text := ""


func _ready() -> void:
	background.draw.connect(_draw_background)
	game.rng.randomize()
	new_round()


func new_round() -> void:
	game.wall_mode = selected_wall_mode
	game.new_round()
	previous_drop.clear()
	held_directions.clear()
	visual_facing.clear()
	walk_phase.clear()
	for i in range(game.players.size()):
		previous_drop.append(false)
		held_directions.append([])
		visual_facing.append(0.0)
		walk_phase.append(0.0)
	present_board()


func _physics_process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and (game.round_over or selected_wall_mode != game.wall_mode):
		new_round()
	if game.round_over:
		return
	var old_positions: Array[Vector2] = []
	var directions := []
	var plant_requests := []
	for i in range(game.players.size()):
		directions.append(Vector2.ZERO)
		plant_requests.append(false)
		old_positions.append(game.players[i].pos)
		if not game.players[i].alive:
			continue
		if not held_directions[i].is_empty():
			directions[i] = held_directions[i].back()
		var drop := i < 2 and Input.is_key_pressed(KEY_SPACE if i == 0 else KEY_ENTER)
		plant_requests[i] = drop and not previous_drop[i]
		previous_drop[i] = drop
	game.step(delta, directions, plant_requests)
	for i in range(game.players.size()):
		visual_facing[i] = lerp_angle(visual_facing[i], game.players[i].facing, minf(1.0, delta * 12.0))
		walk_phase[i] = walk_phase[i] + delta * 18.0 if game.players[i].pos != old_positions[i] else 0.0
	present_board()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	if event.pressed and event.keycode == KEY_M:
		selected_wall_mode = ArenaGame.MAP_MODES[(ArenaGame.MAP_MODES.find(selected_wall_mode) + 1) % ArenaGame.MAP_MODES.size()]
		queue_redraw()
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
		if not game.round_over and game.players[player_index].alive and game.move_targets[player_index] == Vector2.ZERO:
			game.start_move(player_index, direction)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(142, 43), "QACK BLAST", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("403d57"))
	draw_string(font, Vector2(143, 66), "a tiny bomb battle for 2-6", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("867f91"))
	rounded_box(Rect2(704, 24, 114, 38), Color("ffe1a6"), 19.0)
	centered_text("%s  %dP" % ["ONLINE" if networked else "LOCAL", game.players.size()], Vector2(761, 49), 15, Color("73512d"))
	centered_text("%s  %d:%02d" % [ArenaGame.MAP_NAMES[game.wall_mode].to_upper(), int(game.round_elapsed) / 60, int(game.round_elapsed) % 60], Vector2(635, 49), 13, Color("73512d"))
	if game.round_elapsed >= game.SUDDEN_DEATH_START and not game.round_over:
		centered_text("SUDDEN DEATH", Vector2(635, 68), 11, Color("c35162"))
	if shows_next_map():
		centered_text("NEXT: %s" % ArenaGame.MAP_NAMES[selected_wall_mode].to_upper(), Vector2(500, 49), 12, Color("92536b"))
	for i in range(game.players.size()):
		draw_player_card(i)
	rounded_box(Rect2(142, 667, 259, 29), Color("e7f2ed"), 14.0)
	rounded_box(Rect2(416, 667, 402, 29), Color("f9e8ed"), 14.0)
	centered_text("WASD / ARROWS + SPACE / ENTER" if networked else "P1  WASD  +  SPACE", Vector2(271, 687), 12 if networked else 14, Color("366b68"))
	centered_text((spectator_text() if viewer_slot < 0 else "ROOM HOST STARTS NEXT ROUND") if networked else "P2 ARROWS + ENTER  |  M NEXT MAP  R START", Vector2(617, 687), 12, Color("92536b"))
	if networked and not countdown_text.is_empty():
		draw_rect(BOARD_REGION, Color("44395488"))
		rounded_box(Rect2(350, 246, 260, 188), Color("fffaf0"), 25.0)
		centered_text("GET READY" if countdown_text != "GO" else "LET'S PLAY!", Vector2(480, 284), 18, Color("aa8a89"))
		centered_text(countdown_text, Vector2(480, 390), 84, Color("403d57"))
	if game.round_over:
		draw_rect(Rect2(board.transform * game.ORIGIN, Vector2(game.WIDTH, game.HEIGHT) * game.CELL * board.scale), Color("44395488"))
		var large_result: bool = game.players.size() > 4
		var panel_y := 187.0 if large_result else 224.0
		var button_y := 482.0 if large_result else 414.0
		rounded_box(Rect2(273, panel_y + 5, 414, 356 if large_result else 242), Color("b4a5b8"), 25.0)
		rounded_box(Rect2(269, panel_y, 414, 356 if large_result else 242), Color("fffaf0"), 25.0)
		centered_text("ROUND OVER", Vector2(476, panel_y + 38), 16, Color("aa8a89"))
		centered_text("IT'S A DRAW!" if game.result == "DRAW" else round_result_text() + "!", Vector2(476, panel_y + 88), 32, Color("403d57"))
		var ranked := game.score_order()
		for rank in range(ranked.size()):
			var i: int = ranked[rank]
			centered_text("%d. %s    WINS %d    KILLS %d" % [rank + 1, player_label(i), game.scores[i].wins, game.scores[i].kills], Vector2(476, panel_y + 107 + rank * 23), 13, Color("403d57"))
		rounded_box(Rect2(352, button_y, 248, 36), Color("ffe1a6"), 18.0)
		centered_text("RETURN TO ROOM" if networked else "PRESS R TO PLAY AGAIN", Vector2(476, button_y + 24), 16, Color("73512d"))


func rounded_box(rect: Rect2, color: Color, radius: float, canvas: CanvasItem = self) -> void:
	canvas.draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2, rect.size.y)), color)
	canvas.draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2)), color)
	for offset in [Vector2(radius, radius), Vector2(rect.size.x - radius, radius), Vector2(radius, rect.size.y - radius), Vector2(rect.size.x - radius, rect.size.y - radius)]:
		canvas.draw_circle(rect.position + offset, radius, color)


func centered_text(value: String, baseline: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func shows_next_map() -> bool:
	return not networked and selected_wall_mode != game.wall_mode


func player_marker(i: int) -> String:
	return "YOU" if networked and viewer_slot >= 0 and i == viewer_slot else ""


func spectator_text() -> String:
	return "SPECTATING — next round" if networked and viewer_slot < 0 else ""


func player_label(i: int) -> String:
	if networked and i < player_names.size() and not player_names[i].is_empty():
		return player_names[i]
	return "PLAYER %d" % (i + 1)


func round_result_text() -> String:
	if game.result.begins_with("PLAYER ") and game.result.ends_with(" WINS"):
		var slot: int = game.result.trim_prefix("PLAYER ").trim_suffix(" WINS").to_int() - 1
		if slot >= 0 and slot < game.players.size():
			return "%s WINS" % player_label(slot)
	return game.result


func map_colors(mode: String) -> Dictionary:
	return board.map_colors(mode)


func visible_tile(tile: Vector2i) -> bool:
	_sync_board_view()
	return board.visible_tile(tile)


func vision_darkness(point: Vector2) -> float:
	_sync_board_view()
	return board.vision_darkness(point)


func draw_duck(pos: Vector2, player_index: int, angle: float = 0.0, phase: float = 0.0) -> void:
	board.draw_duck(pos, player_index, angle, phase, self)


func _sync_board_view() -> void:
	board.networked = networked
	board.visual_facing = visual_facing
	board.walk_phase = walk_phase
	board.game = game
	board.viewer_slot = viewer_slot
	board.spawn_marker_slot = viewer_slot if networked and viewer_slot >= 0 and viewer_slot < game.players.size() and game.players[viewer_slot].alive and not game.round_over and game.round_elapsed < 2.5 else -1


func present_board(display_state: Dictionary = {}) -> void:
	_sync_board_view()
	board.present(game, display_state, viewer_slot)
	board.fit_to(BOARD_REGION, game.CELL)
	background.queue_redraw()
	queue_redraw()


func _draw_background() -> void:
	var colors := map_colors(game.wall_mode)
	background.draw_rect(Rect2(Vector2.ZERO, Vector2(960, 704)), Color("fff7ed"))
	background.draw_circle(Vector2(30, 35), 104.0, Color("ffe8d9"))
	background.draw_circle(Vector2(934, 678), 140.0, Color("e4f5ed"))
	rounded_box(Rect2(136, 76, 688, 584), colors.frame, 13.0, background)
	rounded_box(Rect2(138, 78, 684, 580), Color("fffdf6"), 11.0, background)


func draw_player_card(i: int) -> void:
	var x := 10.0 if i % 2 == 0 else 830.0
	var compact: bool = game.players.size() > 4
	var y := 82.0 + (i / 2) * 192.0 if compact else (107.0 if i < 2 else 335.0)
	var card_height := 181.0 if compact else 202.0
	var tint: Color = COLORS[i].lightened(0.72)
	rounded_box(Rect2(x, y + 3, 120, card_height), Color("e3d8d5"), 17.0)
	rounded_box(Rect2(x, y, 120, card_height), Color("fffdf7"), 17.0)
	rounded_box(Rect2(x + 8, y + 8, 104, 53 if compact else 65), tint, 12.0)
	draw_duck(Vector2(x + 60, y + (33 if compact else 40)), i)
	var name := player_label(i)
	var name_size := 17
	while ThemeDB.fallback_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > 108.0 and name_size > 9:
		name_size -= 1
	centered_text(name, Vector2(x + 60, y + (84 if compact else 101)), name_size, Color("403d57"))
	centered_text(("YOU · " if not player_marker(i).is_empty() else "") + ("READY!" if game.players[i].alive else "OUT!"), Vector2(x + 60, y + (105 if compact else 122)), 13, Color("5f9b80") if game.players[i].alive else Color("c77c83"))
	centered_text("BOMB %d   FIRE %d" % [game.players[i].bomb_limit, game.players[i].range], Vector2(x + 60, y + (130 if compact else 149)), 12, Color("827b8b"))
	if game.wall_mode == "night":
		centered_text("SIGHT %d" % game.players[i].vision, Vector2(x + 60, y + (148 if compact else 166)), 12, Color("827b8b"))
	elif game.wall_mode == "pond":
		centered_text("SPEED %d%%" % int((1.0 + game.players[i].speed_bonus) * 100), Vector2(x + 60, y + (148 if compact else 166)), 12, Color("827b8b"))
	elif game.wall_mode == "frost":
		centered_text("BOMB KICK %s" % ("ON" if game.players[i].can_kick else "OFF"), Vector2(x + 60, y + (148 if compact else 166)), 12, Color("827b8b"))
	centered_text("WINS %d   KILLS %d" % [game.scores[i].wins, game.scores[i].kills], Vector2(x + 60, y + (166 if compact else 181)), 12, Color("827b8b"))
