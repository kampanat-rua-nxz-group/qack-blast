extends RefCounted
## Only detached observations enter this controller. Commands use one-tile
## presses with neutral held input so a reaction interval cannot overshoot turns.

const Profiles = preload("res://scripts/bot_profiles.gd")
const Nav = preload("res://scripts/bot_navigation.gd")
const Rules = preload("res://scripts/arena_game.gd")

var _slot := -1
var _profile: Dictionary = {}
var _seed := 0
var _rng := RandomNumberGenerator.new()
var _next := 0.0
var _decisions := 0
var _expanded := 0
var _candidates := 0
var _history: Dictionary = {}
var _escape: Array = []
var _escape_until := 0.0


func configure(slot: int, difficulty: String, seed_value: int) -> bool:
	_profile = Profiles.get_profile(difficulty)
	_slot = slot
	_seed = seed_value
	reset()
	return slot >= 0 and not _profile.is_empty()


func reset() -> void:
	_rng.seed = _seed
	_next = 0.0
	_decisions = 0
	_expanded = 0
	_candidates = 0
	_history.clear()
	_escape.clear()
	_escape_until = 0.0


func diagnostics() -> Dictionary:
	return {"decision_count": _decisions, "expanded_nodes": _expanded,
		"candidate_count": _candidates, "next_decision_in": _next}


func neutral() -> Dictionary:
	return {"direction": Vector2.ZERO, "move_press": Vector2.ZERO, "plant": false}


func advance(delta: float, observation: Dictionary) -> Dictionary:
	var command := neutral()
	if _profile.is_empty() or not valid(observation):
		_escape.clear()
		_history.clear()
		return command
	_next -= maxf(0.0, delta)
	if _next > 0.000001:
		return command
	# Sample once, relative to now: delayed ticks never replay old decisions.
	_next = _rng.randf_range(_profile.interval_min, _profile.interval_max)
	_decisions += 1
	_expanded = 0
	_candidates = 0
	var predicted := opponent_tiles(observation)
	var projection := Nav.forecast(observation)
	if not projection.complete:
		_escape.clear()
		return command
	if observation.self.move_target != Vector2.ZERO or observation.self.slide:
		return command
	if not _escape.is_empty():
		var step: Dictionary = _escape[0]
		if observation.self.tile == step.origin:
			var edge := Nav.movement_edge(observation, projection, observation.self.pos,
				Nav.center(observation, step.origin + step.direction), 0,
				projection.egress_tile != Nav.INVALID_TILE)
			if not edge.is_empty() and edge.tile == step.destination and escape_still_safe(observation, projection):
				_escape.pop_front()
				command.move_press = Vector2(step.direction)
				return command
		_escape.clear()
	if observation.round_elapsed < _escape_until:
		if Nav.safe_segment(observation, projection, observation.self.pos, observation.self.pos,
			0.0, projection.horizon, false):
			return command
	var goals := open_tiles(observation)
	if not Nav.safe_segment(observation, projection, observation.self.pos, observation.self.pos,
		0.0, projection.horizon, projection.egress_tile != Nav.INVALID_TILE):
		var survival := scheduled_escape(observation, projection, goals)
		return begin_route(survival)
	var own_bombs := 0
	for bomb in observation.bombs:
		if bomb.owner == _slot:
			own_bombs += 1
	var best := {}
	var best_score := -INF
	if own_bombs < observation.self.bomb_limit:
		for tile in nearby_candidates(observation):
			_candidates += 1
			var route := route_to(observation, projection, [tile])
			if not route.found:
				continue
			var score := placement_score(observation, tile, predicted, projection)
			if score > best_score and score > 0.0:
				# Future candidates are goals only. Placement is proved again from
				# the actual current tile, never from a hypothetical future duck.
				if tile == observation.self.tile:
					var candidate := {"tile": tile, "owner": _slot,
						"range": observation.self.range, "time": Rules.FUSE}
					var with_bomb := Nav.forecast(observation, candidate)
					var escape := scheduled_escape(observation, with_bomb, goals, _next)
					if not escape.found:
						continue
					best = {"plant": true, "route": escape, "horizon": with_bomb.horizon}
				else:
					best = {"plant": false, "route": route}
				best_score = score
	var pickup_goals: Array = []
	if _profile.candidate_limit > 1:
		for tile in observation.pickups:
			if useful_pickup(observation, observation.pickups[tile]):
				pickup_goals.append(tile)
		if not pickup_goals.is_empty() and (_profile.prediction_seconds == 0.0 or best_score < 1000.0):
			var pickup_route := route_to(observation, projection, pickup_goals)
			if pickup_route.found:
				return begin_route(pickup_route)
	if not best.is_empty():
		if best.plant:
			_escape = best.route.steps.duplicate(true)
			_escape_until = observation.round_elapsed + best.horizon
			command.plant = true
			return command
		return begin_route(best.route)
	var frontier: Array = []
	for tile in goals:
		for direction in Rules.DIRECTIONS:
			var neighbor: Vector2i = tile + direction
			if Nav.inside(observation.board, neighbor) and observation.board[neighbor.y][neighbor.x] == -1:
				frontier.append(tile)
				break
	if not frontier.is_empty():
		return begin_route(route_to(observation, projection, frontier))
	if not goals.is_empty():
		var exploration: Vector2i = goals[_rng.randi_range(0, goals.size() - 1)]
		return begin_route(route_to(observation, projection, [exploration]))
	return command


