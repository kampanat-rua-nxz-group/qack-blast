extends RefCounted

# Only received authority is sampled. Targets reconstruct corners, never predict.
const BUFFER_SECONDS = 0.05
const RESET_GAP = 0.25
const WALK_RADIANS_PER_PIXEL = 18.0 / 188.0

var samples: Array[Dictionary] = []
var round_id := -1
var snapshot_seq := -1
var last_positions: Array = []
var facing: Array = []
var walk_phase: Array = []


func reset() -> void:
	samples.clear()
	round_id = -1
	snapshot_seq = -1
	last_positions.clear()
	facing.clear()
	walk_phase.clear()


func accepts_snapshot(snapshot: Dictionary) -> bool:
	var next_round := int(snapshot.round_id)
	return next_round > round_id or (next_round == round_id and int(snapshot.snapshot_seq) > snapshot_seq)


func push_snapshot(snapshot: Dictionary, received_at: float) -> void:
	if not accepts_snapshot(snapshot):
		return
	var clear_history := int(snapshot.round_id) != round_id
	if not samples.is_empty():
		var previous: Dictionary = samples.back().snapshot
		clear_history = clear_history or received_at - samples.back().received_at > RESET_GAP or float(snapshot.round_elapsed) - float(previous.round_elapsed) > RESET_GAP
		clear_history = clear_history or snapshot.geometry != previous.geometry or snapshot.board != previous.board or snapshot.players.size() != previous.players.size()
		# A newer packet at the same simulation time replaces the sample (results,
		# upgrades, etc.), rather than inventing a zero-duration movement segment.
		if not clear_history and float(snapshot.round_elapsed) == float(previous.round_elapsed):
			samples.pop_back()
	if clear_history:
		reset()
	round_id = int(snapshot.round_id)
	snapshot_seq = int(snapshot.snapshot_seq)
	samples.append({"snapshot": snapshot.duplicate(true), "received_at": received_at})
	while samples.size() > 16:
		samples.pop_front()


func sample(now: float) -> Dictionary:
	if samples.is_empty():
		return {}
	var latest: Dictionary = samples.back().snapshot
	var time := minf(float(latest.round_elapsed), float(latest.round_elapsed) + now - float(samples.back().received_at) - BUFFER_SECONDS)
	var left: Dictionary = samples.front().snapshot
	var right := left
	for entry in samples:
		right = entry.snapshot
		if float(right.round_elapsed) >= time:
			break
		left = right
	var duration := float(right.round_elapsed) - float(left.round_elapsed)
	var weight := clampf((time - float(left.round_elapsed)) / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	var positions: Array[Vector2] = []
	for i in range(latest.players.size()):
		var player: Dictionary = latest.players[i]
		var pos := _vector(player.pos)
		var direction := Vector2.ZERO
		if player.alive and not latest.get("round_over", false):
			var segment := _along_segment(left.players[i], right.players[i], weight)
			pos = segment.pos
			direction = segment.direction
		positions.append(pos)
		if i >= last_positions.size():
			facing.append(float(player.facing))
			walk_phase.append(0.0)
		else:
			var motion: Vector2 = pos - last_positions[i]
			if player.alive and not motion.is_zero_approx():
				facing[i] = (direction if direction != Vector2.ZERO else motion).angle() - PI / 2.0
				walk_phase[i] += motion.length() * WALK_RADIANS_PER_PIXEL
			else:
				walk_phase[i] = 0.0
	last_positions = positions.duplicate()
	return {"round_id": round_id, "positions": positions, "facing": facing.duplicate(), "walk_phase": walk_phase.duplicate()}


func _along_segment(left: Dictionary, right: Dictionary, weight: float) -> Dictionary:
	var start := _vector(left.pos)
	var end := _vector(right.pos)
	if not left.alive or not right.alive:
		return {"pos": end, "direction": Vector2.ZERO}
	var corner := _vector(left.move_target)
	var next_target := _vector(right.move_target)
	var straight := _axis_aligned(start, end)
	# Same-axis reversals still finish the old tile step before turning back.
	var reversal := corner != Vector2.ZERO and next_target != Vector2.ZERO and (corner - start).dot(next_target - end) < 0.0
	if straight and not reversal:
		return {"pos": start.lerp(end, weight), "direction": end - start}
	if corner == Vector2.ZERO:
		if is_equal_approx(next_target.x, end.x):
			corner = Vector2(end.x, start.y)
		elif is_equal_approx(next_target.y, end.y):
			corner = Vector2(start.x, end.y)
		else:
			return {"pos": end, "direction": Vector2.ZERO}
	if not (_axis_aligned(start, corner) and _axis_aligned(corner, end)):
		return {"pos": end, "direction": Vector2.ZERO}
	var first_length := start.distance_to(corner)
	var distance := (first_length + corner.distance_to(end)) * weight
	if distance < first_length:
		return {"pos": start.move_toward(corner, distance), "direction": corner - start}
	return {"pos": corner.move_toward(end, distance - first_length), "direction": end - corner}


func _axis_aligned(a: Vector2, b: Vector2) -> bool:
	return is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)


func _vector(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
