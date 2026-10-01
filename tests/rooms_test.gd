extends SceneTree

var failures := 0


func _initialize() -> void:
	check(load("res://scripts/room_server.gd").new() != null, "WebSocket server script parses")
	if not ResourceLoader.exists("res://scripts/room_registry.gd"):
		check(false, "room registry exists")
		finish()
		return
	var registry = load("res://scripts/room_registry.gd").new()
	registry.rng.seed = 7
	var created: Dictionary = registry.create_room(10, "Duck")
	check(created.ok and created.code.length() == 6, "host receives a six-character room code")
	var code: String = created.code
	check(not registry.join_room(20, "BADCODE", "Duck").ok, "unknown room code is rejected")
	check(registry.join_room(20, code, "Duck").ok, "friend joins with room code")
	check(registry.join_room(30, code, "Duck").ok, "third player joins")
	check(registry.join_room(40, code, "Duck").ok, "fourth player joins")
	check(registry.join_room(50, code, "Duck").ok, "fifth player joins")
	check(registry.join_room(60, code, "Duck").ok, "sixth player joins")
	# Six-player regression remains a supported smaller room.
	var room: Dictionary = registry.rooms[code]
	check(room.people.map(func(person): return person.name) == ["Duck", "Duck#1", "Duck#2", "Duck#3", "Duck#4", "Duck#5"], "duplicate nicknames get distinct suffixes")
	check(not registry.choose_map(20, "random") and registry.choose_map(10, "random"), "only host selects the map")
	check(registry.choose_map(10, "pond") and registry.choose_map(10, "frost"), "host can select both new maps")
	check(not registry.choose_map(10, "unknown"), "unknown maps are rejected")
	check(registry.choose_map(10, "random"), "host can return to random map")
	check(not registry.start_round(20) and registry.start_round(10), "only host can start with two to six players")
	check(registry.room_for_peer(10).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	check(room.phase == "playing" and room.game.player_count == 6 and room.game.wall_mode == "random", "round uses selected map and six players")
	var encoded := JSON.stringify(registry.game_view(room))
	check(JSON.parse_string(encoded).players[0].sliding == false, "slide state survives JSON snapshot round trip")
	room.game.slide_active[0] = true
	room.game.move_targets[0] = room.game.center(Vector2i(2, 1))
	check(JSON.parse_string(JSON.stringify(registry.game_view(room))).players[0].sliding, "active forced slide is transported")
	room.game.slide_active[0] = false
	room.game.move_targets[0] = Vector2.ZERO
	check(JSON.parse_string(encoded).players.size() == 6, "authoritative snapshot can be sent as JSON")
	var danger_bomb := {"tile": Vector2i(3, 3), "owner": -1, "range": 0, "time": 5.0, "danger": true}
	room.game.bombs.append(danger_bomb)
	check(JSON.parse_string(JSON.stringify(registry.game_view(room))).bombs[0].get("danger", false), "snapshot marks neutral danger bombs")
	room.game.bombs.erase(danger_bomb)
	check(not registry.choose_map(10, "fixed"), "map cannot change during a round")
	check(registry.set_input(20, Vector2.RIGHT, true), "participant sends own input")
	registry.tick(0.016)
	check(room.game.bombs.size() == 1 and room.game.bombs[0].owner == 1, "server applies input to the matching player only")
	registry.leave(10)
	check(room.host == room.people[1].id, "host transfers to longest-connected remaining player")
	check(room.people[0].peer == 0 and room.people[0].disconnect_remaining > 0.0, "disconnected avatar waits thirty seconds")
	check(room.directions[0] == Vector2.ZERO, "disconnected avatar stays stationary")
	check(registry.join_room(70, code, "Duck").ok, "new join after disconnect is a spectator")
	check(room.people.back().name == "Duck#6" and room.people.back().slot == -1, "rejoin is a new participant with a new name")
	registry.tick(30.0)
	check(not room.game.players[0].alive, "disconnected avatar is eliminated after thirty seconds")
	check(room.people[0].scores.kills == 0, "disconnect elimination awards no Kill")
	for i in range(room.game.players.size()):
		room.game.players[i].alive = i == 2
	room.game.resolve_round()
	registry.tick(0.0)
	check(room.people[2].scores.wins == 1, "winner score persists on participant record")
	check(not registry.choose_map(30, "frost") and not registry.start_round(30), "guest cannot change map or replay during results")
	check(registry.choose_map(20, "frost"), "new host changes map during results")
	check(registry.start_round(20), "new host starts a rematch")
	check(registry.room_for_peer(20).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	check(room.code == code and room.people.size() == 7 and room.game.wall_mode == "frost", "rematch keeps room and uses chosen map")
	check(room.game.scores[1].wins == 1, "rematch carries the surviving participant's score")
	for peer_id in [20, 30, 40, 50, 60, 70]:
		registry.leave(peer_id)
	check(not registry.rooms.has(code), "room and scores disappear when last peer leaves")
	test_ten_connected_admission()
	test_countdown_freezes_game_clock()
	test_countdown_transitions_once()
	test_countdown_rejects_start_map_and_input()
	test_lineup_departure_cancels_countdown()
	test_late_join_spectates()
	test_same_tick_bomb_blocks_press_and_held_input()
	test_input_press_intent()
	test_expanded_geometry_snapshot()
	test_map_round_snapshots()
	test_snapshot_identity_and_targets()
	test_event_batches_drain_in_order()
	test_final_events_when_entering_results()
	test_event_cursor_late_join_and_reset()
	test_disconnect_expiry_event_and_cause()
	test_room_events_are_bounded()
	finish()


func test_map_round_snapshots() -> void:
	var Registry = load("res://scripts/room_registry.gd")
	for mode in ["fixed", "random", "pond", "frost", "night"]:
		var registry = Registry.new()
		var created: Dictionary = registry.create_room(100, "A")
		registry.join_room(200, created.code, "B")
		check(registry.choose_map(100, mode) and registry.start_round(100), "%s starts through host selection" % mode)
		check(registry.room_for_peer(100).phase == "countdown", "start prepares a countdown")
		registry.tick(3.0)
		var room: Dictionary = registry.rooms[created.code]
		var game = room.game
		var special: int = {"fixed": 0, "random": 3, "pond": 4, "frost": 5, "night": 2}[mode]
		game.pickups[game.tile_at(game.players[0].pos)] = special
		game.round_elapsed = 180.0
		game.schedule_hazards(180.0)
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
		check(snapshot.pickups.any(func(pickup): return pickup.kind == special), "%s special pickup reaches snapshot" % mode)
		check(not snapshot.bombs.is_empty() if mode == "fixed" else not snapshot.hazards.is_empty(), "%s sudden-death warning reaches snapshot" % mode)
		registry.tick(0.0)
		check(room.phase == "playing", "%s round continues with multiple ducks alive" % mode)
		game.players[0].alive = false
		game.resolve_round()
		registry.tick(0.0)
		check(room.phase == "results" and game.result == "PLAYER 2 WINS", "%s resolves after one survivor" % mode)
		check(registry.start_round(100), "%s starts rematch" % mode)
		check(registry.room_for_peer(100).phase == "countdown", "start prepares a countdown")
		registry.tick(3.0)
		room.game.players[0].alive = false
		room.game.players[1].alive = false
		room.game.resolve_round()
		registry.tick(0.0)
		check(room.phase == "results" and room.game.result == "DRAW", "%s draws when last ducks die together" % mode)


func test_same_tick_bomb_blocks_press_and_held_input() -> void:
	for use_press in [false, true]:
		var registry = load("res://scripts/room_registry.gd").new()
		registry.create_room(10, "A")
		var room: Dictionary = registry.room_for_peer(10)
		registry.join_room(20, room.code, "B")
		registry.start_round(10)
		check(registry.room_for_peer(10).phase == "countdown", "start prepares a countdown")
		registry.tick(3.0)
		var game = room.game
		game.board[1][2] = 0
		game.players[1].pos = game.center(Vector2i(2, 1))
		var start: Vector2 = game.players[1].pos
		registry.set_input(10, Vector2.ZERO, true)
		registry.set_input(20, Vector2.ZERO if use_press else Vector2.LEFT, false, Vector2.LEFT if use_press else Vector2.ZERO)
		registry.tick(0.016)
		check(game.bombs.size() == 1 and game.bombs[0].owner == 0, "earlier slot plants bomb in same tick")
		check(game.players[1].pos == start and game.move_targets[1] == Vector2.ZERO, "%s movement blocks bomb planted by earlier slot in same tick" % ("press" if use_press else "held"))


func test_input_press_intent() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	registry.create_room(10, "A")
	var room: Dictionary = registry.room_for_peer(10)
	registry.join_room(20, room.code, "B")
	registry.start_round(10)
	check(registry.room_for_peer(10).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	var game = room.game
	game.board[1][2] = 0
	game.board[1][3] = 0
	var start: Vector2 = game.players[0].pos
	check(not registry.set_input(10, Vector2.RIGHT, true, Vector2(1, 1)), "diagonal press rejects entire input")
	check(not registry.set_input(10, Vector2.RIGHT, true, Vector2(2, 0)), "noncardinal press rejects entire input")
	registry.tick(0.016)
	check(game.players[0].pos == start and game.bombs.is_empty(), "invalid press cannot move or plant")
	check(registry.set_input(10, Vector2.RIGHT, false, Vector2.RIGHT), "cardinal press accepted")
	registry.set_input(10, Vector2.ZERO, false)
	registry.tick(0.016)
	check(game.players[0].pos.x > start.x, "press then release between ticks starts movement from rest")
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "short press produces exactly one tile step")
	registry.set_input(10, Vector2.RIGHT, false)
	registry.tick(0.016)
	registry.set_input(10, Vector2.ZERO, false, Vector2.RIGHT)
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL * 2, 0), "press during movement does not queue another step")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	registry.set_input(10, Vector2.RIGHT, false)
	registry.tick(0.016)
	registry.tick(0.19)
	registry.tick(0.19)
	check(game.players[0].pos == start + Vector2(game.CELL, 0), "expired held input stops after current tile")
	game.players[0].pos = start
	game.move_targets[0] = Vector2.ZERO
	registry.set_input(10, Vector2.UP, false, Vector2.UP)
	registry.set_input(10, Vector2.ZERO, false)
	registry.tick(0.016)
	check(game.players[0].pos == start, "press intent respects wall collision")
	registry.set_input(10, Vector2.RIGHT, false, Vector2.RIGHT)
	registry.leave(10)
	registry.tick(0.016)
	check(game.players[0].pos == start, "disconnect clears pending press before next tick")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Room checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_snapshot_identity_and_targets() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	var created: Dictionary = registry.create_room(1, "A")
	registry.join_room(2, created.code, "B")
	var room: Dictionary = registry.rooms[created.code]
	check(registry.room_view(room).get("round_id", -1) == 0, "lobby has initial round identity")
	registry.start_round(1)
	check(registry.room_for_peer(1).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	room.game.board[1][2] = 0
	registry.set_input(1, Vector2.RIGHT, false)
	registry.tick(0.016)
	var first: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
	check(first.get("round_id", -1) == 1 and registry.room_view(room).get("round_id", -2) == first.get("round_id", -3), "room and game share prepared round identity")
	check(first.players[0].get("move_target", []) == [272.0,160.0], "movement target survives JSON in rule coordinates")
	check(first.players[1].get("move_target", []) == [0.0,0.0], "resting player has JSON safe zero target")
	var second: Dictionary = registry.game_view(room)
	check(second.get("snapshot_seq", 0) > first.get("snapshot_seq", 0), "central snapshot materialization advances sequence")
	room.game.players[0].alive = false
	room.game.resolve_round()
	registry.tick(0.0)
	registry.start_round(1)
	check(registry.room_for_peer(1).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	var rematch: Dictionary = registry.game_view(room)
	check(rematch.get("round_id", 0) == 2, "each rematch increments round identity")
	check(rematch.get("snapshot_seq", 0) > second.get("snapshot_seq", 0), "sequence remains monotonic across rematches")


func test_expanded_geometry_snapshot() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	check(registry.MAX_CONNECTED == 10, "online capacity is ten connected participants")
	var created: Dictionary = registry.create_room(1, "A")
	registry.join_room(2, created.code, "B")
	registry.start_round(1)
	check(registry.room_for_peer(1).phase == "countdown", "start prepares a countdown")
	registry.tick(3.0)
	var room: Dictionary = registry.rooms[created.code]
	for count in range(2, 11):
		room.game.player_count = count
		room.game.new_round()
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
		check(snapshot.geometry.width == room.game.WIDTH and snapshot.geometry.height == room.game.HEIGHT and snapshot.geometry.cell == room.game.CELL and snapshot.geometry.origin == [room.game.ORIGIN.x, room.game.ORIGIN.y], "snapshot carries selected %d-player authoritative geometry" % count)
		check(snapshot.players.size() == count and snapshot.board.size() == snapshot.geometry.height and snapshot.board[0].size() == snapshot.geometry.width, "snapshot arrays match %d-player geometry" % count)


func countdown_registry():
	var registry = load("res://scripts/room_registry.gd").new()
	registry.create_room(10, "A")
	registry.join_room(20, registry.room_for_peer(10).code, "B")
	check(registry.start_round(10), "host prepares first round")
	return registry


func test_countdown_freezes_game_clock() -> void:
	var registry = countdown_registry()
	var room: Dictionary = registry.room_for_peer(10)
	var start: Vector2 = room.game.players[0].pos
	check(room.phase == "countdown" and registry.room_view(room).get("countdown_remaining", -1) == 3.0, "first start exposes three seconds")
	registry.tick(1.0)
	check(room.phase == "countdown" and registry.room_view(room).get("countdown_remaining", -1) == 2.0, "authoritative countdown advances")
	check(room.game.round_elapsed == 0.0 and room.game.players[0].pos == start and room.game.bombs.is_empty(), "countdown freezes clock and rule state")


func test_countdown_transitions_once() -> void:
	var registry = countdown_registry()
	var room: Dictionary = registry.room_for_peer(10)
	var game = room.game
	registry.tick(3.25)
	check(room.phase == "playing" and is_equal_approx(game.round_elapsed, 0.25), "large crossing tick uses only residual gameplay delta")
	registry.tick(0.5)
	check(room.game == game and room.round_id == 1 and is_equal_approx(game.round_elapsed, 0.75), "GO transitions once without rebuilding the round")
	registry.leave(20)
	registry.tick(29.99)
	check(game.players[1].alive, "active disconnect retains avatar before thirty seconds")
	registry.tick(0.02)
	check(not game.players[1].alive and room.phase == "results", "active disconnect grace expires at thirty seconds")


func test_countdown_rejects_start_map_and_input() -> void:
	var registry = countdown_registry()
	var room: Dictionary = registry.room_for_peer(10)
	check(not registry.start_round(10) and not registry.start_round(20), "countdown rejects repeated and guest start")
	check(not registry.choose_map(10, "night"), "countdown locks selected map")
	check(not registry.set_input(10, Vector2.RIGHT, true, Vector2.RIGHT), "countdown ignores held and edge gameplay input")
	registry.tick(3.0)
	check(room.round_id == 1 and room.game.bombs.is_empty() and room.game.round_elapsed == 0.0 and room.directions[0] == Vector2.ZERO and room.move_presses[0] == Vector2.ZERO, "GO clears countdown input without consuming countdown time")
	check(registry.set_input(10, Vector2.ZERO, true), "fresh gameplay input accepted after GO")
	registry.tick(0.016)
	check(room.game.bombs.size() == 1, "fresh bomb press plants after GO")


func test_lineup_departure_cancels_countdown() -> void:
	var registry = countdown_registry()
	var room: Dictionary = registry.room_for_peer(10)
	room.people[1].scores.wins = 2
	room.people[1].scores.kills = 3
	var code: String = room.code
	registry.join_room(30, code, "C")
	registry.leave(10)
	check(room.phase == "lobby" and room.game == null and room.lineup.is_empty() and room.directions.is_empty() and room.plants.is_empty() and room.move_presses.is_empty() and room.input_remaining.is_empty(), "lineup departure clears prepared round and all input buffers")
	check(room.people.all(func(person): return person.slot == -1) and room.host == room.people[1].id, "cancellation resets every slot and transfers host")
	check(room.people[1].scores == {"wins": 2, "kills": 3} and room.wall_mode == "fixed", "cancellation retains scores and selected map")
	check(not registry.room_view(room).get("notice", "").is_empty(), "cancellation explains return to lobby")
	check(registry.start_round(20), "new host starts with fresh connected lineup")
	check(room.lineup == [room.people[1].id, room.people[2].id] and room.round_id == 2 and room.game.scores[0].wins == 2, "fresh lineup excludes departed member and retains score")
	registry.leave(20)
	registry.leave(30)
	check(not registry.rooms.has(code), "last countdown departure deletes empty room")


func test_late_join_spectates() -> void:
	var registry = countdown_registry()
	var room: Dictionary = registry.room_for_peer(10)
	var lineup: Array = room.lineup.duplicate()
	registry.join_room(30, room.code, "C")
	check(room.people.back().slot == -1 and room.lineup == lineup and room.game.players.size() == 2, "countdown join stays outside frozen lineup")
	registry.leave(30)
	check(room.phase == "countdown", "spectator departure preserves countdown")
	registry.join_room(40, room.code, "D")
	registry.tick(3.0)
	check(not registry.set_input(40, Vector2.RIGHT, true), "late join cannot control prepared round")
	room.game.players[0].alive = false
	room.game.resolve_round()
	registry.tick(0.0)
	check(registry.start_round(10) and room.phase == "countdown" and room.game.players.size() == 3 and room.people.back().slot == 2, "rematch countdown includes spectator in fresh lineup")


func event_room():
	var registry = load("res://scripts/room_registry.gd").new()
	var created: Dictionary = registry.create_room(1, "A")
	registry.join_room(2, created.code, "B")
	registry.start_round(1)
	registry.tick(3.0)
	var room: Dictionary = registry.rooms[created.code]
	for y in range(1, room.game.HEIGHT - 1):
		for x in range(1, room.game.WIDTH - 1):
			if room.game.board[y][x] != room.game.WALL:
				room.game.board[y][x] = room.game.OPEN
	registry.take_room_events(room)
	return [registry, room]


func test_event_batches_drain_in_order() -> void:
	var pair = event_room()
	var registry = pair[0]
	var room: Dictionary = pair[1]
	registry.set_input(1, Vector2.ZERO, true)
	registry.tick(0.016)
	registry.set_input(2, Vector2.ZERO, true)
	registry.tick(0.016)
	var batch: Array = registry.take_room_events(room)
	var ids: Array = batch.map(func(event): return event.event_id)
	check(batch.size() == 2 and batch[0].kind == "bomb_placed" and ids == [1, 2], "registry batch keeps ordered event ids")
	check(JSON.parse_string(JSON.stringify(batch))[0].tile == [1.0, 1.0], "batch tiles serialize as JSON arrays")
	check(registry.take_room_events(room).is_empty(), "batch is cleared after dispatch")
	registry.tick(0.016)
	check(registry.take_room_events(room).is_empty(), "quiet tick produces no events")


func test_final_events_when_entering_results() -> void:
	var pair = event_room()
	var registry = pair[0]
	var room: Dictionary = pair[1]
	room.game.players[0].pos = room.game.center(Vector2i(3, 3))
	room.game.bombs = [{"tile": Vector2i(3, 3), "owner": 0, "range": 1, "time": 0.0}]
	registry.tick(0.016)
	check(room.phase == "results", "fatal blast enters results")
	var batch: Array = registry.take_room_events(room)
	var kinds: Array = batch.map(func(event): return event.kind)
	check("bomb_exploded" in kinds and "player_eliminated" in kinds and kinds[-1] == "round_ended", "results tick still carries explosion elimination and round end")
	var view: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
	check(view.players[0].elimination_cause.kind == "own_bomb", "snapshot retains elimination cause without replaying events")
	check(int(view.event_cursor) == batch[-1].event_id, "game view cursor equals last emitted id")
	check(registry.take_room_events(room).is_empty(), "results phase does not resend events")


func test_event_cursor_late_join_and_reset() -> void:
	var pair = event_room()
	var registry = pair[0]
	var room: Dictionary = pair[1]
	registry.set_input(1, Vector2.ZERO, true)
	registry.tick(0.016)
	var cursor: int = registry.game_view(room).event_cursor
	check(cursor == 1 and registry.room_view(room).event_cursor == 1, "room and game views expose current event cursor")
	check(registry.join_room(9, room.code, "Late").ok, "late player joins")
	check(registry.game_view(room).event_cursor == cursor, "late join initializes at the current cursor")
	room.game.players[1].alive = false
	room.game.resolve_round()
	registry.tick(0.016)
	registry.take_room_events(room)
	check(registry.start_round(1), "rematch starts")
	registry.tick(3.0)
	check(room.game.event_counter == 0 and registry.game_view(room).event_cursor == 0 and registry.take_room_events(room).is_empty(), "rematch resets per-round event counter and batch")
	registry.set_input(1, Vector2.ZERO, true)
	registry.tick(0.016)
	check(registry.take_room_events(room)[0].event_id == 1, "new round ids restart at one")


func test_disconnect_expiry_event_and_cause() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	var created: Dictionary = registry.create_room(1, "A")
	registry.join_room(2, created.code, "B")
	registry.join_room(3, created.code, "C")
	registry.start_round(1)
	registry.tick(3.0)
	var room: Dictionary = registry.rooms[created.code]
	registry.take_room_events(room)
	registry.leave(2)
	registry.tick(29.0)
	check(room.game.players[1].alive, "avatar survives grace")
	registry.tick(1.5)
	var out: Array = registry.take_room_events(room).filter(func(event): return event.kind == "player_eliminated" and event.player == 1)
	check(out.size() == 1 and out[0].cause.kind == "disconnect", "disconnect expiry emits one elimination event")
	check(JSON.parse_string(JSON.stringify(registry.game_view(room))).players[1].elimination_cause.kind == "disconnect", "disconnect cause appears in snapshot")
	registry.tick(1.0)
	check(registry.take_room_events(room).filter(func(event): return event.kind == "player_eliminated" and event.player == 1).is_empty(), "disconnect elimination is not repeated")


func test_room_events_are_bounded() -> void:
	var pair = event_room()
	var registry = pair[0]
	var room: Dictionary = pair[1]
	for i in range(2000):
		room.game.emit_event("bomb_placed", {"tile": [1, 1], "owner": 0})
		registry.tick(0.001)
	check(room.events.size() <= registry.MAX_ROOM_EVENTS, "undrained room batch stays bounded")
	var batch: Array = registry.take_room_events(room)
	check(batch[-1].event_id == 2000, "bounded batch keeps the newest events")


func test_ten_connected_admission() -> void:
	var registry = load("res://scripts/room_registry.gd").new()
	var created: Dictionary = registry.create_room(1, "Duck")
	var room: Dictionary = registry.rooms[created.code]
	for peer in range(2, 11):
		check(registry.join_room(peer, created.code, "Duck").ok, "connected participant %d admitted" % peer)
	check(room.people.size() == 10 and room.people[9].name == "Duck#9" and created.code.length() == 6, "ten admissions preserve nickname suffixes and six-character code")
	check(registry.join_room(11, created.code, "Duck") == {"ok": false, "error": "Room is full"}, "eleventh connected participant receives existing full-room error")
	if room.people.size() != 10:
		return
	check(registry.start_round(1), "ten connected ducks enter countdown")
	registry.tick(3.0)
	var identities: Array = room.game.players.map(func(player): return player.avatar_id)
	registry.leave(1)
	check(room.host == room.people[1].id and room.game.players[0].alive, "ten-player host departure transfers host and retains grace avatar")
	check(registry.join_room(11, created.code, "Duck").ok, "offline history frees a connected slot")
	check(room.people.back().slot == -1 and not registry.set_input(11, Vector2.RIGHT, true), "replacement spectates without controlling a duck")
	check(not registry.join_room(12, created.code, "Duck").ok, "spectator consumes tenth connection slot")
	check(room.game.players.size() == 10 and room.game.players.map(func(player): return player.avatar_id) == identities, "replacement preserves ten live visual identities")
	registry.tick(29.99)
	check(room.game.players[0].alive, "ten-player disconnect avatar survives until thirty seconds")
	registry.tick(0.02)
	check(not room.game.players[0].alive and room.people[0].scores.kills == 0, "ten-player grace expires without Kill credit")
	for i in range(10):
		room.game.players[i].alive = i == 9
	room.game.resolve_round()
	registry.tick(0.0)
	check(room.phase == "results" and room.people[9].scores.wins == 1, "tenth duck reaches results with persisted Win")
	check(registry.start_round(2) and room.game.players.size() == 10, "replacement joins ten-duck rematch")
	check(room.people[9].slot == 8 and room.game.scores[8].wins == 1 and room.game.players[8].avatar_id == identities[9], "slot change preserves tenth player's identity and score")
	registry.leave(2)
	check(room.phase == "lobby" and room.host == room.people[2].id and room.game == null, "ten-player countdown departure cancels and transfers host")
