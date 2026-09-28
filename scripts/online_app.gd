extends Control

const RoomClient = preload("res://scripts/room_client.gd")
const ArenaScene = preload("res://scenes/arena.tscn")
const LobbyArt = preload("res://scripts/lobby_art.gd")
const NAVY = Color("403d57")
const MUTED = Color("867f91")

var client = RoomClient.new()
var arena: Node2D
var lobby: Control
var server_field: LineEdit
var name_field: LineEdit
var code_field: LineEdit
var room_label: Label
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


func build_lobby() -> void:
	lobby = Control.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby)
	var art := LobbyArt.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(art)
	var column := card(lobby, Vector2(142, 126), Vector2(414, 508), 24)
	label(column, "READY TO PLAY?", 24, NAVY)
	label(column, "Create a room or join your friends.", 15, MUTED)
	spacer(column, 9)
	server_field = field(column, "WEBSOCKET SERVER", "ws://127.0.0.1:9080")
	name_field = field(column, "NICKNAME", "Duck")
	code_field = field(column, "ROOM CODE", "")
	spacer(column, 7)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var create_button := Button.new()
	create_button.text = "CREATE ROOM"
	create_button.custom_minimum_size = Vector2(169, 47)
	button_style(create_button, Color("ffe1a6"), Color("73512d"))
	create_button.pressed.connect(func(): request({"type": "create", "name": name_field.text}))
	row.add_child(create_button)
	var join_button := Button.new()
	join_button.text = "JOIN ROOM"
	join_button.custom_minimum_size = Vector2(169, 47)
	button_style(join_button, Color("f9e8ed"), Color("92536b"))
	join_button.pressed.connect(func(): request({"type": "join", "name": name_field.text, "code": code_field.text}))
	row.add_child(join_button)
	spacer(column, 8)
	label(column, "Start the room server before creating a room.", 13, MUTED)
	label(column, "Each window controls one duck.", 13, MUTED)
	var status_column := card(lobby, Vector2(574, 126), Vector2(244, 508), 20)
	label(status_column, "ROOM STATUS", 20, NAVY)
	spacer(status_column, 5)
	room_label = label(status_column, "No room yet", 16, NAVY)
	room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spacer(status_column, 8)
	roster_label = label(status_column, "", 14, NAVY)
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label = label(status_column, "Enter a nickname to begin.", 14, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 72
	spacer(status_column, 6)
	map_button = Button.new()
	map_button.text = "CHANGE MAP"
	map_button.custom_minimum_size.y = 42
	button_style(map_button, Color("e7f2ed"), Color("366b68"))
	map_button.disabled = true
	map_button.pressed.connect(_change_map)
	status_column.add_child(map_button)
	start_button = Button.new()
	start_button.text = "START ROUND"
	start_button.custom_minimum_size.y = 42
	button_style(start_button, Color("ffe1a6"), Color("73512d"))
	start_button.disabled = true
	start_button.pressed.connect(func(): client.send({"type": "start"}))
	status_column.add_child(start_button)
	leave_button = Button.new()
	leave_button.text = "LEAVE ROOM"
	leave_button.custom_minimum_size.y = 42
	button_style(leave_button, Color("f9e8ed"), Color("92536b"))
	leave_button.disabled = true
	leave_button.pressed.connect(func(): client.send({"type": "leave"}))
	status_column.add_child(leave_button)


func field(parent: VBoxContainer, label_text: String, initial: String) -> LineEdit:
	label(parent, label_text, 13, MUTED)
	var edit := LineEdit.new()
	edit.text = initial
	edit.custom_minimum_size.y = 44
	edit.add_theme_font_size_override("font_size", 16)
	edit.add_theme_color_override("font_color", NAVY)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdf7")
	style.border_color = Color("d8d2df")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 13
	style.content_margin_right = 13
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	parent.add_child(edit)
	return edit


func card(parent: Control, at: Vector2, dimensions: Vector2, inset: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.custom_minimum_size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdf7")
	style.border_color = Color("d8d2df")
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	style.shadow_color = Color("e3d8d5")
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", inset)
	margin.add_theme_constant_override("margin_right", inset)
	margin.add_theme_constant_override("margin_top", inset)
	margin.add_theme_constant_override("margin_bottom", inset)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column


func label(parent: VBoxContainer, value: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


func spacer(parent: VBoxContainer, height: float) -> void:
	var empty := Control.new()
	empty.custom_minimum_size.y = height
	parent.add_child(empty)


func button_style(button: Button, background: Color, foreground: Color) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_disabled_color", Color("aaa4af"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f1edf0") if state == "disabled" else background.lightened(0.12) if state == "hover" else background.darkened(0.07) if state == "pressed" else background
		style.set_corner_radius_all(17)
		button.add_theme_stylebox_override(state, style)


func request(message: Dictionary) -> void:
	pending_request = message
	status_label.text = "Connecting to server..."
	if client.connected:
		_connected()
	else:
		client.connect_to_server(server_field.text.strip_edges())


func _connected() -> void:
	if not pending_request.is_empty():
		client.send(pending_request)
		pending_request = {}
		status_label.text = "Connecting to room..."


func _room_changed(room: Dictionary) -> void:
	var playing: bool = room.phase == "playing"
	lobby.visible = not playing
	arena.visible = playing
	code_field.text = room.code
	room_label.text = "Room %s  |  %s  |  map: %s" % [room.code, room.phase, room.wall_mode]
	var lines: Array[String] = []
	for person in room.people:
		lines.append("%s%s%s  —  Wins %d  Kills %d" % [person.name, " (host)" if person.id == room.host else "", " (offline)" if not person.connected else "", person.wins, person.kills])
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
		status_label.text = "Round over: %s. The host can start another round." % client.game.result
	elif room.phase == "lobby":
		status_label.text = "Waiting for 2–4 players."


func _game_changed(snapshot: Dictionary) -> void:
	var game = arena.game
	game.board = snapshot.board
	game.players.clear()
	for player in snapshot.players:
		game.players.append({"pos": Vector2(player.pos[0], player.pos[1]), "alive": player.alive, "bomb_limit": player.bomb_limit, "range": player.range, "facing": player.facing})
	game.player_count = game.players.size()
	game.bombs.clear()
	for bomb in snapshot.bombs:
		game.bombs.append({"tile": Vector2i(bomb.tile[0], bomb.tile[1]), "owner": bomb.owner, "time": bomb.time})
	game.flames.clear()
	for flame in snapshot.flames:
		game.flames.append({"tile": Vector2i(flame.tile[0], flame.tile[1]), "owner": flame.owner, "time": flame.time})
	game.pickups.clear()
	for pickup in snapshot.pickups:
		game.pickups[Vector2i(pickup.tile[0], pickup.tile[1])] = pickup.kind
	game.scores = snapshot.scores
	game.round_elapsed = snapshot.round_elapsed
	game.closed_layers = snapshot.closed_layers
	game.round_over = snapshot.round_over
	game.result = snapshot.result
	game.wall_mode = snapshot.wall_mode
	arena.visual_facing.resize(game.players.size())
	arena.walk_phase.resize(game.players.size())
	for i in range(game.players.size()):
		arena.visual_facing[i] = game.players[i].facing
		arena.walk_phase[i] = 0.0
	arena.queue_redraw()
	if not client.room.is_empty() and client.room.phase == "results":
		status_label.text = "Round over: %s. The host can start another round." % game.result


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
	var mode := "random" if client.room.wall_mode == "fixed" else "fixed"
	client.send({"type": "map", "mode": mode})


func _show_error(message: String) -> void:
	pending_request = {}
	status_label.text = message


func _left_room() -> void:
	lobby.show()
	arena.hide()
	room_label.text = "No room yet"
	roster_label.text = ""
	status_label.text = "Left room."
	start_button.disabled = true
	map_button.disabled = true
	leave_button.disabled = true


func _disconnected() -> void:
	_left_room()
	status_label.text = "Server disconnected. Reconnect to create or join a room."
