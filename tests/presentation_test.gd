extends SceneTree

var failures := 0
var Presentation


func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/arena_presentation.gd"):
		check(false, "authoritative presentation interface exists")
		finish()
		return
	Presentation = load("res://scripts/arena_presentation.gd")
	test_active_slide_stall_and_reset()
	test_slide_pose_matches_sampled_position()
	test_interpolation_between_samples()
	test_close_snapshot_does_not_rewind_display()
	test_turn_uses_tile_center()
	test_turn_facing_follows_current_segment()
	test_reversal_uses_tile_center()
	test_duplicate_sample_does_not_restart_walk()
	test_stall_holds_position()
	test_round_change_resets_samples()
	test_death_or_board_change_invalidates_motion()
	finish()


func snapshot(seq: int, elapsed: float, pos: Vector2, target: Vector2 = Vector2.ZERO, round_id: int = 1) -> Dictionary:
	return {"round_id": round_id, "snapshot_seq": seq, "round_elapsed": elapsed, "geometry": {"width": 5, "height": 5, "cell": 48.0, "origin": [0, 0]}, "board": [[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0]], "players": [{"pos": [pos.x, pos.y], "move_target": [target.x, target.y], "alive": true, "facing": -PI/2}]}


func test_interpolation_between_samples() -> void:
	var p = Presentation.new()
	var a := snapshot(1, 1.0, Vector2(72,72), Vector2(120,72))
	var b := snapshot(2, 1.05, Vector2(82,72), Vector2(120,72))
	p.push_snapshot(a, 10.0)
	check(p.sample(10.0).positions[0] == Vector2(72,72), "first sample displays immediately")
	p.push_snapshot(b, 10.05)
	var display: Dictionary = p.sample(10.075)
	check(display.positions[0].is_equal_approx(Vector2(77,72)), "50 ms buffer interpolates halfway between authoritative samples")
	check(is_equal_approx(display.facing[0], -PI/2), "displayed rightward motion faces right")
	check(display.walk_phase[0] > 0.0, "displayed movement animates walking")
	check(a.players[0].pos == [72.0,72.0] and b.players[0].pos == [82.0,72.0], "presentation does not mutate snapshots")
	check(display.round_id == 1, "sample identifies its matching round")


func test_turn_uses_tile_center() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72), Vector2(120,72)), 10.0)
	p.push_snapshot(snapshot(2, 1.1, Vector2(120,82), Vector2(120,120)), 10.1)
	check(p.sample(10.075).positions[0].is_equal_approx(Vector2(115,72)), "turn approaches authoritative tile center without a diagonal")
	check(p.sample(10.1).positions[0].is_equal_approx(Vector2(120,72)), "turn passes exactly through tile center")
	check(p.sample(10.125).positions[0].is_equal_approx(Vector2(120,77)), "turn leaves center along new segment")
	# A snapshot at rest still supplies a center through the next target's axis.
	p.reset()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72)), 10.0)
	p.push_snapshot(snapshot(2, 1.1, Vector2(120,82), Vector2(120,120)), 10.1)
	check(p.sample(10.1).positions[0].is_equal_approx(Vector2(120,72)), "next movement target reconstructs turn when previous target is absent")


func test_duplicate_sample_does_not_restart_walk() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(72,72), Vector2(120,72)), 10.0)
	p.push_snapshot(snapshot(2, 1.05, Vector2(82,72), Vector2(120,72)), 10.05)
	var before: Dictionary = p.sample(10.075)
	p.push_snapshot(snapshot(2, 1.05, Vector2(82,72), Vector2(120,72)), 10.08)
	check(p.sample(10.085).walk_phase[0] > before.walk_phase[0], "duplicate sequence does not restart walking or timing")
	p.push_snapshot(snapshot(1, 0.9, Vector2(20,20)), 10.09)
	check(p.sample(10.1).positions[0] == Vector2(82,72), "stale sequence cannot rewind motion")
	p.push_snapshot(snapshot(3, 1.1, Vector2(82,72)), 10.1)
	p.sample(10.15)
	p.push_snapshot(snapshot(4, 1.15, Vector2(82,72)), 10.15)
	check(p.sample(10.2).walk_phase[0] == 0.0, "stationary repeated snapshots do not create walking")


func test_stall_holds_position() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(72,72), Vector2(120,72)), 10.0)
	p.push_snapshot(snapshot(2, 1.05, Vector2(82,72), Vector2(120,72)), 10.05)
	p.sample(10.1)
	check(p.sample(10.5).positions[0] == Vector2(82,72), "stall holds latest position without extrapolating toward target")
	check(p.sample(10.6).walk_phase[0] == 0.0, "held position stops walking")
	p.push_snapshot(snapshot(3, 1.5, Vector2(120,100), Vector2(120,120)), 10.5)
	check(p.sample(10.5).positions[0] == Vector2(120,100), "gap over 250 ms resumes at fresh authoritative position")


func test_round_change_resets_samples() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(8, 9.0, Vector2(200,72)), 10.0)
	p.push_snapshot(snapshot(9, 0.0, Vector2(72,72), Vector2.ZERO, 2), 10.05)
	check(p.sample(10.05).positions[0] == Vector2(72,72) and p.sample(10.05).round_id == 2, "new round resets history immediately")
	p.push_snapshot(snapshot(10, 9.1, Vector2(210,72)), 10.1)
	check(p.sample(10.1).round_id == 2, "older round with higher sequence is rejected")
	p.reset()
	check(p.sample(10.1).is_empty(), "leave or disconnect can clear all display history")


