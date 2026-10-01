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
	test_ten_player_hud_bounds(app)
	await test_owner_render_smoke(app)
	await test_scrolling_roster(app)
	test_game_arrives_before_room(app)
	test_snapshot_geometry_round_trip(app)
	test_authoritative_display_separation(app)
	test_connection_ui(app)
	test_online_hides_local_next_map(app)
	test_local_player_marker_follows_person_slot(app)
	test_spectator_has_no_player_marker(app)
	test_shared_map_picker(app)
	test_events_are_consumed_and_mute_is_available(app)
	test_slot_nine_online_feedback(app)
	test_room_change_clears_transient_feedback(app)
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
	check(registry.room_for_peer(10).phase == "countdown", "start enters authoritative countdown")
	registry.tick(3.0)
	var room: Dictionary = registry.rooms[result.code]
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.visible and not app.lobby.visible, "online scene displays arena during round")
	check(app.arena.player_label(0) == "Duck" and app.arena.player_label(1) == "Duck#1", "arena cards show joined nicknames by slot")
	check(app.arena.game.players.size() == 2 and app.arena.game.board.size() == 11, "scene receives server snapshot")
	check(app.arena.game.tile_at(app.arena.game.players[1].pos) == Vector2i(11, 9), "snapshot restores player positions")
	check(app.arena.game.wall_mode == "night" and app.arena.game.players[0].vision == 1, "night vision arrives in server snapshot")
	check(app.arena.visible_tile(Vector2i(3, 1)) and not app.arena.within_audio_reach(Vector2i(3, 1)), "online faint region is visible but silent")
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
	check(room.phase == "countdown", "replay enters countdown")
	app.client.accept(registry.room_view(room))
	check(not app.arena.visible and app.lobby.visible and not app.results.visible, "new round prepares without showing previous round arena")
	check(app.status_label.text.contains("Preparing"), "mismatched room and game show preparing state")
	app.client.accept(registry.game_view(room))
	check(app.arena.visible and app.arena.get("countdown_text") == "3", "matching prepared game shows authoritative countdown overlay")
	check(app.map_button.disabled and app.start_button.disabled, "countdown locks host map and start controls")
	registry.tick(1.0)
	app.client.accept(registry.room_view(room))
	check(app.arena.get("countdown_text") == "2", "shared countdown advances from room state")
	registry.tick(1.0)
	app.client.accept(registry.room_view(room))
	check(app.arena.get("countdown_text") == "1", "shared countdown displays final second")
	registry.tick(1.0)
	app.client.accept(registry.room_view(room))
	check(app.arena.get("countdown_text") == "GO", "authoritative playing transition displays GO")
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
	check(registry.room_for_peer(1).phase == "countdown", "start enters authoritative countdown")
	registry.tick(3.0)
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
	app.client.accept(registry.room_view(room))
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
	check(registry.room_for_peer(1).phase == "countdown", "start enters authoritative countdown")
	registry.tick(3.0)
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


func test_game_arrives_before_room(app) -> void:
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "One")
	app.client.accept({"type": "joined", "person_id": created.person_id})
	registry.join_room(2, created.code, "Two")
	registry.start_round(1)
	var room: Dictionary = registry.room_for_peer(1)
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	registry.tick(3.0)
	room.game.players[0].alive = false
	room.game.resolve_round()
	registry.tick(0.0)
	app.client.accept(registry.room_view(room))
	registry.choose_map(1, "pond")
	registry.start_round(1)
	app.client.accept(registry.game_view(room))
	check(not app.arena.visible, "future game snapshot stays hidden until matching room authority")
	app.arena.feedback.unlocked = true
	var before: int = app.arena.feedback.cues.count("pickup")
	app.client.accept({"type": "events", "round_id": room.round_id, "events": [{"event_id": 1, "kind": "pickup_collected", "player": 0, "tile": [1,1], "pickup": 0, "granted": true}]})
	check(app.arena.feedback.cues.count("pickup") == before, "future game event waits for room and matched context")
	app.client.accept(registry.room_view(room))
	check(app.arena.feedback.cues.count("pickup") == before + 1, "future game then event then room presents event once")
	check(app.arena.feedback.notice == "BOMB +1", "queued pickup uses matching viewer identity")
	check(app.arena.visible and app.arena.game.wall_mode == "pond" and app.arena.countdown_text == "3", "room arriving after game applies matching prepared arena before displaying it")
	app.client.accept({"type": "left"})


