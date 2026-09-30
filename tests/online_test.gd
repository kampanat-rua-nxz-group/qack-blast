extends SceneTree

const RoomClient = preload("res://scripts/room_client.gd")
const Ui = preload("res://scripts/lobby_ui.gd")
const RoomRegistry = preload("res://scripts/room_registry.gd")

var failures := 0


func _initialize() -> void:
	var scene = load("res://scenes/online.tscn")
	check(scene != null, "online scene loads")
	if scene == null:
		finish()
		return
	var app = scene.instantiate()
	root.add_child(app)
	call_deferred("run_checks", app)


func run_checks(app) -> void:
	check(RoomClient.resolve_server_url(PackedStringArray(), "") == "ws://127.0.0.1:9080", "server URL defaults to local server")
	check(RoomClient.resolve_server_url(PackedStringArray(), "", "wss://game.onrender.com") == "wss://game.onrender.com", "web build uses configured public server")
	check(RoomClient.resolve_server_url(PackedStringArray(), "wss://override.example", "wss://game.onrender.com") == "wss://override.example", "query parameter overrides public server")
	check(RoomClient.resolve_server_url(PackedStringArray(["--server=wss://duck.example"]), "") == "wss://duck.example", "server URL reads --server argument")
	check(RoomClient.resolve_server_url(PackedStringArray(["--server=ws://a"]), " wss://b ") == "wss://b", "web server parameter wins")
	check(app.lobby.find_children("*", "LineEdit", true, false).size() == 2, "entry screen hides server URL")
	test_snapshot_geometry_round_trip(app)
	test_authoritative_display_separation(app)
	test_connection_ui(app)
	var registry = RoomRegistry.new()
	var result: Dictionary = registry.create_room(10, "Duck")
	app.client.accept({"type": "joined", "person_id": result.person_id})
	app.client.accept(registry.room_view(registry.rooms[result.code]))
	var waiting = app.lobby.find_child("WaitingCard", true, false)
	check(waiting != null and waiting.visible, "creating a room switches to waiting lobby")
	check(app.room_label.text == result.code, "waiting lobby shows shareable room code")
	check(app.lobby.find_child("CopyCodeButton", true, false) != null, "waiting lobby has copy code button")
	registry.join_room(20, result.code, "Duck")
	var lobby_room: Dictionary = registry.rooms[result.code]
	lobby_room.people[0].scores.wins = 3
	lobby_room.people[1].scores.kills = 2
	app.client.accept(registry.room_view(lobby_room))
	check(app.roster_label.text.contains("Duck") and not app.roster_label.text.contains("Wins") and not app.roster_label.text.contains("Kills"), "waiting roster omits scores")
	check(registry.choose_map(10, "night"), "host can select night map")
	registry.start_round(10)
	var room: Dictionary = registry.rooms[result.code]
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.visible and not app.lobby.visible, "online scene displays arena during round")
	check(app.arena.player_label(0) == "Duck" and app.arena.player_label(1) == "Duck#1", "arena cards show joined nicknames by slot")
	check(app.arena.game.players.size() == 2 and app.arena.game.board.size() == 11, "scene receives server snapshot")
	check(app.arena.game.tile_at(app.arena.game.players[1].pos) == Vector2i(11, 9), "snapshot restores player positions")
	check(app.arena.game.wall_mode == "night" and app.arena.game.players[0].vision == 1, "night vision arrives in server snapshot")
	check(registry.game_view(room).has("terrain") and registry.game_view(room).players[0].has("speed_bonus"), "terrain and speed upgrade are included in snapshots")
	room.game.terrain[1][1] = 1
	room.game.players[0].speed_bonus = 0.25
	app.client.accept(registry.game_view(room))
	check(app.arena.game.terrain[1][1] == 1 and is_equal_approx(app.arena.game.players[0].speed_bonus, 0.25), "client restores water and speed from snapshot")
	check(registry.game_view(room).players[0].has("can_kick"), "bomb-kick upgrade is included in snapshots")
	room.game.players[0].can_kick = true
	room.game.bombs.append({"tile": Vector2i(4, 4), "owner": 0, "time": 1.0, "kick_direction": Vector2i.RIGHT, "kick_progress": 0.5})
	app.client.accept(registry.game_view(room))
	check(app.arena.game.players[0].can_kick and app.arena.game.bombs.back().kick_direction == Vector2i.RIGHT and is_equal_approx(app.arena.game.bombs.back().kick_progress, 0.5), "client restores moving bomb and kick upgrade")
	room.game.bombs.pop_back()
	check(app.arena.viewer_slot == 0 and not app.arena.visible_tile(Vector2i(11, 9)), "online darkness uses the local player's slot")
	var danger_bomb := {"tile": Vector2i(3, 3), "owner": -1, "range": 0, "time": 5.0, "danger": true}
	room.game.bombs.append(danger_bomb)
	app.client.accept(registry.game_view(room))
	check(app.arena.game.bombs[0].get("danger", false) and app.arena.game.warning_tiles().has(Vector2i(11, 3)), "online warning spans the danger bomb's row")
	if room.game.get("hazards") == null:
		check(false, "online snapshot carries map hazards")
	else:
		room.game.hazards.append({"kind": "random_burst", "tiles": [Vector2i(2, 2)], "time": 5.0})
		app.client.accept(registry.game_view(room))
		check(app.arena.game.hazards.size() == 1 and app.arena.game.warning_tiles().has(Vector2i(2, 2)), "online snapshot restores map hazard warnings")
	room.game.bombs.erase(danger_bomb)
	room.game.players[0].alive = false
	app.client.accept(registry.game_view(room))
	check(app.arena.visible_tile(Vector2i(11, 9)), "eliminated online viewer sees full night map")
	room.game.resolve_round()
	room.phase = "results"
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.results.visible and not app.lobby.visible and not app.arena.visible, "result switches to dedicated screen")
	check(app.results.find_child("Outcome", true, false).text.contains("Duck#1 WINS"), "final snapshot shows winner nickname")
	check(app.results.find_child("RoomCode", true, false).text == result.code, "results retain shareable room code")
	check(app.results.change_map_requested.get_connections().size() == 1 and app.results.play_again_requested.get_connections().size() == 1, "results actions connect to online app")
	check(registry.choose_map(10, "pond"), "host changes map after round")
	app.client.accept(registry.room_view(room))
	check(app.results.find_child("SelectedMap", true, false).text.contains("Lily Pond"), "results update selected map")
	app.client.accept({"type": "error", "message": "Action rejected"})
	check(app.results.find_child("Status", true, false).text == "Action rejected" and app.results.visible, "results show rejected command")
	for peer_id in [30, 40, 50, 60]:
		check(registry.join_room(peer_id, result.code, "Duck").ok, "another player joins before six-player rematch")
	check(registry.start_round(10), "host starts six-player rematch")
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.visible and not app.lobby.visible and not app.results.visible, "rematch goes directly to arena")
	check(app.arena.game.board.size() == 13 and app.arena.game.board[0].size() == 15, "six-player snapshot uses enlarged board")
	check(app.arena.game.players.size() == 6 and app.arena.game.tile_at(app.arena.game.players[5].pos) == Vector2i(7, 11), "sixth player reaches client with lower spawn")
	check(app.arena.player_label(5) == "Duck#5", "rematch cards follow the new six-player lineup")
	app.client.accept({"type": "left"})
	check(app.lobby.visible and not app.arena.visible and not app.results.visible and app.entry_card.visible, "leaving returns to room entry")
	test_rejoin_preserves_code_without_resuming_identity(app)
	finish()


