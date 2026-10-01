extends RefCounted
## A detached projection of known events; it never reads or mutates a live game.

const Rules = preload("res://scripts/arena_game.gd")
const QUANTUM := 0.05
const MARGIN := 0.20
const MAX_HORIZON := 6.0
const EPS := 0.000001
const INVALID_TILE := Vector2i(-1, -1)


static func forecast(observation: Dictionary, candidate: Dictionary = {}) -> Dictionary:
	var result := {"horizon": 0.0, "complete": false, "danger_intervals": {},
		"blocked_intervals": {}, "solid_intervals": {}, "bomb_intervals": {},
		"egress_tile": INVALID_TILE, "candidate": not candidate.is_empty()}
	if observation.is_empty():
		return result
	var board: Array = observation.board.duplicate(true)
	var bombs: Array = observation.bombs.duplicate(true)
	var hazards: Array = observation.hazards.duplicate(true)
	if not candidate.is_empty():
		bombs.append(candidate.duplicate(true))
		if candidate.owner == observation.self_slot and candidate.tile == observation.self.tile:
			result.egress_tile = candidate.tile
	if result.egress_tile == INVALID_TILE:
		result.egress_tile = observation.self.safe_bomb
	var latest := 0.0
	var moving_count := 0
	for bomb in bombs:
		latest = maxf(latest, bomb.time)
		bomb.since = 0.0
		if bomb.get("kick_direction", Vector2i.ZERO) != Vector2i.ZERO and not bomb.get("danger", false):
			moving_count += 1
	for hazard in hazards:
		latest = maxf(latest, hazard.time)
	for flame in observation.flames:
		add_interval(result.danger_intervals, flame.tile, 0.0, maxf(0.0, flame.time))
		latest = maxf(latest, flame.time - Rules.FLAME_TIME)
	var needed := latest + Rules.FLAME_TIME + MARGIN
	result.horizon = minf(MAX_HORIZON, needed)
	result.complete = needed <= MAX_HORIZON + EPS
	for y in range(board.size()):
		for x in range(board[y].size()):
			var tile := Vector2i(x, y)
			if board[y][x] != Rules.OPEN or observation.terrain[y][x] == -1:
				add_interval(result.solid_intervals, tile, 0.0, INF)
			if board[y][x] == -1:
				board[y][x] = Rules.WALL
	var time := 0.0
	# The engine stops motion as soon as the next tile is blocked, even before
	# enough kick progress has accrued to cross a tile boundary.
	advance_bombs(result, board, bombs, 0.0, 0.0)
	while true:
		# Moving bombs update before hazards, which update before natural fuses.
		for hazard in hazards.duplicate():
			if hazard.time > time + EPS:
				continue
			hazards.erase(hazard)
			if hazard.kind in ["flood", "closing_walls"]:
				for tile in hazard.tiles:
					board[tile.y][tile.x] = Rules.DEEP_WATER if hazard.kind == "flood" else Rules.WALL
					add_interval(result.solid_intervals, tile, time, INF)
					for bomb in bombs.duplicate():
						if bomb.tile == tile:
							finish_bomb(result, bombs, bomb, time)
			else:
				var triggered: Array = []
				for tile in hazard.tiles:
					add_interval(result.danger_intervals, tile, time, time + Rules.FLAME_TIME)
					if board[tile.y][tile.x] == Rules.CRATE:
						clear_crate(result, board, tile, time)
					trigger_at(bombs, tile, triggered)
				# Hazard-triggered explosions have their own crate snapshot, as in resolve_hazard.
				explode_batch(result, board, bombs, triggered, time)
		var due: Array = []
		for bomb in bombs:
			if bomb.time <= time + EPS:
				due.append(bomb)
		explode_batch(result, board, bombs, due, time)
		if time >= result.horizon - EPS:
			break
		var next_time: float = result.horizon
		for bomb in bombs:
			next_time = minf(next_time, bomb.time)
			if bomb.get("kick_direction", Vector2i.ZERO) != Vector2i.ZERO and not bomb.get("danger", false):
				next_time = minf(next_time, time + (1.0 - bomb.get("kick_progress", 0.0)) / Rules.KICK_TILES_PER_SECOND)
		for hazard in hazards:
			next_time = minf(next_time, maxf(time, hazard.time))
		advance_bombs(result, board, bombs, time, next_time)
		time = next_time
	for bomb in bombs:
		add_interval(result.bomb_intervals, bomb.tile, bomb.since, INF)
	for source in [result.solid_intervals, result.bomb_intervals]:
		for tile in source:
			for span in source[tile]:
				add_interval(result.blocked_intervals, tile, span[0], span[1])
	# Completeness follows resolved events, not original fuses: a guaranteed
	# early chain or flood can remove a bomb whose original fuse exceeded the cap.
	var resolved_end := Rules.FLAME_TIME
	for spans in result.danger_intervals.values():
		for span in spans:
			resolved_end = maxf(resolved_end, span[1])
	for spans in result.solid_intervals.values():
		for span in spans:
			if span[1] == INF:
				resolved_end = maxf(resolved_end, span[0] + Rules.FLAME_TIME)
	needed = resolved_end + MARGIN
	# ArenaGame advances each bomb for the whole engine slice before the next
	# bomb. Interacting movers can therefore end on different tiles for different
	# future slice sizes, which are not part of a fair observation. Refuse proof.
	result.complete = moving_count <= 1 and bombs.is_empty() and hazards.is_empty() and needed <= MAX_HORIZON + EPS
	result.horizon = minf(MAX_HORIZON, needed) if result.complete else MAX_HORIZON
	return result