func test_online_hides_local_next_map(app) -> void:
	check(app.arena.has_method("shows_next_map"), "online exposes next-map visibility")
	if not app.arena.has_method("shows_next_map"):
		return
	app.arena.selected_wall_mode = "pond"
	app.arena.game.wall_mode = "fixed"
	check(not app.arena.shows_next_map(), "online hides local NEXT map")
	app.arena.networked = false
	check(app.arena.shows_next_map(), "local retains M/R next map indication")
	app.arena.networked = true


func test_local_player_marker_follows_person_slot(app) -> void:
	check(app.arena.has_method("player_marker"), "arena provides local identity marker")
	if not app.arena.has_method("player_marker"):
		return
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "Host")
	var joined: Dictionary = registry.join_room(2, created.code, "Guest")
	registry.start_round(1)
	app.client.accept({"type": "joined", "person_id": joined.person_id})
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	app.client.accept(registry.game_view(registry.room_for_peer(1)))
	check(app.arena.player_marker(0).is_empty() and app.arena.player_marker(1) == "YOU", "YOU follows local person slot rather than host slot")
	check(app.arena.board.get("spawn_marker_slot") == 1, "spawn indicator follows local duck")
	registry.tick(3.0)
	registry.room_for_peer(1).game.round_elapsed = 3.0
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	app.client.accept(registry.game_view(registry.room_for_peer(1)))
	check(app.arena.board.get("spawn_marker_slot") == -1, "spawn indicator expires while card identity persists")
	check(app.arena.player_marker(1) == "YOU", "local card remains identified after spawn")
	app.client.accept({"type": "left"})


func test_spectator_has_no_player_marker(app) -> void:
	if not app.arena.has_method("player_marker"):
		check(false, "spectator identity presentation exists")
		return
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "Host")
	registry.join_room(2, created.code, "Guest")
	registry.start_round(1)
	var late: Dictionary = registry.join_room(3, created.code, "Late")
	app.client.accept({"type": "joined", "person_id": late.person_id})
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	app.client.accept(registry.game_view(registry.room_for_peer(1)))
	check(app.arena.viewer_slot == -1 and app.arena.player_marker(0).is_empty() and app.arena.player_marker(1).is_empty(), "spectator has no marker on another duck")
	check(app.arena.spectator_text() == "SPECTATING — next round" and app.arena.board.spawn_marker_slot == -1, "spectator sees next-round label without spawn marker")
	app.client.accept({"type": "left"})


func test_shared_map_picker(app) -> void:
	check(app.get("map_picker") != null, "online owns shared lobby/results picker")
	if app.get("map_picker") == null:
		return
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "Host")
	var guest: Dictionary = registry.join_room(2, created.code, "Guest")
	app.client.accept({"type": "joined", "person_id": guest.person_id})
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	check(not app.map_button.disabled, "guest can open waiting map descriptions")
	app.map_button.pressed.emit()
	check(app.map_picker.visible and not app.map_picker.can_select, "guest waiting picker only inspects")
	app.map_picker.inspect("frost")
	check(app.map_picker.selected_mode == "fixed", "guest inspection preserves authoritative map")
	app.client.person_id = created.person_id
	app._room_changed(app.client.room)
	app.map_picker.inspect("night")
	app.map_picker.select_button.pressed.emit()
	check(app.map_picker.selected_mode == "fixed", "map request does not optimistically select")
	app._show_error("Map rejected")
	check(app.map_picker.selected_mode == "fixed", "rejection leaves selected map authoritative")
	check(app.map_picker.permission_label.text.contains("Map rejected"), "map rejection stays visible inside open picker")
	registry.choose_map(1, "pond")
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	check(app.map_picker.selected_mode == "pond", "room update changes selected indicator")
	registry.start_round(1)
	app.client.accept(registry.room_view(registry.room_for_peer(1)))
	check(not app.map_picker.visible and not app.map_picker.can_select, "countdown closes and locks picker")
	registry.tick(3.0)
	var room: Dictionary = registry.room_for_peer(1)
	room.game.players[0].alive = false
	room.game.resolve_round()
	registry.tick(0.0)
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	app.results.map_button.pressed.emit()
	check(app.map_picker.visible and app.map_picker.selected_mode == "pond" and app.map_picker.can_select, "results opens same authoritative host picker")
	app.client.accept({"type": "left"})
	check(not app.map_picker.visible, "leaving closes picker")