func test_connection_ui(app) -> void:
	app.server_url = "wss://game.example"
	app.request({"type": "create", "name": "Duck"})
	var create = app.get("create_button")
	check(create != null and create.disabled, "busy connection disables duplicate create")
	if create == null:
		return
	check(app.join_button.disabled and app.cancel_button.visible, "busy connection offers cancel and disables join")
	app._connection_actions(app.connection_flow.advance(8.0))
	check(app.status_label.text == "The server may be waking up. This can take about a minute.", "eight-second waking status reaches player UI")
	check(not app.status_label.text.contains("game.example"), "player status hides endpoint")
	app.request({"type": "join", "name": "Duplicate", "code": "ABCDEF"})
	check(app.connection_flow.retry_request.type == "create", "busy UI action cannot replace pending request")
	app._cancel_connection()
	check(not create.disabled and app.pending_request.is_empty(), "cancel restores entry and discards command")
	for public_url in ["wss://game.example", "wss://localhost.example", "wss://127.0.0.1.example", "wss://[::1].example"]:
		check(not Ui.is_loopback_server(public_url), "public lookalike does not receive development hints")
		check(not Ui.connection_text("failed", "connection", false, Ui.is_loopback_server(public_url)).contains("Godot"), "public failure gives player recovery without local hint")
	for local_url in ["ws://127.0.0.1:9080", "ws://localhost:9080", "ws://[::1]:9080"]:
		check(Ui.is_loopback_server(local_url), "actual loopback permits local hint")
	app.server_url = RoomClient.DEFAULT_SERVER_URL


