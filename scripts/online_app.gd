extends Control

const ConnectionFlow = preload("res://scripts/connection_flow.gd")
const PlayerInput = preload("res://scripts/player_input.gd")
const RoomClient = preload("res://scripts/room_client.gd")
const ArenaPresentation = preload("res://scripts/arena_presentation.gd")
const ArenaGame = preload("res://scripts/arena_game.gd")
const ArenaScene = preload("res://scenes/arena.tscn")
const LobbyArt = preload("res://scripts/lobby_art.gd")
const CharacterCatalog = preload("res://scripts/character_catalog.gd")
const DuckArt = preload("res://scripts/duck_art.gd")
const Ui = preload("res://scripts/lobby_ui.gd")
const MapPicker = preload("res://scripts/map_picker.gd")
const ResultsScene = preload("res://scenes/results.tscn")

var client = RoomClient.new()
var arena: Node2D
var lobby: Control
var results: Control
var server_url := RoomClient.DEFAULT_SERVER_URL
var name_field: LineEdit
var code_field: LineEdit
var entry_card: Control
var waiting_card: Control
var room_label: Label
var room_detail_label: Label
var roster_label: Label
var roster_rows: VBoxContainer
var roster_people: Array = []
var roster_person_id := -1
var status_label: Label
var start_button: Button
var map_button: Button
var map_picker: Control
var leave_button: Button
var pending_request: Dictionary = {}
var connection_flow = ConnectionFlow.new()
var create_button: Button
var join_button: Button
var cancel_button: Button
var retry_button: Button
var rejoin_button: Button
var can_rejoin := false
var player_input = PlayerInput.new()
var input_focused := true
var input_clock := 0.0
var presentation = ArenaPresentation.new()
var input_phase := ""
var go_remaining := 0.0
var arena_round_id := -1
var mute_button: Button
var _last_countdown_shown := -1

const MUTE_BUTTON_RECT := Rect2(832, 24, 118, 38)
const MUTE_FONT_SIZE := 13


func _ready() -> void:
	var public_url := str(ProjectSettings.get_setting("network/public_server_url", "")) if OS.has_feature("web") else ""
	server_url = RoomClient.resolve_server_url(OS.get_cmdline_user_args(), web_server_param(), public_url)
	arena = ArenaScene.instantiate()
	arena.networked = true
	add_child(arena)
	arena.set_physics_process(false)
	arena.set_process_input(false)
	arena.hide()
	arena.feedback.unlocked = not OS.has_feature("web")
	add_child(client)
	client.transport_result.connect(_transport_result)
	client.room_result.connect(_room_result)
	client.room_changed.connect(_room_changed)
	client.game_changed.connect(_game_changed)
	client.events_received.connect(_on_events)
	client.error_received.connect(_show_error)
	client.left_room.connect(_left_room)
	client.transport_disconnected.connect(_disconnected)
	build_lobby()
	results = ResultsScene.instantiate()
	add_child(results)
	results.hide()
	results.change_map_requested.connect(_change_map)
	results.play_again_requested.connect(func(): client.send({"type": "start"}))
	results.leave_requested.connect(_leave_room)
	map_picker = MapPicker.new()
	add_child(map_picker)
	map_picker.map_selected.connect(_select_map)
	build_mute_button()


func build_mute_button() -> void:
	mute_button = Button.new()
	mute_button.name = "MuteButton"
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.position = MUTE_BUTTON_RECT.position
	mute_button.size = MUTE_BUTTON_RECT.size
	mute_button.add_theme_font_size_override("font_size", MUTE_FONT_SIZE)
	mute_button.pressed.connect(_toggle_mute)
	add_child(mute_button)
	_render_mute()


func _toggle_mute() -> void:
	arena.feedback.unlock()
	arena.feedback.set_muted(not arena.feedback.muted)
	_render_mute()


func _render_mute() -> void:
	mute_button.text = "Sound: OFF" if arena.feedback.muted else "Sound: ON"