func test_death_or_board_change_invalidates_motion() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72), Vector2(120,72)), 10.0)
	var next := snapshot(2, 1.05, Vector2(120,72))
	next.players[0].alive = false
	p.push_snapshot(next, 10.05)
	check(p.sample(10.05).positions[0] == Vector2(120,72) and p.sample(10.05).walk_phase[0] == 0.0, "death discards obsolete movement immediately")
	p.reset()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72), Vector2(120,72)), 10.0)
	next = snapshot(2, 1.05, Vector2(120,72))
	next.board[1][2] = 1
	p.push_snapshot(next, 10.05)
	check(p.sample(10.05).positions[0] == Vector2(120,72), "changed board invalidates buffered movement immediately")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Presentation checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_turn_facing_follows_current_segment() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72), Vector2(120,72)), 10.0)
	p.sample(10.0)
	p.push_snapshot(snapshot(2, 1.1, Vector2(120,82), Vector2(120,120)), 10.1)
	p.sample(10.095)
	check(is_zero_approx(p.sample(10.105).facing[0]), "frame crossing corner faces new cardinal segment without diagonal facing")


func test_reversal_uses_tile_center() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(110,72), Vector2(120,72)), 10.0)
	p.push_snapshot(snapshot(2, 1.1, Vector2(115,72), Vector2(72,72)), 10.1)
	check(p.sample(10.1).positions[0].is_equal_approx(Vector2(117.5,72)), "reversal reaches tile center before retracing the segment")


func test_close_snapshot_does_not_rewind_display() -> void:
	var p = Presentation.new()
	p.push_snapshot(snapshot(1, 1.0, Vector2(72,72), Vector2(120,72)), 10.0)
	p.sample(10.0)
	p.push_snapshot(snapshot(2, 1.05, Vector2(82,72), Vector2(120,72)), 10.05)
	var before: Dictionary = p.sample(10.085)
	check(before.positions[0].is_equal_approx(Vector2(79,72)), "regular snapshot samples expected buffered position before command broadcast")
	p.push_snapshot(snapshot(3, 1.06, Vector2(84,72), Vector2(120,72)), 10.09)
	var immediate: Dictionary = p.sample(10.09)
	check(immediate.positions[0].is_equal_approx(Vector2(79,72)), "closely spaced higher sequence cannot rewind displayed position")
	check(is_equal_approx(immediate.facing[0], -PI/2), "closely spaced broadcast preserves displayed cardinal facing")
	check(p.sample(10.13).positions[0].is_equal_approx(Vector2(82,72)), "display resumes forward movement when buffered clock catches up")
	check(p.sample(10.5).positions[0] == Vector2(84,72), "monotonic clock still caps display at received authority")
	p.push_snapshot(snapshot(4, 1.5, Vector2(72,72)), 10.5)
	check(p.sample(10.5).positions[0] == Vector2(72,72), "long gap resets monotonic cursor and displays fresh position immediately")
	p.push_snapshot(snapshot(5, 0.0, Vector2(120,120), Vector2.ZERO, 2), 10.55)
	check(p.sample(10.55).positions[0] == Vector2(120,120), "new round resets monotonic cursor to fresh round timing")


func test_slide_pose_matches_sampled_position() -> void:
	var p = Presentation.new()
	var a := snapshot(1, 1.0, Vector2(110,72), Vector2(120,72))
	var b := snapshot(2, 1.1, Vector2(130,72), Vector2(168,72))
	a.players[0].sliding = false
	b.players[0].sliding = true
	p.push_snapshot(a, 10.0)
	p.push_snapshot(b, 10.1)
	check(not p.sample(10.075).sliding[0], "walking pose before displayed ice center despite newer slide packet")
	check(p.sample(10.125).sliding[0], "glide pose after displayed ice center")
	check(p.sample(10.125).sliding[0], "repeated sample keeps matching slide state")
	var c := snapshot(3, 1.2, Vector2(168,72))
	c.players[0].sliding = false
	p.push_snapshot(c, 10.2)
	check(p.sample(10.2).sliding[0], "delayed sample still glides toward dry-floor endpoint")
	check(not p.sample(10.25).sliding[0], "slide pose ends at displayed dry-floor endpoint")
	check(not p.sample(10.8).sliding[0], "stall at rest cannot manufacture slide movement")
	var dead := snapshot(4, 1.25, Vector2(168,72))
	dead.players[0].alive = false
	dead.players[0].sliding = true
	p.push_snapshot(dead, 10.25)
	check(not p.sample(10.25).sliding[0], "elimination clears sampled slide immediately")


func test_active_slide_stall_and_reset() -> void:
	var p = Presentation.new()
	var a := snapshot(1, 1.0, Vector2(130,72), Vector2(168,72))
	a.players[0].sliding = true
	p.push_snapshot(a, 10.0)
	var stalled: Dictionary = p.sample(10.7)
	check(stalled.positions[0] == Vector2(130,72) and stalled.sliding[0], "mid-slide network stall holds matching received pose without moving")
	p.reset()
	check(p.sample(10.8).is_empty(), "room reset discards active slide presentation")
	p.push_snapshot(a, 10.9)
	var b := snapshot(2, 1.05, Vector2(130,72))
	b.board[1][2] = 1
	b.players[0].sliding = false
	p.push_snapshot(b, 10.95)
	check(not p.sample(10.95).sliding[0], "board-cancelled slide drops buffered pose immediately")
	p.push_snapshot(snapshot(1, 0.0, Vector2(72,72), Vector2.ZERO, 2), 11.0)
	check(not p.sample(11.0).sliding[0], "new round clears previous mid-slide pose")