func test_rejoin_preserves_code_without_resuming_identity(app) -> void:
	app.name_field.text = "Remembered Duck"
	app.code_field.text = "ABCDEF"
	app.client.person_id = 55
	app._disconnected()
	check(app.code_field.text == "ABCDEF" and app.name_field.text == "Remembered Duck", "disconnect preserves room code and nickname")
	var rejoin = app.get("rejoin_button")
	check(rejoin != null and rejoin.visible, "disconnect offers explicit rejoin")
	if rejoin == null:
		return
	check(app.client.person_id == 0 and app.client.room.is_empty(), "disconnect clears previous identity")
	check(app.status_label.text.contains("new player") and app.status_label.text.contains("next round"), "rejoin explains new participant and next round")
	app._rejoin_room()
	check(app.connection_flow.retry_request == {"type": "join", "name": "Remembered Duck", "code": "ABCDEF"}, "rejoin sends preserved code without identity credentials")
	app._cancel_connection()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Online UI checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_snapshot_geometry_round_trip(app) -> void:
	var registry = RoomRegistry.new()
	var result: Dictionary = registry.create_room(1, "One")
	registry.join_room(2, result.code, "Two")
	registry.start_round(1)
	var room: Dictionary = registry.rooms[result.code]
	# Deliberately differs from the profile inferred from these two players.
	room.game.player_count = 6
	room.game.new_round()
	room.game.players.resize(2)
	room.game.ORIGIN = Vector2(18, 26)
	room.game.players[0].pos = Vector2(84, 92)
	room.game.players[1].pos = Vector2(612, 532)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(registry.game_view(room)))
	check(snapshot.has("geometry"), "snapshot includes authoritative geometry")
	if not snapshot.has("geometry"):
		return
	check(snapshot.geometry.width == 15 and snapshot.geometry.height == 13 and snapshot.geometry.cell == 44.0 and snapshot.geometry.origin == [18.0, 26.0], "geometry survives a JSON round trip")
	app.client.accept(snapshot)
	check(app.arena.game.WIDTH == 15 and app.arena.game.HEIGHT == 13 and app.arena.game.CELL == 44.0 and app.arena.game.ORIGIN == Vector2(18, 26), "client applies geometry rather than guessing from player count")
	check(app.arena.game.tile_at(app.arena.game.players[0].pos) == Vector2i(1, 1), "snapshot origin and cell restore rule-space coordinates")
	var board = app.arena.get_node_or_null("Board")
	check(board != null, "online arena uses shared board renderer")
	if board != null:
		check((board.transform * app.arena.game.ORIGIN).is_equal_approx(Vector2(150, 82)), "snapshot board is centered in display region")
		check((board.transform * app.arena.game.players[0].pos).is_equal_approx(Vector2(216, 148)), "snapshot duck uses same world-to-display transform as board")
		board.fit_to(Rect2(142, 82, 676, 572), 22.0)
		check(app.arena.game.tile_at(app.arena.game.players[0].pos) == Vector2i(1, 1), "online display scaling preserves snapshot rule coordinates")
	app.client.accept({"type": "left"})


func test_authoritative_display_separation(app) -> void:
	check(app.get("presentation") != null, "online app owns authoritative presentation")
	if app.get("presentation") == null:
		return
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "A")
	registry.join_room(2, created.code, "B")
	registry.choose_map(1, "night")
	registry.start_round(1)
	var room: Dictionary = registry.rooms[created.code]
	room.game.board[1][2] = 0
	app.client.accept({"type": "joined", "person_id": created.person_id})
	app.client.accept(registry.room_view(room))
	var a: Dictionary = registry.game_view(room)
	room.game.players[0].pos += Vector2(10,0)
	room.game.move_targets[0] = Vector2(272,160)
	room.game.round_elapsed = 0.05
	var b: Dictionary = registry.game_view(room)
	app.client.accept(a)
	app.client.accept(b)
	app.presentation.reset()
	app.presentation.push_snapshot(a, 10.0)
	app.presentation.push_snapshot(b, 10.05)
	app.arena.present_board(app.presentation.sample(10.075))
	var board = app.arena.board
	check(board.player_position(0).is_equal_approx(Vector2(225,160)), "shared board draws halfway displayed duck")
	check(app.arena.game.players[0].pos == Vector2(230,160) and app.arena.game.board == b.board, "display interpolation leaves authoritative position and board unchanged")
	check(is_zero_approx(board.vision_darkness(Vector2(152.2,160))), "Nightfall original clear radius follows displayed duck")
	check(board.vision_darkness(Vector2(147,160)) > 0.0, "existing Nightfall falloff starts outside displayed clear radius")
	var old := a.duplicate(true)
	old.players[0].pos = [100,100]
	app.client.accept(old)
	check(app.arena.game.players[0].pos == Vector2(230,160) and app.client.game.players[0].pos == b.players[0].pos, "stale packets cannot rewind client or arena authority")
	app.client.accept({"type": "left"})
	check(app.presentation.sample(10.1).is_empty(), "leaving clears presentation history")
	app.presentation.push_snapshot(a, 10.0)
	app._disconnected()
	check(app.presentation.sample(10.1).is_empty(), "disconnect clears presentation history")
