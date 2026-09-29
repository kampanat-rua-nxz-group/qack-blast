extends Control

const RoomClient = preload("res://scripts/room_client.gd")
const ArenaGame = preload("res://scripts/arena_game.gd")
const ArenaScene = preload("res://scenes/arena.tscn")
const LobbyArt = preload("res://scripts/lobby_art.gd")
const Ui = preload("res://scripts/lobby_ui.gd")
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
var status_label: Label
var start_button: Button
var map_button: Button
var leave_button: Button
var pending_request: Dictionary = {}
var last_drop := false
var pending_drop := false
var input_clock := 0.0


func _ready() -> void:
	var public_url := str(ProjectSettings.get_setting("network/public_server_url", "")) if OS.has_feature("web") else ""
	server_url = RoomClient.resolve_server_url(OS.get_cmdline_user_args(), web_server_param(), public_url)
	arena = ArenaScene.instantiate()
	arena.networked = true
	add_child(arena)
	arena.set_physics_process(false)
	arena.set_process_input(false)
	arena.hide()
	add_child(client)
	client.transport_connected.connect(_connected)
	client.room_changed.connect(_room_changed)
	client.game_changed.connect(_game_changed)
	client.error_received.connect(_show_error)
	client.left_room.connect(_left_room)
	client.transport_disconnected.connect(_disconnected)
	build_lobby()
	results = ResultsScene.instantiate()
	add_child(results)
	results.hide()
	results.change_map_requested.connect(_change_map)
	results.play_again_requested.connect(func(): client.send({"type": "start"}))
	results.leave_requested.connect(func(): client.send({"type": "leave"}))


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
	roster_label = Ui.label(status_column, "", 14, Ui.NAVY)
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label = Ui.label(status_column, "Enter a nickname to begin.", 14, Ui.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 72
	Ui.spacer(status_column, 6)
	map_button = Ui.button(status_column, "CHANGE MAP", 42, Color("e7f2ed"), Color("366b68"))
	map_button.disabled = true
	map_button.pressed.connect(_change_map)
	start_button = Ui.button(status_column, "START ROUND", 42, Color("ffe1a6"), Color("73512d"))
	start_button.disabled = true
	start_button.pressed.connect(func(): client.send({"type": "start"}))
	leave_button = Ui.button(status_column, "LEAVE ROOM", 42, Color("f9e8ed"), Color("92536b"))
	leave_button.disabled = true
	leave_button.pressed.connect(func(): client.send({"type": "leave"}))


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
	var create_button := Ui.button(row, "CREATE ROOM", 47, Color("ffe1a6"), Color("73512d"))
	create_button.custom_minimum_size.x = 169
	create_button.pressed.connect(func(): request({"type": "create", "name": name_field.text}))
	var join_button := Ui.button(row, "JOIN ROOM", 47, Color("f9e8ed"), Color("92536b"))
	join_button.custom_minimum_size.x = 169
	join_button.pressed.connect(func(): request({"type": "join", "name": name_field.text, "code": code_field.text}))
	Ui.spacer(column, 8)
	Ui.label(column, "Start the room server before creating a room.", 13, Ui.MUTED)
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
	Ui.label(column, "The host starts the round once 2–6 players have joined.", 13, Ui.MUTED)


func _copy_code() -> void:
	DisplayServer.clipboard_set(room_label.text)
	status_label.text = "Room code copied."


func request(message: Dictionary) -> void:
	pending_request = message
	status_label.text = "Connecting to server..."
	if client.connected:
		_connected()
	else:
		client.connect_to_server(server_url)


func _connected() -> void:
	if not pending_request.is_empty():
		client.send(pending_request)
		pending_request = {}
		status_label.text = "Connecting to room..."


func _room_changed(room: Dictionary) -> void:
	var playing: bool = room.phase == "playing"
	var showing_results: bool = room.phase == "results"
	if showing_results and not results.visible:
		results.clear_feedback()
	lobby.visible = not playing and not showing_results
	arena.visible = playing
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
		lines.append("%s%s%s" % [person.name, " (host)" if person.id == room.host else "", " (offline)" if not person.connected else ""])
	roster_label.text = "\n".join(lines)
	var host: bool = room.host == client.person_id
	var connected_count := 0
	for person in room.people:
		if person.connected:
			connected_count += 1
	map_button.disabled = not host or playing
	start_button.disabled = not host or playing or connected_count < 2
	leave_button.disabled = false
	if room.phase == "results" and not client.game.is_empty():
		status_label.text = "Round over: %s. The host can start another round." % arena.round_result_text()
	elif room.phase == "lobby":
		status_label.text = "Waiting for 2–6 players."
	if showing_results:
		results.present(room, client.game, client.person_id)


func _game_changed(snapshot: Dictionary) -> void:
	var game = arena.game
	game.configure_map(snapshot.players.size())
	game.board = snapshot.board
	game.terrain = snapshot.get("terrain", [])
	game.players.clear()
	for player in snapshot.players:
		game.players.append({"pos": Vector2(player.pos[0], player.pos[1]), "alive": player.alive, "bomb_limit": player.bomb_limit, "range": player.range, "vision": player.vision, "speed_bonus": player.get("speed_bonus", 0.0), "can_kick": player.get("can_kick", false), "facing": player.facing})
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
	arena.viewer_slot = -1
	if not client.room.is_empty():
		for person in client.room.people:
			if person.id == client.person_id:
				arena.viewer_slot = person.slot
				break
	arena.visual_facing.resize(game.players.size())
	arena.walk_phase.resize(game.players.size())
	for i in range(game.players.size()):
		arena.visual_facing[i] = game.players[i].facing
		arena.walk_phase[i] = 0.0
	arena.queue_redraw()
	if not client.room.is_empty() and client.room.phase == "results":
		status_label.text = "Round over: %s. The host can start another round." % arena.round_result_text()
		results.present(client.room, snapshot, client.person_id)


func _physics_process(delta: float) -> void:
	if client.room.is_empty() or client.room.phase != "playing":
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction = Vector2.UP
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction = Vector2.DOWN
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction = Vector2.LEFT
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction = Vector2.RIGHT
	var drop := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)
	pending_drop = pending_drop or (drop and not last_drop)
	last_drop = drop
	input_clock += delta
	if input_clock >= 1.0 / 30.0 or pending_drop:
		input_clock = 0.0
		client.send({"type": "input", "direction": [direction.x, direction.y], "plant": pending_drop})
		pending_drop = false


func _change_map() -> void:
	var modes: Array = ArenaGame.MAP_MODES
	var mode: String = modes[(modes.find(client.room.wall_mode) + 1) % modes.size()]
	client.send({"type": "map", "mode": mode})


func _show_error(message: String) -> void:
	pending_request = {}
	if results.visible:
		results.show_error(message)
	else:
		status_label.text = message


func _left_room() -> void:
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
	status_label.text = "Left room."
	start_button.disabled = true
	map_button.disabled = true
	leave_button.disabled = true


func _disconnected() -> void:
	_left_room()
	status_label.text = "Server disconnected. Reconnect to create or join a room."