static func add_interval(intervals: Dictionary, tile: Vector2i, start: float, end: float) -> void:
	if end < start:
		return
	if not intervals.has(tile):
		intervals[tile] = []
	var span := [start, end]
	if not intervals[tile].has(span):
		intervals[tile].append(span)


static func clear_crate(result: Dictionary, board: Array, tile: Vector2i, time: float) -> void:
	board[tile.y][tile.x] = Rules.OPEN
	for span in result.solid_intervals.get(tile, []):
		if span[1] == INF:
			span[1] = time


static func finish_bomb(result: Dictionary, bombs: Array, bomb: Dictionary, time: float) -> void:
	add_interval(result.bomb_intervals, bomb.tile, bomb.since, time)
	bombs.erase(bomb)


static func trigger_at(bombs: Array, tile: Vector2i, queue: Array) -> void:
	for bomb in bombs:
		if bomb.tile == tile and not bomb.get("danger", false) and not queue.has(bomb):
			queue.append(bomb)


static func explode_batch(result: Dictionary, board: Array, bombs: Array, queue: Array, time: float) -> void:
	if queue.is_empty():
		return
	var crates := {}
	for y in range(board.size()):
		for x in range(board[y].size()):
			if board[y][x] == Rules.CRATE:
				crates[Vector2i(x, y)] = true
	while not queue.is_empty():
		var bomb: Dictionary = queue.pop_front()
		if not bombs.has(bomb):
			continue
		finish_bomb(result, bombs, bomb, time)
		var danger: bool = bomb.get("danger", false)
		# A remembered bomb with a negative fuse has already spent part of its flame lifetime.
		var end := time + Rules.FLAME_TIME + minf(0.0, bomb.time)
		for tile in Rules.blast_tiles(board, bomb.tile, bomb.range, danger, crates):
			add_interval(result.danger_intervals, tile, time, end)
			trigger_at(bombs, tile, queue)
			if board[tile.y][tile.x] == Rules.CRATE and (danger or tile != bomb.tile):
				clear_crate(result, board, tile, time)


static func bomb_motion_blocked(board: Array, bombs: Array, bomb: Dictionary, tile: Vector2i) -> bool:
	if not inside(board, tile) or board[tile.y][tile.x] != Rules.OPEN:
		return true
	for other in bombs:
		if other != bomb and other.tile == tile:
			return true
	return false


static func advance_bombs(result: Dictionary, board: Array, bombs: Array, start: float, end: float) -> void:
	for bomb in bombs:
		var direction: Vector2i = bomb.get("kick_direction", Vector2i.ZERO)
		if direction == Vector2i.ZERO or bomb.get("danger", false):
			continue
		bomb.kick_progress = bomb.get("kick_progress", 0.0) + (end - start) * Rules.KICK_TILES_PER_SECOND
		while bomb.kick_progress >= 1.0 - EPS:
			var tile: Vector2i = bomb.tile + direction
			if bomb_motion_blocked(board, bombs, bomb, tile):
				bomb.kick_direction = Vector2i.ZERO
				bomb.kick_progress = 0.0
				break
			add_interval(result.bomb_intervals, bomb.tile, bomb.since, end)
			bomb.tile = tile
			bomb.since = end
			bomb.kick_progress = maxf(0.0, bomb.kick_progress - 1.0)
		if bomb_motion_blocked(board, bombs, bomb, bomb.tile + direction):
			bomb.kick_direction = Vector2i.ZERO
			bomb.kick_progress = 0.0


static func inside(board: Array, tile: Vector2i) -> bool:
	return tile.y >= 0 and tile.y < board.size() and tile.x >= 0 and tile.x < board[0].size()


static func tile_at(observation: Dictionary, position: Vector2) -> Vector2i:
	var local: Vector2 = (position - observation.geometry.origin) / observation.geometry.cell
	return Vector2i(floori(local.x), floori(local.y))