func valid(o: Dictionary) -> bool:
	return o.has("self") and o.self.get("alive", false) and not o.get("round_over", true) \
		and o.get("self_slot", -1) == _slot and o.has("geometry") and o.has("board") \
		and o.has("terrain") and o.has("bombs") and o.has("hazards") and o.has("players") \
		and o.has("flames") and o.has("pickups")


func open_tiles(o: Dictionary) -> Array:
	var result: Array = []
	for y in range(o.board.size()):
		for x in range(o.board[y].size()):
			if o.board[y][x] == Rules.OPEN and o.terrain[y][x] != -1:
				result.append(Vector2i(x, y))
	return result


func nearby_candidates(o: Dictionary) -> Array:
	var queue: Array = [o.self.tile]
	var seen := {o.self.tile: true}
	var result: Array = []
	while not queue.is_empty() and result.size() < _profile.candidate_limit:
		var tile: Vector2i = queue.pop_front()
		result.append(tile)
		for direction in Rules.DIRECTIONS:
			var next: Vector2i = tile + direction
			if not seen.has(next) and Nav.inside(o.board, next) and o.board[next.y][next.x] == Rules.OPEN and o.terrain[next.y][next.x] != -1:
				seen[next] = true
				queue.append(next)
	return result


func route_to(o: Dictionary, f: Dictionary, goals: Array) -> Dictionary:
	var route := Nav.find_route(o, f, goals)
	_expanded += route.expanded_nodes
	if not route.found or route.tiles.size() < 2:
		return {"found": route.found, "steps": []}
	# A repeated tile is a timed wait. Do not turn it into an early movement.
	if route.tiles[1] == route.tiles[0]:
		return {"found": true, "steps": []}
	return scheduled_escape(o, f, goals)


func begin_route(route: Dictionary) -> Dictionary:
	var command := neutral()
	if route.get("found", false) and not route.steps.is_empty():
		command.move_press = Vector2(route.steps[0].direction)
	return command


func scheduled_escape(o: Dictionary, f: Dictionary, goals: Array, first_delay: float = 0.0) -> Dictionary:
	var failure := {"found": false, "steps": []}
	if not f.complete or o.self.move_target != Vector2.ZERO or o.self.slide:
		return failure
	var egress: bool = f.egress_tile != Nav.INVALID_TILE and Nav.occupied_tiles(o, o.self.pos, o.self.pos).has(f.egress_tile)
	var nodes: Array = [{"tile": o.self.tile, "tick": 0, "egress": egress, "steps": []}]
	var seen := {Vector3i(o.self.tile.x, o.self.tile.y, int(egress)): 0}
	var delay := ceili(_profile.interval_max / Nav.QUANTUM)
	var index := 0
	while index < nodes.size() and index < 8192:
		var node: Dictionary = nodes[index]
		index += 1
		_expanded += 1
		var position: Vector2 = o.self.pos if node.steps.is_empty() else Nav.center(o, node.tile)
		var now: float = node.tick * Nav.QUANTUM
		if goals.has(node.tile) and Nav.safe_segment(o, f, position, position, 0.0, maxf(now, f.horizon), node.egress):
			return {"found": true, "steps": node.steps}
		for direction in Rules.DIRECTIONS:
			var target := Nav.center(o, node.tile + direction)
			if Nav.solid_at(o, f, target, 0.0, node.egress):
				continue
			var start_tick: int = node.tick + (ceili(first_delay / Nav.QUANTUM) if node.steps.is_empty() else delay)
			var edge := Nav.movement_edge(o, f, position, target, start_tick, node.egress)
			if edge.is_empty():
				continue
			# The plant tick waits its already sampled deadline; subsequent
			# voluntary legs can start one maximum reaction interval late.
			# Reserve its complete swept path from time zero to its latest finish:
			# earlier engine arrival/slide timing cannot evade this reservation.
			var finish: int = edge.tick
			if finish > 120 or not Nav.safe_segment(o, f, position, Nav.center(o, edge.tile), 0.0, finish * Nav.QUANTUM, node.egress):
				continue
			var key := Vector3i(edge.tile.x, edge.tile.y, int(edge.egress))
			if seen.has(key) and seen[key] <= finish:
				continue
			seen[key] = finish
			var steps: Array = node.steps.duplicate()
			steps.append({"origin": node.tile, "direction": direction, "destination": edge.tile})
			nodes.append({"tile": edge.tile, "tick": finish, "egress": edge.egress, "steps": steps})
	return failure


