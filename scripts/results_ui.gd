extends Control

signal change_map_requested
signal play_again_requested
signal leave_requested

const ArenaGame = preload("res://scripts/arena_game.gd")
const LobbyArt = preload("res://scripts/lobby_art.gd")
const CharacterCatalog = preload("res://scripts/character_catalog.gd")
const DuckArt = preload("res://scripts/duck_art.gd")
const GameFeedback = preload("res://scripts/game_feedback.gd")
const Ui = preload("res://scripts/lobby_ui.gd")

const WIN_NOTE := "You won the round!"

var room_code: String = ""
var feedback: String = ""
var displayed_people: Array = []
var displayed_host := -1
var displayed_person_id := -1
var room_code_label: Label
var outcome_label: Label
var personal_note_label: Label
var map_label: Label
var status_label: Label
var leaderboard_rows: VBoxContainer
var map_button: Button
var replay_button: Button


func _ready() -> void:
	var art := LobbyArt.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	var column := Ui.card(self, "ResultsCard", Vector2(142, 108), Vector2(676, 536), 22)
	Ui.label(column, "ROUND RESULTS", 22, Ui.NAVY)
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 18)
	column.add_child(summary)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	summary.add_child(details)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 16)
	details.add_child(code_row)
	room_code_label = _text(code_row, "", "RoomCode", 22, Ui.NAVY)
	var copy_button := Ui.button(code_row, "COPY CODE", 36, Color("e7f2ed"), Color("366b68"))
	copy_button.name = "CopyCodeButton"
	copy_button.pressed.connect(_copy_code)
	map_label = Ui.label(details, "", 16, Ui.NAVY)
	map_label.name = "SelectedMap"
	var result_panel := PanelContainer.new()
	result_panel.name = "ResultHighlight"
	result_panel.custom_minimum_size = Vector2(300, 126)
	var result_style := StyleBoxFlat.new()
	result_style.bg_color = Color("f7e6ae")
	result_style.border_color = Color("e8cf7d")
	result_style.set_border_width_all(2)
	result_style.set_corner_radius_all(18)
	result_style.set_content_margin_all(14)
	result_panel.add_theme_stylebox_override("panel", result_style)
	summary.add_child(result_panel)
	var result_content := VBoxContainer.new()
	result_content.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(result_content)
	var result_caption := Ui.label(result_content, "ROUND RESULT", 13, Color("73512d"))
	result_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_label = Ui.label(result_content, "Round complete", 32, Ui.NAVY)
	outcome_label.name = "Outcome"
	outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	personal_note_label = Ui.label(column, "", 16, Ui.NAVY)
	personal_note_label.name = "PersonalNote"
	personal_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	personal_note_label.hide()
	var headings := HBoxContainer.new()
	column.add_child(headings)
	_add_score_cells(headings, "#", "PLAYER", "WINS", "KILLS")
	var portrait_gap := Control.new()
	portrait_gap.name = "PortraitGap"
	portrait_gap.custom_minimum_size.x = 54  # 32 px portrait + 18 px badge + one separation
	headings.add_child(portrait_gap)
	headings.move_child(portrait_gap, 1)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	leaderboard_rows = VBoxContainer.new()
	leaderboard_rows.name = "LeaderboardRows"
	leaderboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(leaderboard_rows)
	status_label = Ui.label(column, "", 14, Ui.MUTED)
	status_label.name = "Status"
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	map_button = Ui.button(actions, "EXPLORE MAPS", 40, Color("e7f2ed"), Color("366b68"))
	map_button.name = "ChangeMapButton"
	map_button.pressed.connect(func(): change_map_requested.emit())
	replay_button = Ui.button(actions, "PLAY AGAIN", 40, Color("ffe1a6"), Color("73512d"))
	replay_button.name = "PlayAgainButton"
	replay_button.pressed.connect(func(): play_again_requested.emit())
	var leave_button := Ui.button(actions, "LEAVE ROOM", 40, Color("f9e8ed"), Color("92536b"))
	leave_button.name = "LeaveRoomButton"
	leave_button.pressed.connect(func(): leave_requested.emit())
	for button in actions.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func present(room: Dictionary, game: Dictionary, person_id: int, personal_note: String = "") -> void:
	room_code = str(room.get("code", ""))
	room_code_label.text = room_code
	map_label.text = "MAP: %s" % ArenaGame.MAP_NAMES.get(room.get("wall_mode", "fixed"), "Classic")
	var people: Array = room.get("people", [])
	outcome_label.text = _outcome_text(game, people)
	_show_personal_note(_personal_note_text(game, people, person_id, personal_note))
	var outcome_size := 32
	while outcome_label.get_theme_font("font").get_string_size(outcome_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, outcome_size).x > 268.0 and outcome_size > 18:
		outcome_size -= 1
	outcome_label.add_theme_font_size_override("font_size", outcome_size)
	var connected_count := 0
	for person in people:
		if person.connected:
			connected_count += 1
	if people != displayed_people or room.host != displayed_host or person_id != displayed_person_id:
		_render_leaderboard(people, room.host, person_id)
		displayed_people = people.duplicate(true)
		displayed_host = room.host
		displayed_person_id = person_id
	var host: bool = room.host == person_id
	map_button.disabled = room.get("phase", "results") not in ["lobby", "results"]
	replay_button.disabled = not host or connected_count < 2
	status_label.text = feedback if not feedback.is_empty() else "Choose a map or play again." if host else "Waiting for the host to start the next round."