func test_ten_player_hud_bounds(app) -> void:
	check(app.arena.has_method("player_card_rect"), "HUD exposes shared card geometry")
	if not app.arena.has_method("player_card_rect"):
		return
	for count in range(7,11):
		for i in range(count):
			var rect: Rect2 = app.arena.player_card_rect(i,count)
			check(rect.position.y == 82.0 + (i / 2)*112.0 and rect.size.y <= 108.0, "compact rows keep 112 px pitch and 108 px height")
			check(rect.end.y <= 638.0 and rect.position.x >= 0 and rect.end.x <= 960, "seven to ten HUD cards clear footer")
	for count in range(2,7):
		check(app.arena.player_card_rect(0,count).size.y == (181.0 if count > 4 else 202.0), "existing larger HUD preserved")


func test_owner_render_smoke(app) -> void:
	var board = load("res://scripts/arena_board.gd").new()
	root.add_child(board)
	var game = load("res://scripts/arena_game.gd").new()
	game.new_round()
	while game.players.size() < 10:
		game.players.append(game.players[0].duplicate(true))
	for i in range(10):
		game.players[i].avatar_id = 9-i
	board.game = game
	check(board.has_method("owner_color"), "flames use identity-aware bounded owner accents")
	if board.has_method("owner_color"):
		var catalog = load("res://scripts/character_catalog.gd")
		check(board.owner_color(0) == catalog.appearance(9).palette.body, "flame tint follows avatar rather than slot")
		check(board.owner_color(-1) == board.owner_color(99), "neutral and invalid owners use safe lethal tint")
	board.show()
	board.display_state = {}
	for count in range(1,12):
		game.flames.clear()
		for owner in range(count):
			game.flames.append({"tile": Vector2i(3,3), "owner": owner-1, "time": 0.5})
		board.queue_redraw()
		await process_frame
	board.queue_free()


func test_scrolling_roster(app) -> void:
	var people := []
	for i in range(18):
		people.append({"id": i+1,"name": "LongDuckNameNumber%d" % i,"avatar_id": i%10,"slot": -1,"connected": i<10,"wins": 0,"kills": 0})
	app.client.person_id = 1
	app.client.accept({"type": "room","code": "ABCDEF","host": 1,"phase": "lobby","round_id": 100,"wall_mode": "fixed","people": people})
	await process_frame
	await process_frame
	var scroll = app.lobby.find_child("RosterScroll",true,false)
	check(scroll != null, "waiting roster scrolls")
	if scroll != null:
		check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "ten plus offline history overflows inside scroll")
	check(app.leave_button.get_global_rect().end.y <= 634, "long roster keeps room controls above footer")
	check(app.start_button.get_global_rect().end.y < app.leave_button.get_global_rect().position.y, "start remains above leave")
	app.client.accept({"type":"left"})


func start_two_player_round(app, guest_view := true) -> Dictionary:
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "Host")
	var joined: Dictionary = registry.join_room(2, created.code, "Guest")
	registry.start_round(1)
	app.client.accept({"type": "joined", "person_id": joined.person_id if guest_view else created.person_id})
	var room: Dictionary = registry.room_for_peer(1)
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	return {"registry": registry, "room": room}


