extends SceneTree

const RoomClient = preload("res://scripts/room_client.gd")
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
	check(app.lobby.visible and app.status_label.text.contains("Duck#1 WINS"), "result returns to lobby with winner nickname")
	check(app.arena.round_result_text() == "Duck#1 WINS", "arena result shows winner nickname")
	for peer_id in [30, 40, 50, 60]:
		check(registry.join_room(peer_id, result.code, "Duck").ok, "another player joins before six-player rematch")
	check(registry.start_round(10), "host starts six-player rematch")
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.game.board.size() == 13 and app.arena.game.board[0].size() == 15, "six-player snapshot uses enlarged board")
	check(app.arena.game.players.size() == 6 and app.arena.game.tile_at(app.arena.game.players[5].pos) == Vector2i(7, 11), "sixth player reaches client with lower spawn")
	check(app.arena.player_label(5) == "Duck#5", "rematch cards follow the new six-player lineup")
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Online UI checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
