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
	registry.start_round(10)
	var room: Dictionary = registry.rooms[result.code]
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.arena.visible and not app.lobby.visible, "online scene displays arena during round")
	check(app.arena.game.players.size() == 2 and app.arena.game.board.size() == 11, "scene receives server snapshot")
	check(app.arena.game.tile_at(app.arena.game.players[1].pos) == Vector2i(11, 9), "snapshot restores player positions")
	room.game.players[0].alive = false
	room.game.resolve_round()
	room.phase = "results"
	app.client.accept(registry.room_view(room))
	app.client.accept(registry.game_view(room))
	check(app.lobby.visible and app.status_label.text.contains("PLAYER 2 WINS"), "result returns to lobby with winner")
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Online UI checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