func test_events_are_consumed_and_mute_is_available(app) -> void:
	var mute = app.find_child("MuteButton", true, false)
	check(mute != null and mute.visible and mute.focus_mode == Control.FOCUS_NONE, "visible mute control that does not take keyboard focus")
	check(app.arena.get("feedback") != null, "arena owns feedback state")
	if app.arena.get("feedback") == null:
		return
	app.arena.feedback.persist = false
	app.arena.feedback.unlocked = true
	var setup := start_two_player_round(app)
	var room: Dictionary = setup.room
	room.game.slide_active[0] = true
	room.game.move_targets[0] = room.game.center(Vector2i(2, 1))
	app.client.accept(setup.registry.game_view(room))
	check(app.arena.game.is_sliding(0) and app.presentation.sample(Time.get_ticks_usec() / 1000000.0).sliding[0], "online slide state reaches authority mirror and sampled pose")
	room.game.players[1].alive = false
	room.game.players[1].elimination_cause = {"kind": "own_bomb", "owner": 1}
	var cue_count: int = app.arena.feedback.cues.size()
	app.client.accept(setup.registry.game_view(room))
	check(app.arena.feedback.personal_cause.contains("own bomb") and app.arena.feedback.cues.size() == cue_count, "dead viewer snapshot restores cause without historical sound")
	room.game.place_bomb(0)
	app.client.accept({"type": "events", "round_id": room.round_id, "events": room.game.take_events()})
	check(app.arena.feedback.cues.has("place"), "events message reaches feedback once room state matches")
	var count: int = app.arena.feedback.cues.size()
	app.client.accept({"type": "events", "round_id": room.round_id, "events": [{"event_id": 1, "kind": "bomb_placed", "tile": [1, 1], "owner": 0, "elapsed": 0.0}]})
	check(app.arena.feedback.cues.size() == count, "client dedupe plus feedback dedupe avoid replay")
	mute.pressed.emit()
	check(app.arena.feedback.muted, "mute button toggles feedback")
	app.client.accept({"type": "events", "round_id": room.round_id, "events": [{"event_id": 50, "kind": "player_eliminated", "player": 1, "tile": [3, 3], "cause": {"kind": "own_bomb", "owner": 1}, "elapsed": 1.0}]})
	check(app.arena.feedback.personal_cause.begins_with("OUT") and app.arena.feedback.cues.size() == count, "muted personal elimination keeps text without sound")
	mute.pressed.emit()
	check(not app.arena.feedback.muted, "mute toggles back")
	app.client.accept({"type": "left"})


func test_room_change_clears_transient_feedback(app) -> void:
	if app.arena.get("feedback") == null:
		check(false, "arena owns feedback state")
		return
	app.arena.feedback.persist = false
	start_two_player_round(app)
	app.client.accept({"type": "events", "round_id": app.client.game.round_id, "events": [{"event_id": 60, "kind": "player_eliminated", "player": 1, "tile": [3, 3], "cause": {"kind": "flood", "owner": -1}, "elapsed": 1.0}]})
	check(not app.arena.feedback.personal_cause.is_empty(), "personal cause set before leaving")
	app.client.accept({"type": "left"})
	check(app.arena.feedback.personal_cause.is_empty() and app.arena.feedback.effects.is_empty() and app.arena.feedback.round_id == -1, "leaving a room clears transient feedback")


func test_slot_nine_online_feedback(app) -> void:
	app.client.accept({"type": "left"})
	var registry = RoomRegistry.new()
	var created: Dictionary = registry.create_room(1, "Duck")
	for peer in range(2, 11):
		registry.join_room(peer, created.code, "Duck")
	var room: Dictionary = registry.rooms[created.code]
	registry.choose_map(1, "night")
	registry.start_round(1)
	app.client.accept({"type": "joined", "person_id": room.people[9].id})
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.viewer_slot == 9 and app.arena.player_marker(9) == "YOU" and app.arena.board.spawn_marker_slot == 9, "tenth local viewer receives countdown identity and marker")
	registry.tick(3.0)
	app.client.accept(registry.room_view(room))
	room.game.slide_active[9] = true
	room.game.move_targets[9] = room.game.center(Vector2i(2, 11))
	app.client.accept(registry.game_view(room))
	check(app.arena.game.is_sliding(9) and app.presentation.sample(Time.get_ticks_usec() / 1000000.0).sliding[9], "slot 9 slide state reaches rule mirror and presentation")
	app.arena.present_board()
	check(app.arena.visible_tile(app.arena.game.tile_at(app.arena.game.players[9].pos)) and not app.arena.visible_tile(app.arena.game.tile_at(app.arena.game.players[0].pos)), "slot 9 Nightfall falloff follows its own authoritative tile")
	app.arena.feedback.persist = false
	app.arena.feedback.unlocked = true
	var before: int = app.arena.feedback.cues.size()
	room.game.place_bomb(9)
	var events: Array = room.game.take_events()
	app.client.accept({"type": "events", "round_id": room.round_id, "events": events})
	check(app.arena.feedback.cues.size() == before + 1 and app.arena.feedback.cues.back() == "place", "slot 9 receives personal bomb placement feedback")
	app.client.accept({"type": "events", "round_id": room.round_id, "events": events})
	check(app.arena.feedback.cues.size() == before + 1, "slot 9 placement event deduplicates")
	room.game.players[9].alive = false
	room.game.players[9].elimination_cause = {"kind": "own_bomb", "owner": 9}
	app.client.accept(registry.game_view(room))
	check(app.arena.feedback.personal_cause.contains("own bomb"), "slot 9 snapshot restores personal elimination cause")
	app.client.accept({"type": "left"})
