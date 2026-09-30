extends RefCounted

const NAVY = Color("403d57")
const MUTED = Color("867f91")


static func field(parent: VBoxContainer, label_text: String, initial: String) -> LineEdit:
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


static func card(parent: Control, card_name: String, at: Vector2, dimensions: Vector2, inset: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = card_name
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


static func label(parent: VBoxContainer, value: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


static func spacer(parent: VBoxContainer, height: float) -> void:
	var empty := Control.new()
	empty.custom_minimum_size.y = height
	parent.add_child(empty)


static func button(parent: Container, text: String, height: float, background: Color, foreground: Color) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = height
	result.add_theme_font_size_override("font_size", 15)
	result.add_theme_color_override("font_color", foreground)
	result.add_theme_color_override("font_disabled_color", Color("aaa4af"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("f1edf0") if state == "disabled" else background.lightened(0.12) if state == "hover" else background.darkened(0.07) if state == "pressed" else background
		style.set_corner_radius_all(17)
		result.add_theme_stylebox_override(state, style)
	parent.add_child(result)
	return result


static func connection_text(phase: String, category: String, waking: bool, local_server: bool) -> String:
	match phase:
		"connecting":
			return "The server may be waking up. This can take about a minute." if waking else "Connecting to server… You can cancel."
		"waiting_room":
			return "Waiting for your room… You can cancel."
		"failed":
			match category:
				"room_not_found": return "Room not found. It may have closed after a server restart. Check the code or create a room."
				"room_full": return "Room is full. Try another room code or create a room."
				"room_rejected": return "The room request was rejected. Check your details and try again."
				"room_timeout": return "We could not confirm your room request. Retry when you are ready."
				"disconnected": return "Connection lost. Rejoin as a new player; if a round is running, you will wait for the next round."
				_: return "Could not connect. Check your connection and select Retry." + (" For local play, start the Godot room server." if local_server else "")
	return "Enter a nickname to begin."


static func is_loopback_server(url: String) -> bool:
	var authority := url.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0).to_lower()
	if authority.begins_with("[::1]"):
		return authority == "[::1]" or authority.begins_with("[::1]:")
	var host := authority.get_slice(":", 0)
	if host == "localhost":
		return true
	var parts := host.split(".")
	if parts.size() != 4 or parts[0] != "127":
		return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255:
			return false
	return true
