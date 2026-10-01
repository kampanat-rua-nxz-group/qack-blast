extends SceneTree

const Registry = preload("res://scripts/room_registry.gd")
const Online = preload("res://scenes/online.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var app = Online.instantiate()
	root.add_child(app)
	app.set_process(false)
	app.client.set_process(false)
	var registry = Registry.new()
	var made = registry.create_room(1, "Duck")
	for peer in range(2, 11):
		registry.join_room(peer, made.code, "Duck")
	registry.start_round(1)
	var room = registry.rooms[made.code]
	var snapshot = registry.game_view(room)
	app._game_changed(snapshot)
	test_malformed_snapshot_geometry(app, snapshot)
	test_malformed_transport_keeps_last_good_state(app, registry, room, snapshot)
	test_portable_map_marker(app)
	test_profiles_complete_room_flow()
	app.queue_free()
	await process_frame
	print("Ten-player acceptance checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_malformed_snapshot_geometry(app, snapshot: Dictionary) -> void:
	var valid_width = app.arena.game.WIDTH
	var sequence = app.presentation.snapshot_seq
	var variants: Array = []
	for geometry in [null, [], {}, {"width": 19}]:
		var malformed = snapshot.duplicate(true)
		malformed.geometry = geometry
		variants.append(malformed)
	var bad = snapshot.duplicate(true)
	bad.geometry.width = 20
	variants.append(bad)
	bad = snapshot.duplicate(true)
	bad.geometry.cell = 45
	variants.append(bad)
	bad = snapshot.duplicate(true)
	bad.board[0] = []
	variants.append(bad)
	bad = snapshot.duplicate(true)
	bad.terrain = [[]]
	variants.append(bad)
	bad = snapshot.duplicate(true)
	bad.geometry.origin = [0]
	variants.append(bad)
	for field in ["width", "height", "cell"]:
		for value in [NAN, INF, -INF, 19.5]:
			bad = snapshot.duplicate(true)
			bad.geometry[field] = value
			variants.append(bad)
	for value in [NAN, INF, -INF]:
		bad = snapshot.duplicate(true)
		bad.geometry.origin = [value, 0]
		variants.append(bad)
		bad = snapshot.duplicate(true)
		bad.board[0][0] = value
		variants.append(bad)
	for invalid in variants:
		invalid.snapshot_seq = sequence + 1
		app._game_changed(invalid)
		check(app.arena.game.WIDTH == valid_width and app.presentation.snapshot_seq == sequence, "malformed geometry leaves last good authority and presentation intact")


func test_malformed_transport_keeps_last_good_state(app, registry, room: Dictionary, snapshot: Dictionary) -> void:
	app.client.accept(registry.room_view(room))
	app.client.accept(snapshot)
	var before: int = app.client.game.snapshot_seq
	var malformed := snapshot.duplicate(true)
	malformed.snapshot_seq = before + 1
	malformed.geometry.origin = [0]
	app.client.accept(malformed)
	check(app.client.game.snapshot_seq == before, "transport rejects malformed authority before storing its sequence")
	var valid := snapshot.duplicate(true)
	valid.snapshot_seq = before + 1
	app.client.accept(valid)
	check(app.client.game.snapshot_seq == before + 1, "valid replacement with same sequence recovers after malformed transport")
	malformed.round_id = int(snapshot.round_id) + 1
	malformed.snapshot_seq = 1
	app.client.accept(malformed)
	var next_room: Dictionary = registry.room_view(room)
	next_room.round_id = malformed.round_id
	app.client.accept(next_room)
	check(not app.arena.visible and app.status_label.text == "Preparing the next round…", "future malformed snapshot cannot leave the previous arena visible")
	valid = snapshot.duplicate(true)
	valid.round_id = malformed.round_id
	valid.snapshot_seq = 1
	app.client.accept(valid)
	check(app.arena.visible and app.arena_round_id == valid.round_id, "next round becomes visible after valid geometry arrives")



func test_portable_map_marker(app) -> void:
	app.map_picker.present("fixed", true)
	check(app.map_picker.map_buttons.fixed.text.ends_with(" [x]"), "selected map uses portable ASCII marker")


func test_profiles_complete_room_flow() -> void:
	for count in [2, 6, 8, 10]:
		for mode in ["fixed", "random", "pond", "frost", "night"]:
			var r = Registry.new()
			var created = r.create_room(1, "Host")
			for peer in range(2, count + 1):
				r.join_room(peer, created.code, "Duck")
			var active = r.rooms[created.code]
			r.choose_map(1, mode)
			check(r.start_round(1) and active.phase == "countdown", "count/map starts frozen countdown")
			r.tick(3.0)
			check(active.phase == "playing" and active.game.players.size() == count, "count/map reaches play")
			for i in range(count):
				active.game.players[i].alive = i == count - 1
			active.game.resolve_round()
			r.tick(0.0)
			check(active.phase == "results" and active.people[count - 1].scores.wins == 1, "count/map reaches results with score")
			check(r.start_round(1) and active.phase == "countdown" and active.game.scores[count - 1].wins == 1, "count/map rematches with score")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
