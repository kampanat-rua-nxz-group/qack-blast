extends RefCounted
## The AI boundary: only visible public state and caller-owned observation history.

const NightVisibility = preload("res://scripts/night_visibility.gd")
const FLAME_TIME := 0.5


static func capture(game, slot: int, memory: Dictionary) -> Dictionary:
	if slot < 0 or slot >= game.players.size() or not game.players[slot].alive:
		return {}
	var own: Dictionary = game.players[slot]
	var epoch := mini(2, floori(game.round_elapsed / 60.0)) if game.wall_mode == "night" else 0
	if not memory.has("board"):
		memory.board = unknown_grid(game.WIDTH, game.HEIGHT)
		memory.terrain = unknown_grid(game.WIDTH, game.HEIGHT)
		memory.seen_bombs = []
		memory.wall_epoch = epoch
	if epoch != memory.wall_epoch:
		for y in range(1, game.HEIGHT - 1):
			for x in range(1, game.WIDTH - 1):
				memory.board[y][x] = -1
				memory.terrain[y][x] = -1
	for y in range(game.HEIGHT):
		for x in range(game.WIDTH):
			if visible(game, own, game.center(Vector2i(x, y))):
				memory.board[y][x] = game.board[y][x]
				memory.terrain[y][x] = game.terrain[y][x]
	memory.wall_epoch = epoch
	memory.last_elapsed = game.round_elapsed
	var self_state := public_player(own, slot)
	self_state.tile = game.tile_at(own.pos)
	self_state.move_target = game.move_targets[slot]
	self_state.slide = game.slide_active[slot]
	self_state.safe_bomb = own.safe_bomb
	self_state.alive = own.alive
	var opponents: Array = []
	for i in range(game.players.size()):
		if i != slot and game.players[i].alive and visible(game, own, game.players[i].pos):
			opponents.append(public_player(game.players[i], i))
	var seen: Array = []
	for bomb in game.bombs:
		if bomb.get("danger", false) or visible(game, own, game.center(bomb.tile)):
			var copy := fields(bomb, ["tile", "owner", "range", "time", "danger", "kick_direction", "kick_progress"])
			copy.last_observed = game.round_elapsed
			seen.append(copy)
	# Match by observed tile, never authoritative IDs or array indices. Hidden bombs
	# remain at their last seen location; no hidden kick/removal/chain state is read.
	for remembered in memory.seen_bombs:
		var matched := false
		for bomb in seen:
			if bomb.tile == remembered.tile:
				matched = true
				break
		if matched:
			continue
		var remaining: float = remembered.time - (game.round_elapsed - remembered.last_observed)
		if remaining + FLAME_TIME > 0.0:
			seen.append(remembered.duplicate(true))
	memory.seen_bombs = seen.duplicate(true)
	var observed_bombs := seen.duplicate(true)
	for bomb in observed_bombs:
		bomb.time -= game.round_elapsed - bomb.last_observed
	var observed_flames: Array = []
	for flame in game.flames:
		if visible(game, own, game.center(flame.tile)):
			observed_flames.append(fields(flame, ["tile", "owner", "distance", "time", "kind", "source"]))
	var observed_pickups := {}
	for tile in game.pickups:
		if visible(game, own, game.center(tile)):
			observed_pickups[tile] = game.pickups[tile]
	var observed_hazards: Array = []
	for hazard in game.hazards:
		observed_hazards.append(fields(hazard, ["kind", "tiles", "time"]))
	return {"geometry": {"width": game.WIDTH, "height": game.HEIGHT, "cell": game.CELL, "origin": game.ORIGIN},
		"wall_mode": game.wall_mode, "round_elapsed": game.round_elapsed, "round_over": game.round_over,
		"self_slot": slot, "self": self_state, "board": memory.board.duplicate(true),
		"terrain": memory.terrain.duplicate(true), "players": opponents, "bombs": observed_bombs,
		"flames": observed_flames, "pickups": observed_pickups, "hazards": observed_hazards}


static func visible(game, own: Dictionary, position: Vector2) -> bool:
	return game.wall_mode != "night" or NightVisibility.darkness_at(own.pos.distance_to(position), own.vision, game.CELL) < 1.0


static func public_player(player: Dictionary, slot: int) -> Dictionary:
	var result := fields(player, ["pos", "bomb_limit", "range", "vision", "speed_bonus", "can_kick"])
	result.slot = slot
	return result


static func fields(source: Dictionary, keys: Array) -> Dictionary:
	var result := {}
	for key in keys:
		if source.has(key):
			result[key] = source[key]
	return result.duplicate(true)


static func unknown_grid(width: int, height: int) -> Array:
	var result: Array = []
	for y in range(height):
		var row: Array = []
		row.resize(width)
		row.fill(-1)
		result.append(row)
	return result