static func center(observation: Dictionary, tile: Vector2i) -> Vector2:
	return observation.geometry.origin + (Vector2(tile) + Vector2(0.5, 0.5)) * observation.geometry.cell


static func overlaps(intervals: Dictionary, tile: Vector2i, start: float, end: float) -> bool:
	for span in intervals.get(tile, []):
		# Closed intervals deliberately reject equality at an event boundary.
		if span[0] <= end + EPS and span[1] >= start - EPS:
			return true
	return false


static func occupied_tiles(observation: Dictionary, start: Vector2, end: Vector2) -> Array:
	var low := tile_at(observation, start.min(end) - Vector2.ONE * Rules.RADIUS)
	var high := tile_at(observation, start.max(end) + Vector2.ONE * Rules.RADIUS)
	var tiles: Array = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			tiles.append(Vector2i(x, y))
	return tiles


static func safe_segment(observation: Dictionary, projection: Dictionary, start: Vector2, end: Vector2, from: float, to: float, egress: bool) -> bool:
	# Reserve the complete swept collision box for the whole rounded segment.
	# This is intentionally conservative at tile boundaries and never tunnels
	# through a blast or a closure between sampled arrival states.
	for tile in occupied_tiles(observation, start, end):
		if not inside(observation.board, tile) or observation.terrain[tile.y][tile.x] == -1:
			return false
		if overlaps(projection.solid_intervals, tile, from, to) or overlaps(projection.danger_intervals, tile, from, to):
			return false
		if not (egress and tile == projection.egress_tile) and overlaps(projection.bomb_intervals, tile, from, to):
			return false
	return true


static func travel_ticks(observation: Dictionary, start: Vector2, end: Vector2) -> int:
	var distance := start.distance_to(end)
	if distance < EPS:
		return 0
	# ArenaGame samples terrain once per variable engine slice. A water-to-dry
	# crossing can retain water speed for the whole remaining segment, so summing
	# ideal per-terrain durations is not an upper bound. Use the slowest traversed
	# terrain speed for the full cardinal segment, independent of future slices.
	var low := tile_at(observation, start.min(end))
	var high := tile_at(observation, start.max(end))
	var slowest := INF
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var tile := Vector2i(x, y)
			if not inside(observation.terrain, tile) or observation.terrain[y][x] == -1:
				return 121
			slowest = minf(slowest, Rules.movement_speed_for(observation.wall_mode, observation.terrain[y][x], observation.self.speed_bonus))
	return ceili(distance / slowest / QUANTUM - EPS)


static func solid_at(observation: Dictionary, projection: Dictionary, position: Vector2, time: float, egress: bool) -> bool:
	for tile in occupied_tiles(observation, position, position):
		if not inside(observation.board, tile) or observation.terrain[tile.y][tile.x] == -1:
			return true
		if overlaps(projection.solid_intervals, tile, time, time):
			return true
		if not (egress and tile == projection.egress_tile) and overlaps(projection.bomb_intervals, tile, time, time):
			return true
	return false


static func slide_blockage(observation: Dictionary, projection: Dictionary, position: Vector2, start: float, end: float, egress: bool) -> int:
	# A rounded arrival is an upper bound. If a blocker changes during the move,
	# choosing either "slide" or "stop" could certify an impossible escape.
	var uncertain := false
	for tile in occupied_tiles(observation, position, position):
		if not inside(observation.board, tile) or observation.terrain[tile.y][tile.x] == -1:
			return 1
		var sources: Array = [projection.solid_intervals]
		if not (egress and tile == projection.egress_tile):
			sources.append(projection.bomb_intervals)
		for source in sources:
			for span in source.get(tile, []):
				if span[0] <= start + EPS and span[1] >= end - EPS:
					return 1
				if span[0] <= end + EPS and span[1] >= start - EPS:
					uncertain = true
	return -1 if uncertain else 0