func _on_events(round_id: int, events: Array) -> void:
	var names: Array = []
	var viewer := viewer_slot()
	for person in client.room.get("people", []):
		if person.slot >= 0:
			while names.size() <= person.slot:
				names.append("")
			names[person.slot] = person.name
	var context := {"viewer_slot": viewer, "wall_mode": client.room.get("wall_mode", "fixed"), "names": names, "local_play": false}
	context.visible = func(tile: Array) -> bool: return arena.visible_tile(Vector2i(tile[0], tile[1]))
	context.audio_reach = func(tile: Array) -> bool: return arena.within_audio_reach(Vector2i(tile[0], tile[1]))
	arena.feedback.consume_events(round_id, events, context)
	if client.room.get("phase", "") == "results" and round_id == int(client.room.get("round_id", -1)):
		results.present(client.room, client.game, client.person_id, arena.feedback.personal_cause)


func viewer_slot() -> int:
	for person in client.room.get("people", []):
		if person.id == client.person_id:
			return person.slot
	return -1


func web_server_param() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
	return str(value) if value != null else ""


func build_lobby() -> void:
	lobby = Control.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby)
	var art := LobbyArt.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(art)
	build_entry_card()
	build_waiting_card()
	var status_column := Ui.card(lobby, "StatusCard", Vector2(574, 126), Vector2(244, 508), 20)
	Ui.label(status_column, "ROOM STATUS", 20, Ui.NAVY)
	Ui.spacer(status_column, 5)
	room_detail_label = Ui.label(status_column, "No room yet", 16, Ui.NAVY)
	room_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Ui.spacer(status_column, 8)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.name = "RosterScroll"
	roster_scroll.custom_minimum_size.y = 80
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	status_column.add_child(roster_scroll)
	roster_rows = VBoxContainer.new()
	roster_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_rows)
	# Text summary remains available to checks and assistive inspection.
	roster_label = Label.new()
	roster_label.hide()
	status_column.add_child(roster_label)
	status_label = Ui.label(status_column, "Enter a nickname to begin.", 14, Ui.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 72
	Ui.spacer(status_column, 6)
	map_button = Ui.button(status_column, "EXPLORE MAPS", 42, Color("e7f2ed"), Color("366b68"))
	map_button.disabled = true
	map_button.pressed.connect(_change_map)
	start_button = Ui.button(status_column, "START ROUND", 42, Color("ffe1a6"), Color("73512d"))
	start_button.disabled = true
	start_button.pressed.connect(func(): client.send({"type": "start"}))
	leave_button = Ui.button(status_column, "LEAVE ROOM", 42, Color("f9e8ed"), Color("92536b"))
	leave_button.disabled = true
	leave_button.pressed.connect(_leave_room)


func build_entry_card() -> void:
	var column := Ui.card(lobby, "EntryCard", Vector2(142, 126), Vector2(414, 508), 24)
	entry_card = column.get_parent().get_parent()
	Ui.label(column, "READY TO PLAY?", 24, Ui.NAVY)
	Ui.label(column, "Create a room or join your friends.", 15, Ui.MUTED)
	Ui.spacer(column, 9)
	name_field = Ui.field(column, "NICKNAME", "Duck")
	code_field = Ui.field(column, "ROOM CODE", "")
	Ui.spacer(column, 7)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	create_button = Ui.button(row, "CREATE ROOM", 47, Color("ffe1a6"), Color("73512d"))
	create_button.custom_minimum_size.x = 169
	create_button.pressed.connect(func(): request({"type": "create", "name": name_field.text}))
	join_button = Ui.button(row, "JOIN ROOM", 47, Color("f9e8ed"), Color("92536b"))
	join_button.custom_minimum_size.x = 169
	join_button.pressed.connect(func(): request({"type": "join", "name": name_field.text, "code": code_field.text}))
	Ui.spacer(column, 8)
	var recovery := HBoxContainer.new()
	column.add_child(recovery)
	cancel_button = Ui.button(recovery, "CANCEL", 40, Color("f9e8ed"), Color("92536b"))
	cancel_button.pressed.connect(_cancel_connection)
	retry_button = Ui.button(recovery, "RETRY", 40, Color("ffe1a6"), Color("73512d"))
	retry_button.pressed.connect(_retry_connection)
	rejoin_button = Ui.button(recovery, "REJOIN ROOM", 40, Color("e7f2ed"), Color("366b68"))
	rejoin_button.pressed.connect(_rejoin_room)
	cancel_button.hide()
	retry_button.hide()
	rejoin_button.hide()
	Ui.label(column, "Each window controls one duck.", 13, Ui.MUTED)


func build_waiting_card() -> void:
	var column := Ui.card(lobby, "WaitingCard", Vector2(142, 126), Vector2(414, 508), 24)
	waiting_card = column.get_parent().get_parent()
	waiting_card.hide()
	Ui.label(column, "WAITING FOR DUCKS", 24, Ui.NAVY)
	Ui.label(column, "Share this code with your friends.", 15, Ui.MUTED)
	Ui.spacer(column, 9)
	Ui.label(column, "ROOM CODE", 13, Ui.MUTED)
	room_label = Ui.label(column, "", 48, Ui.NAVY)
	var copy_button := Ui.button(column, "COPY CODE", 47, Color("e7f2ed"), Color("366b68"))
	copy_button.name = "CopyCodeButton"
	copy_button.pressed.connect(_copy_code)
	Ui.spacer(column, 8)
	Ui.label(column, "The host starts the round once 2–10 players have joined.", 13, Ui.MUTED)


func _copy_code() -> void:
	DisplayServer.clipboard_set(room_label.text)
	status_label.text = "Room code copied."


func request(message: Dictionary) -> void:
	if connection_flow.busy():
		return
	can_rejoin = false
	connection_flow.begin(message)
	pending_request = connection_flow.pending_request.duplicate(true)
	_connection_actions(connection_flow.advance(0.0))


func _process(delta: float) -> void:
	_connection_actions(connection_flow.advance(delta))
	if go_remaining > 0.0:
		go_remaining = maxf(0.0, go_remaining - delta)
		if go_remaining == 0.0:
			arena.countdown_text = ""
			arena.queue_redraw()
	if arena.visible:
		arena.present_board(presentation.sample(Time.get_ticks_usec() / 1000000.0))


func _transport_result(generation: int, connected: bool) -> void:
	_connection_actions(connection_flow.on_transport_result(generation, connected))


func _room_result(generation: int, message: Dictionary) -> void:
	_connection_actions(connection_flow.on_room_result(generation, message))


func _connection_actions(actions: Array) -> void:
	for action in actions:
		match action.type:
			"close":
				client.close_transport(action.attempt_id)
			"connect":
				if action.attempt_id == connection_flow.attempt_id and connection_flow.phase == "connecting":
					client.connect_to_server(server_url, action.attempt_id)
			"send_request":
				if action.attempt_id == connection_flow.attempt_id and connection_flow.phase == "waiting_room":
					client.send(action.request)
					pending_request.clear()
			"display_state":
				_render_connection_state()
	pending_request = connection_flow.pending_request.duplicate(true)


func _render_connection_state() -> void:
	var busy: bool = connection_flow.busy()
	create_button.disabled = busy
	join_button.disabled = busy
	cancel_button.visible = busy
	retry_button.visible = connection_flow.phase == "failed" and not connection_flow.retry_request.is_empty() and not can_rejoin
	rejoin_button.visible = can_rejoin and not busy
	if connection_flow.phase != "in_room":
		status_label.text = Ui.connection_text(connection_flow.phase, connection_flow.error_category, connection_flow.waking, Ui.is_loopback_server(server_url))


func _cancel_connection() -> void:
	connection_flow.cancel()
	_connection_actions(connection_flow.advance(0.0))
	status_label.text = "Connection cancelled. Create or join when you are ready."


func _retry_connection() -> void:
	if not connection_flow.retry_request.is_empty():
		request(connection_flow.retry_request.duplicate(true))


func _rejoin_room() -> void:
	request({"type": "join", "name": name_field.text, "code": code_field.text})


func _room_changed(room: Dictionary) -> void:
	if not client.game.is_empty() and int(client.game.round_id) == int(room.round_id) and arena_round_id != int(room.round_id):
		_game_changed(client.game)
		return
	var playing: bool = room.phase == "playing"
	var countdown: bool = room.phase == "countdown"
	var showing_results: bool = room.phase == "results"
	if input_phase != room.phase:
		player_input.clear_pending()
		input_clock = 0.0
		if playing:
			if input_phase == "countdown":
				go_remaining = 0.6
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
		input_phase = room.phase
	if showing_results and not results.visible:
		results.clear_feedback()
	var matched: bool = arena_round_id == int(room.round_id)
	arena.visible = (playing or countdown) and matched
	lobby.visible = not arena.visible and not showing_results
	arena.countdown_text = str(int(ceil(room.countdown_remaining))) if countdown else ("GO" if go_remaining > 0.0 and playing else "")
	if arena.countdown_text.is_valid_int() and int(arena.countdown_text) > 0:
		if int(arena.countdown_text) != _last_countdown_shown:
			_last_countdown_shown = int(arena.countdown_text)
			arena.feedback.play_cue("countdown")
	else:
		_last_countdown_shown = -1
	results.visible = showing_results
	arena.player_names.clear()
	for person in room.people:
		if person.slot >= 0:
			while arena.player_names.size() <= person.slot:
				arena.player_names.append("")
			arena.player_names[person.slot] = person.name
	arena.queue_redraw()
	code_field.text = room.code
	entry_card.hide()
	waiting_card.show()
	room_label.text = room.code
	room_detail_label.text = "Room %s  |  %s  |  map: %s" % [room.code, room.phase, ArenaGame.MAP_NAMES[room.wall_mode]]
	var lines: Array[String] = []
	for person in room.people:
		lines.append("%s%s%s%s" % [person.name, " (YOU)" if person.id == client.person_id else "", " (host)" if person.id == room.host else "", " (offline)" if not person.connected else ""])
	roster_label.text = "\n".join(lines)
	_render_roster(room.people)
	var host: bool = room.host == client.person_id
	var connected_count := 0
	for person in room.people:
		if person.connected:
			connected_count += 1
	map_button.disabled = playing or countdown
	map_picker.present(room.wall_mode, host and not playing and not countdown)
	if playing or countdown:
		map_picker.hide()
	start_button.disabled = not host or playing or countdown or connected_count < 2
	leave_button.disabled = false
	if room.phase == "results" and not client.game.is_empty():
		status_label.text = "Round over: %s. The host can start another round." % arena.round_result_text()
	elif room.phase == "lobby":
		status_label.text = room.get("notice", "") if not room.get("notice", "").is_empty() else "Waiting for 2–10 players."
	elif (playing or countdown) and not matched:
		status_label.text = "Preparing the next round…"
	elif countdown:
		status_label.text = "Round starts in %d…" % int(ceil(room.countdown_remaining))
	if showing_results:
		results.present(room, client.game if matched else {}, client.person_id, arena.feedback.personal_cause)


func _game_changed(snapshot: Dictionary) -> void:
	if not client.valid_snapshot_geometry(snapshot):
		return
	if not client.room.is_empty() and int(snapshot.round_id) != int(client.room.round_id):
		return
	if not presentation.accepts_snapshot(snapshot):
		return
	presentation.push_snapshot(snapshot, Time.get_ticks_usec() / 1000000.0)
	var game = arena.game
	var geometry: Dictionary = snapshot.geometry
	game.WIDTH = int(geometry.width)
	game.HEIGHT = int(geometry.height)
	game.CELL = float(geometry.cell)
	game.ORIGIN = Vector2(geometry.origin[0], geometry.origin[1])
	game.board = snapshot.board
	game.terrain = snapshot.get("terrain", [])
	game.players.clear()
	game.move_targets.clear()
	game.slide_active.clear()
	for player in snapshot.players:
		game.players.append({"pos": Vector2(player.pos[0], player.pos[1]), "alive": player.alive, "bomb_limit": player.bomb_limit, "range": player.range, "vision": player.vision, "speed_bonus": player.get("speed_bonus", 0.0), "can_kick": player.get("can_kick", false), "facing": player.facing, "avatar_id": player.get("avatar_id", game.players.size()), "elimination_cause": player.get("elimination_cause", {}).duplicate(true)})
		game.move_targets.append(Vector2(player.move_target[0], player.move_target[1]))
		game.slide_active.append(bool(player.get("sliding", false)))
	game.player_count = game.players.size()
	game.bombs.clear()
	for bomb in snapshot.bombs:
		var kick_direction: Array = bomb.get("kick_direction", [0, 0])
		game.bombs.append({"tile": Vector2i(bomb.tile[0], bomb.tile[1]), "owner": bomb.owner, "time": bomb.time, "danger": bomb.get("danger", false), "kick_direction": Vector2i(kick_direction[0], kick_direction[1]), "kick_progress": bomb.get("kick_progress", 0.0)})
	game.hazards.clear()
	for hazard in snapshot.get("hazards", []):
		var tiles: Array[Vector2i] = []
		for tile in hazard.tiles:
			tiles.append(Vector2i(tile[0], tile[1]))
		game.hazards.append({"kind": hazard.kind, "tiles": tiles, "time": hazard.time})
	game.flames.clear()
	for flame in snapshot.flames:
		game.flames.append({"tile": Vector2i(flame.tile[0], flame.tile[1]), "owner": flame.owner, "time": flame.time, "kind": flame.get("kind", "")})
	game.pickups.clear()
	for pickup in snapshot.pickups:
		game.pickups[Vector2i(pickup.tile[0], pickup.tile[1])] = pickup.kind
	game.scores = snapshot.scores
	game.round_elapsed = snapshot.round_elapsed
	game.round_over = snapshot.round_over
	game.result = snapshot.result
	game.wall_mode = snapshot.wall_mode
	arena_round_id = int(snapshot.round_id)
	arena.viewer_slot = -1
	if not client.room.is_empty():
		for person in client.room.people:
			if person.id == client.person_id:
				arena.viewer_slot = person.slot
				break
	arena.present_board(presentation.sample(Time.get_ticks_usec() / 1000000.0))
	arena.feedback.reset(int(snapshot.round_id), client.event_floor)
	if arena.viewer_slot >= 0 and arena.viewer_slot < game.players.size() and not game.players[arena.viewer_slot].alive:
		var cause: Dictionary = game.players[arena.viewer_slot].elimination_cause
		if not cause.is_empty():
			var names: Array = []
			for person in client.room.get("people", []):
				if person.slot >= 0:
					while names.size() <= person.slot:
						names.append("")
					names[person.slot] = person.name
			arena.feedback.personal_cause = arena.feedback.out_text(cause, names)
	if not client.room.is_empty():
		_room_changed(client.room)
	if not client.room.is_empty() and client.room.phase == "results":
		status_label.text = "Round over: %s. The host can start another round." % arena.round_result_text()
		results.present(client.room, snapshot, client.person_id, arena.feedback.personal_cause)


func _input(event: InputEvent) -> void:
	if event.is_pressed():
		arena.feedback.unlock()
	if not input_focused or client.room.is_empty() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	var previous: Vector2 = player_input.direction()
	var keycode: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	player_input.handle_key(keycode, key.pressed, key.echo)
	if client.room.phase != "playing":
		player_input.clear_pending()
		return
	var press: Vector2 = player_input.consume_move_press()
	var plant: bool = player_input.consume_bomb_press()
	if previous != player_input.direction() or press != Vector2.ZERO or plant:
		_send_input(press, plant)
		input_clock = 0.0


func _physics_process(delta: float) -> void:
	if not input_focused or client.room.is_empty() or client.room.phase != "playing":
		return
	input_clock += delta
	if input_clock >= 1.0 / 30.0:
		input_clock = 0.0
		_send_input()


func _send_input(move_press: Vector2 = Vector2.ZERO, plant: bool = false) -> void:
	var direction: Vector2 = player_input.direction()
	var command := {"type": "input", "direction": [direction.x, direction.y], "plant": plant}
	if move_press != Vector2.ZERO:
		command.move_press = [move_press.x, move_press.y]
	client.send(command)


func _reset_input(send_neutral: bool = true) -> void:
	player_input.reset()
	input_phase = ""
	input_clock = 0.0
	if send_neutral and not client.room.is_empty():
		_send_input()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		input_focused = false
		_reset_input()
	elif what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		input_focused = true


func _leave_room() -> void:
	_reset_input()
	client.send({"type": "leave"})


func _change_map() -> void:
	if client.room.is_empty() or client.room.phase not in ["lobby", "results"]:
		return
	map_picker.present(client.room.wall_mode, client.room.host == client.person_id)
	map_picker.inspect(client.room.wall_mode)
	map_picker.show()


func _select_map(mode: String) -> void:
	if not client.room.is_empty() and client.room.host == client.person_id and client.room.phase in ["lobby", "results"]:
		client.send({"type": "map", "mode": mode})


func _show_error(message: String) -> void:
	if connection_flow.phase == "failed":
		return
	pending_request = {}
	if map_picker.visible:
		map_picker.show_error(message)
	if results.visible:
		results.show_error(message)
	else:
		status_label.text = message


func _left_room() -> void:
	arena.feedback.clear()
	map_picker.hide()
	presentation.reset()
	go_remaining = 0.0
	arena_round_id = -1
	arena.countdown_text = ""
	arena.present_board()
	connection_flow.cancel()
	_connection_actions(connection_flow.advance(0.0))
	can_rejoin = false
	rejoin_button.hide()
	_reset_input(false)
	lobby.show()
	arena.hide()
	arena.player_names.clear()
	results.hide()
	results.clear_feedback()
	waiting_card.hide()
	entry_card.show()
	room_label.text = ""
	room_detail_label.text = "No room yet"
	roster_label.text = ""
	_render_roster([])
	status_label.text = "Left room."
	start_button.disabled = true
	map_button.disabled = true
	leave_button.disabled = true


func _disconnected() -> void:
	if connection_flow.phase == "waiting_room":
		return
	var previous_code := code_field.text
	_left_room()
	client.person_id = 0
	client.room = {}
	client.game = {}
	code_field.text = previous_code
	can_rejoin = not previous_code.is_empty()
	connection_flow.phase = "failed"
	connection_flow.error_category = "disconnected"
	_render_connection_state()


func _render_roster(people: Array) -> void:
	if people == roster_people and roster_person_id == client.person_id:
		return
	roster_people = people.duplicate(true)
	roster_person_id = client.person_id
	for row in roster_rows.get_children():
		roster_rows.remove_child(row)
		row.queue_free()
	for person in people:
		var row := HBoxContainer.new()
		roster_rows.add_child(row)
		var look := CharacterCatalog.appearance(person.get("avatar_id", -1))
		row.add_child(DuckArt.portrait(look,32.0))
		var name := "%s · %s%s%s" % [look.badge,person.name," (YOU)" if person.id == client.person_id else ""," (offline)" if not person.connected else ""]
		var label := Label.new()
		row.add_child(label)
		label.text = name
		label.add_theme_font_size_override("font_size",14)
		label.add_theme_color_override("font_color",Ui.NAVY)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = name