func escape_still_safe(o: Dictionary, f: Dictionary) -> bool:
	var position: Vector2 = o.self.pos
	var tick := 0
	var egress: bool = f.egress_tile != Nav.INVALID_TILE and Nav.occupied_tiles(o, position, position).has(f.egress_tile)
	for index in range(_escape.size()):
		var step: Dictionary = _escape[index]
		if Nav.tile_at(o, position) != step.origin:
			return false
		var start: int = tick + (0 if index == 0 else ceili(_profile.interval_max / Nav.QUANTUM))
		var edge := Nav.movement_edge(o, f, position, Nav.center(o, step.origin + step.direction), start, egress)
		if edge.is_empty() or edge.tile != step.destination:
			return false
		var end := Nav.center(o, edge.tile)
		if not Nav.safe_segment(o, f, position, end, 0.0, edge.tick * Nav.QUANTUM, egress):
			return false
		position = end
		tick = edge.tick
		egress = edge.egress
	return Nav.safe_segment(o, f, position, position, 0.0, maxf(tick * Nav.QUANTUM, f.horizon), egress)


func useful_pickup(o: Dictionary, kind: int) -> bool:
	match kind:
		Rules.PICKUP_SPEED:
			return o.self.speed_bonus < Rules.SPEED_BONUS_MAX
		Rules.PICKUP_BOMB_KICK:
			return not o.self.can_kick
	return true


func opponent_tiles(o: Dictionary) -> Array:
	var result: Array = []
	var fresh := {}
	for player in o.players:
		var tile := Nav.tile_at(o, player.pos)
		var candidates: Array = [tile]
		if _profile.prediction_seconds > 0.0 and _history.has(player.slot):
			var previous: Dictionary = _history[player.slot]
			var elapsed: float = o.round_elapsed - previous.time
			var displacement: Vector2 = player.pos - previous.pos
			if elapsed > 0.0 and displacement.length() > 0.01:
				var speed := minf(displacement.length() / elapsed, Rules.SPEED * 1.5)
				var distance := floori(speed * _profile.prediction_seconds / o.geometry.cell)
				var branch: Array = [{"tile": tile, "depth": 0}]
				var visited := {tile: true}
				var index := 0
				while index < branch.size():
					var node: Dictionary = branch[index]
					index += 1
					if node.depth >= distance:
						continue
					for direction in Rules.DIRECTIONS:
						var next: Vector2i = node.tile + direction
						if not visited.has(next) and Nav.inside(o.board, next) and o.board[next.y][next.x] == Rules.OPEN:
							visited[next] = true
							candidates.append(next)
							branch.append({"tile": next, "depth": node.depth + 1})
		result.append(candidates)
		fresh[player.slot] = {"pos": player.pos, "time": o.round_elapsed}
	_history = fresh
	return result


func placement_score(o: Dictionary, tile: Vector2i, predicted: Array, baseline: Dictionary = {}) -> float:
	var crate_tiles := {}
	var visible_board: Array = o.board.duplicate(true)
	for y in range(o.board.size()):
		for x in range(o.board[y].size()):
			if o.board[y][x] == Rules.CRATE:
				crate_tiles[Vector2i(x, y)] = true
			elif o.board[y][x] == -1:
				visible_board[y][x] = Rules.WALL
	var blast := Rules.blast_tiles(visible_board, tile, o.self.range, false, crate_tiles)
	var crates := 0
	for hit in blast:
		if o.board[hit.y][hit.x] == Rules.CRATE:
			crates += 1
	var attack := 0.0
	var combined := {}
	if _profile.prediction_seconds > 0.0:
		if baseline.is_empty():
			baseline = Nav.forecast(o)
		combined = Nav.forecast(o, {"tile": tile, "owner": _slot, "range": o.self.range, "time": Rules.FUSE})
	for positions in predicted:
		for opponent in positions:
			if _profile.prediction_seconds == 0.0:
				if blast.has(opponent):
					attack += 1
			else:
				# Count pressure on every legal predicted exit, including visible
				# bombs' rays. Existing bombs therefore affect successive tactics.
				var exits: Array = [opponent]
				for direction in Rules.DIRECTIONS:
					var exit: Vector2i = opponent + direction
					if Nav.inside(o.board, exit) and o.board[exit.y][exit.x] == Rules.OPEN:
						exits.append(exit)
				var before := 0
				var after := 0
				for exit in exits:
					if Nav.overlaps(baseline.danger_intervals, exit, 0.0, baseline.horizon) or Nav.overlaps(baseline.blocked_intervals, exit, 0.0, baseline.horizon):
						continue
					before += 1
					if not Nav.overlaps(combined.danger_intervals, exit, 0.0, combined.horizon) and not Nav.overlaps(combined.blocked_intervals, exit, 0.0, combined.horizon):
						after += 1
				if before > 0:
					attack += float(before - after) / before * (1.0 + 1.0 / (before + 1))
	var distance: int = absi(tile.x - o.self.tile.x) + absi(tile.y - o.self.tile.y)
	var upgrade := 100.0 if o.pickups.has(tile) and useful_pickup(o, o.pickups[tile]) else 0.0
	return attack * (100000.0 if _profile.prediction_seconds > 0.0 else 10.0) + upgrade + crates - distance * 0.01
