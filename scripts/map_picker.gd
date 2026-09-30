extends Control

signal map_selected(mode: String)

const MapCatalog = preload("res://scripts/map_catalog.gd")
const ArenaGame = preload("res://scripts/arena_game.gd")
const ArenaBoard = preload("res://scripts/arena_board.gd")
const Ui = preload("res://scripts/lobby_ui.gd")

var selected_mode := "fixed"
var inspected_mode := "fixed"
var can_select := false
var feedback := ""
var title_label: Label
var selected_label: Label
var terrain_label: Label
var pickup_label: Label
var hazard_label: Label
var preview_label: Label
var permission_label: Label
var select_button: Button
var preview: Control
var map_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("443954bb")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := Ui.card(self, "MapPickerCard", Vector2(142, 112), Vector2(676, 528), 22)
	Ui.label(column, "EXPLORE MAPS", 23, Ui.NAVY)
	selected_label = Ui.label(column, "", 15, Ui.MUTED)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	column.add_child(body)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 158
	list.add_theme_constant_override("separation", 10)
	body.add_child(list)
	for mode in ArenaGame.MAP_MODES:
		var button := Ui.button(list, MapCatalog.describe(mode).name, 47, Color("e7f2ed"), Color("366b68"))
		button.pressed.connect(inspect.bind(mode))
		map_buttons[mode] = button
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.custom_minimum_size.x = 440
	details.add_theme_constant_override("separation", 8)
	body.add_child(details)
	title_label = Ui.label(details, "", 21, Ui.NAVY)
	preview = Control.new()
	preview.custom_minimum_size.y = 88
	preview.draw.connect(_draw_preview)
	details.add_child(preview)
	preview_label = _description(details, 12, Ui.MUTED)
	terrain_label = _description(details, 14, Ui.NAVY)
	pickup_label = _description(details, 14, Ui.NAVY)
	hazard_label = _description(details, 14, Ui.NAVY)
	Ui.label(column, "Sudden death: warning at 3:00, strike at 3:05, then every 15s.", 13, Ui.MUTED)
	permission_label = Ui.label(column, "", 13, Ui.MUTED)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	select_button = Ui.button(actions, "SELECT MAP", 40, Color("ffe1a6"), Color("73512d"))
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.pressed.connect(_select_inspected)
	var close := Ui.button(actions, "CLOSE", 40, Color("f9e8ed"), Color("92536b"))
	close.custom_minimum_size.x = 120
	close.pressed.connect(hide)
	present(selected_mode, false)
	hide()


func _description(parent: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := Ui.label(parent, "", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func present(next_selected_mode: String, next_can_select: bool) -> void:
	if selected_mode != next_selected_mode:
		feedback = ""
	selected_mode = next_selected_mode
	can_select = next_can_select
	selected_label.text = "SELECTED FOR NEXT ROUND: %s" % MapCatalog.describe(selected_mode).name
	permission_label.text = feedback if not feedback.is_empty() else "Only a room update confirms your selection." if can_select else "Browse any map. Only the host can select before the round."
	for mode in map_buttons:
		map_buttons[mode].text = MapCatalog.describe(mode).name + (" ✓" if mode == selected_mode else "")
	inspect(inspected_mode)


func inspect(mode: String) -> void:
	inspected_mode = mode
	var entry: Dictionary = MapCatalog.describe(mode)
	title_label.text = entry.name
	preview_label.text = entry.preview_text
	terrain_label.text = "TERRAIN  " + entry.terrain_text
	pickup_label.text = "PICKUPS  " + entry.pickup_text
	hazard_label.text = entry.hazard_text
	select_button.disabled = not can_select or mode == selected_mode
	preview.queue_redraw()


func _select_inspected() -> void:
	if can_select and inspected_mode != selected_mode:
		feedback = ""
		present(selected_mode, can_select)
		map_selected.emit(inspected_mode)


func show_error(message: String) -> void:
	feedback = message
	permission_label.text = message


func _draw_preview() -> void:
	var renderer := ArenaBoard.new()
	var colors: Dictionary = renderer.map_colors(inspected_mode)
	renderer.free()
	var rows: Array = MapCatalog.describe(inspected_mode).preview
	var cell := 12.0
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var tile := Rect2(Vector2(x, y) * cell, Vector2.ONE * (cell - 1))
			var color: Color = colors.floor if (x + y) % 2 == 0 else colors.floor_alt
			if inspected_mode == "pond" and x == 3:
				color = Color("92d9dd")
			elif inspected_mode == "frost" and y == 3:
				color = Color("c5e9f7")
			if rows[y][x] == "#":
				color = colors.wall
			elif rows[y][x] == "c":
				color = colors.crate
			preview.draw_rect(tile, color)
	preview.draw_string(ThemeDB.fallback_font, Vector2(102, 30), "■  Wall     ■  Crate", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.NAVY)
	preview.draw_string(ThemeDB.fallback_font, Vector2(102, 55), "Routes, terrain and hazards vary.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.MUTED)