static func movement_edge(observation: Dictionary, projection: Dictionary, position: Vector2, target: Vector2, tick: int, egress: bool, already_sliding: bool = false) -> Dictionary:
	var initial_egress := egress
	var next_tick := tick + travel_ticks(observation, position, target)
	if next_tick > 120 or not safe_segment(observation, projection, position, target, tick * QUANTUM, next_tick * QUANTUM, egress):
		return {}
	var tile := tile_at(observation, target)
	egress = egress and occupied_tiles(observation, target, target).has(projection.egress_tile)
	var edge := {"tile": tile, "tick": next_tick, "egress": egress, "tiles": [tile], "ticks": [next_tick]}
	if observation.wall_mode == "frost" and observation.terrain[tile.y][tile.x] == 2 and not already_sliding:
		var direction := Vector2i(int(sign(target.x - position.x)), int(sign(target.y - position.y)))
		var slide_target := center(observation, tile + direction)
		# Ice adds exactly one extra tile when its destination is standable.
		var blockage := slide_blockage(observation, projection, slide_target, tick * QUANTUM, next_tick * QUANTUM, egress)
		if blockage == -1:
			return {}
		if direction != Vector2i.ZERO and blockage == 0:
			var slide := movement_edge(observation, projection, target, slide_target, next_tick, egress, true)
			if slide.is_empty():
				return {}
			# The forced leg starts immediately, not at its rounded intermediate
			# timestamp. Reserve both legs together to cover that timing difference.
			if not safe_segment(observation, projection, position, slide_target, tick * QUANTUM, slide.tick * QUANTUM, initial_egress):
				return {}
			edge.tile = slide.tile
			edge.tick = slide.tick
			edge.egress = slide.egress
			edge.tiles.append_array(slide.tiles)
			edge.ticks.append_array(slide.ticks)
	return edge


static func state_key(tile: Vector2i, tick: int, egress: bool) -> Vector4i:
	return Vector4i(tile.x, tile.y, tick, int(egress))


static func find_route(observation: Dictionary, projection: Dictionary, goal_tiles: Array, max_nodes: int = 8192) -> Dictionary:
	var failure := {"found": false, "tiles": [], "arrival_times": [], "expanded_nodes": 0}
	if observation.is_empty() or not projection.get("complete", false) or max_nodes <= 0 or goal_tiles.is_empty():
		return failure
	# Planting is only proved from a stationary, fresh position.
	if projection.get("candidate", false) and (observation.self.move_target != Vector2.ZERO or observation.self.slide):
		return failure
	var position: Vector2 = observation.self.pos
	var egress: bool = projection.egress_tile != INVALID_TILE and occupied_tiles(observation, position, position).has(projection.egress_tile)
	var root := {"tile": observation.self.tile, "tick": 0, "egress": egress,
		"tiles": [observation.self.tile], "ticks": [0], "parent": -1}
	if observation.self.move_target != Vector2.ZERO:
		var committed := movement_edge(observation, projection, position, observation.self.move_target, 0, egress, observation.self.slide)
		if committed.is_empty():
			return failure
		root.tile = committed.tile
		root.tick = committed.tick
		root.egress = committed.egress
		root.tiles.append_array(committed.tiles)
		root.ticks.append_array(committed.ticks)
		position = center(observation, root.tile)
	elif not safe_segment(observation, projection, position, position, 0.0, 0.0, egress):
		return failure
	# Integer-time buckets implement Dijkstra without sorting the frontier.
	var buckets: Array = []
	for i in range(121):
		buckets.append([])
	var nodes: Array = [root]
	buckets[root.tick].append(0)
	var seen := {state_key(root.tile, root.tick, root.egress): true}
	for tick in range(root.tick, 121):
		for index in buckets[tick]:
			if failure.expanded_nodes >= mini(8192, max_nodes):
				return failure
			failure.expanded_nodes += 1
			var node: Dictionary = nodes[index]
			position = center(observation, node.tile)
			var now := tick * QUANTUM
			if goal_tiles.has(node.tile) and safe_segment(observation, projection, position, position, now, maxf(now, projection.horizon), node.egress):
				return reconstruct(nodes, index, failure.expanded_nodes)
			for direction in Rules.DIRECTIONS + [Vector2i.ZERO]:
				var edge: Dictionary
				if direction == Vector2i.ZERO:
					if tick == 120 or not safe_segment(observation, projection, position, position, now, now + QUANTUM, node.egress):
						continue
					edge = {"tile": node.tile, "tick": tick + 1, "egress": node.egress, "tiles": [node.tile], "ticks": [tick + 1]}
				else:
					var target := center(observation, node.tile + direction)
					# Even a kick-capable duck must not plan to initiate a kick.
					if solid_at(observation, projection, target, now, node.egress):
						continue
					edge = movement_edge(observation, projection, position, target, tick, node.egress)
					if edge.is_empty():
						continue
				var key := state_key(edge.tile, edge.tick, edge.egress)
				if seen.has(key):
					continue
				seen[key] = true
				edge.parent = index
				buckets[edge.tick].append(nodes.size())
				nodes.append(edge)
	return failure


static func reconstruct(nodes: Array, index: int, expanded: int) -> Dictionary:
	var ancestry: Array = []
	while index != -1:
		ancestry.push_front(index)
		index = nodes[index].parent
	var tiles: Array = []
	var times: Array = []
	for ancestor in ancestry:
		tiles.append_array(nodes[ancestor].tiles)
		for tick in nodes[ancestor].ticks:
			times.append(tick * QUANTUM)
	return {"found": true, "tiles": tiles, "arrival_times": times, "expanded_nodes": expanded}
