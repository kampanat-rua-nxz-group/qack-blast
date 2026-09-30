extends SceneTree

var failures := 0
const InputIntent = preload("res://scripts/player_input.gd")


class RecordingClient extends "res://scripts/room_client.gd":
	var messages: Array = []

	func send(message: Dictionary) -> void:
		messages.append(message)


func _initialize() -> void:
	test_latest_held_key_wins()
	test_alias_release_keeps_other_key()
	test_repeat_does_not_reorder()
	test_bomb_press_is_consumed_once()
	test_focus_loss_resets_input()
	var app = load("res://scenes/online.tscn").instantiate()
	root.add_child(app)
	call_deferred("test_online_input_lifecycle", app)


func test_online_input_lifecycle(app) -> void:
	var recording = RecordingClient.new()
	app.client = recording
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	app.name_field.grab_focus()
	app._input(key)
	check(recording.messages.is_empty(), "nickname typing produces no gameplay commands")
	var registry = load("res://scripts/room_registry.gd").new()
	var joined: Dictionary = registry.create_room(10, "A")
	registry.join_room(20, joined.code, "B")
	registry.start_round(10)
	recording.person_id = joined.person_id
	recording.room = registry.room_view(registry.room_for_peer(10))
	app._room_changed(recording.room)
	app._input(key)
	check(recording.messages.size() == 1 and recording.messages[0].direction == [0.0, -1.0] and recording.messages[0].move_press == [0.0, -1.0], "direction press sends immediate held direction and edge")
	key.echo = true
	app._input(key)
	check(recording.messages.size() == 1, "repeat sends no immediate command")
	key.echo = false
	key.pressed = false
	app._input(key)
	check(recording.messages.size() == 2 and recording.messages[1].direction == [0.0, 0.0], "release sends immediate neutral command")
	app._physics_process(1.0 / 30.0)
	check(recording.messages.size() == 3 and recording.messages[2].direction == [0.0, 0.0] and not recording.messages[2].plant, "30 Hz heartbeat sends consumed neutral input")
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	app._input(key)
	check(recording.messages.size() == 4 and recording.messages[3].plant, "bomb press sends immediately")
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	app._input(key)
	app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(recording.messages.back().direction == [0.0, 0.0] and not recording.messages.back().plant, "focus loss sends neutral input")
	var count: int = recording.messages.size()
	app._input(key)
	app._physics_process(1.0 / 30.0)
	check(recording.messages.size() == count, "unfocused app sends no new movement")
	app._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	app._physics_process(1.0 / 30.0)
	check(recording.messages.back().direction == [0.0, 0.0], "focus return keeps held state clear")
	app._input(key)
	app._leave_room()
	check(recording.messages[-2].direction == [0.0, 0.0] and recording.messages[-1].type == "leave", "leaving sends neutral before room command")
	app._left_room()
	check(app.player_input.direction() == Vector2.ZERO, "leaving resets held state")
	app._input(key)
	app._disconnected()
	check(app.player_input.direction() == Vector2.ZERO, "disconnect resets held state")
	recording.free()
	finish()


func test_latest_held_key_wins() -> void:
	var intent = InputIntent.new()
	intent.handle_key(KEY_W, true, false)
	intent.handle_key(KEY_D, true, false)
	check(intent.direction() == Vector2.RIGHT, "latest held direction wins")
	intent.handle_key(KEY_D, false, false)
	check(intent.direction() == Vector2.UP, "releasing latest direction falls back to held key")
	intent.handle_key(KEY_W, false, false)
	check(intent.direction() == Vector2.ZERO, "releasing all directions is neutral")
	check(intent.consume_move_press() == Vector2.RIGHT and intent.consume_move_press() == Vector2.ZERO, "latest short movement press is consumed once")


func test_alias_release_keeps_other_key() -> void:
	var intent = InputIntent.new()
	intent.handle_key(KEY_W, true, false)
	intent.handle_key(KEY_UP, true, false)
	intent.handle_key(KEY_UP, false, false)
	check(intent.direction() == Vector2.UP, "arrow release preserves separately held WASD alias")


func test_repeat_does_not_reorder() -> void:
	var intent = InputIntent.new()
	intent.handle_key(KEY_W, true, false)
	intent.handle_key(KEY_D, true, false)
	intent.consume_move_press()
	intent.handle_key(KEY_W, true, true)
	intent.handle_key(KEY_W, true, false)
	check(intent.direction() == Vector2.RIGHT and intent.consume_move_press() == Vector2.ZERO, "repeat and duplicate press do not reorder held keys or create an edge")


func test_bomb_press_is_consumed_once() -> void:
	var intent = InputIntent.new()
	intent.handle_key(KEY_SPACE, true, false)
	intent.handle_key(KEY_SPACE, false, false)
	check(intent.consume_bomb_press() and not intent.consume_bomb_press(), "short bomb tap is consumed once")
	intent.handle_key(KEY_ENTER, true, false)
	intent.consume_bomb_press()
	intent.handle_key(KEY_ENTER, true, true)
	check(not intent.consume_bomb_press(), "bomb repeat does not plant again")


func test_focus_loss_resets_input() -> void:
	var intent = InputIntent.new()
	intent.handle_key(KEY_LEFT, true, false)
	intent.handle_key(KEY_SPACE, true, false)
	intent.reset()
	check(intent.direction() == Vector2.ZERO and intent.consume_move_press() == Vector2.ZERO and not intent.consume_bomb_press(), "focus reset clears held state and pending edges")
	intent.handle_key(KEY_LEFT, true, false)
	check(intent.direction() == Vector2.LEFT, "fresh press works after reset")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Input checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