func _show_personal_note(text: String) -> void:
	personal_note_label.text = text
	personal_note_label.visible = not text.is_empty()


func _personal_note_text(game: Dictionary, people: Array, person_id: int, personal_note: String) -> String:
	var slot := -1
	var names: Array = []
	for person in people:
		var person_slot := int(person.get("slot", -1))
		if person_slot < 0:
			continue
		while names.size() <= person_slot:
			names.append("")
		names[person_slot] = str(person.name)
		if person.id == person_id:
			slot = person_slot
	if slot < 0:
		return ""
	var players: Array = game.get("players", [])
	if slot >= players.size():
		return personal_note
	if players[slot].get("alive", false):
		return WIN_NOTE
	var text := GameFeedback.out_text(players[slot].get("elimination_cause", {}), names)
	return personal_note if text == "OUT" and not personal_note.is_empty() else text


func _outcome_text(game: Dictionary, people: Array) -> String:
	var outcome := str(game.get("result", ""))
	if not game.get("round_over", false) or outcome.is_empty():
		return "Round complete"
	if outcome.begins_with("PLAYER ") and outcome.ends_with(" WINS"):
		var slot := outcome.trim_prefix("PLAYER ").trim_suffix(" WINS").to_int() - 1
		for person in people:
			if person.get("slot", -1) == slot:
				return "%s WINS" % person.name
	return outcome


func _render_leaderboard(people: Array, host_id: int, person_id: int) -> void:
	var entries: Array = []
	for i in range(people.size()):
		entries.append({"person": people[i], "index": i})
	entries.sort_custom(_entry_before)
	for row in leaderboard_rows.get_children():
		leaderboard_rows.remove_child(row)
		row.queue_free()
	for i in range(entries.size()):
		var person: Dictionary = entries[i].person
		var name: String = str(person.name)
		if person.id == person_id:
			name += " (YOU)"
		if person.id == host_id:
			name += " (host)"
		if not person.connected:
			name += " (offline)"
		var row := HBoxContainer.new()
		row.name = "ScoreRow"
		leaderboard_rows.add_child(row)
		var look := CharacterCatalog.appearance(person.get("avatar_id", -1))
		_add_score_cells(row, str(i + 1), name, str(person.wins), str(person.kills))
		row.add_child(DuckArt.portrait(look,32.0))
		row.move_child(row.get_node("Portrait"),1)
		row.get_node("Portrait").tooltip_text = "Badge %s · participant %s" % [look.badge,person.id]
		var badge := _text(row,look.badge,"Badge",14,Ui.NAVY)
		badge.custom_minimum_size.x = 18
		row.move_child(badge,2)


func show_error(message: String) -> void:
	feedback = message
	status_label.text = message


func clear_feedback() -> void:
	feedback = ""


func _copy_code() -> void:
	DisplayServer.clipboard_set(room_code)
	feedback = "Room code copied."
	status_label.text = feedback


func _entry_before(a: Dictionary, b: Dictionary) -> bool:
	var first: Dictionary = a.person
	var second: Dictionary = b.person
	if first.wins != second.wins:
		return first.wins > second.wins
	if first.kills != second.kills:
		return first.kills > second.kills
	return a.index < b.index


func _add_score_cells(row: HBoxContainer, rank: String, name: String, wins: String, kills: String) -> void:
	var rank_label := _text(row, rank, "Rank", 15, Ui.MUTED)
	rank_label.custom_minimum_size.x = 48
	var name_label := _text(row, name, "Name", 15, Ui.NAVY)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = name
	var wins_label := _text(row, wins, "Wins", 15, Ui.NAVY)
	wins_label.custom_minimum_size.x = 54
	var kills_label := _text(row, kills, "Kills", 15, Ui.NAVY)
	kills_label.custom_minimum_size.x = 54


func _text(parent: Container, value: String, node_name: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
