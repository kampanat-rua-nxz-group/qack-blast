extends Control


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 704)), Color("fff7ed"))
	draw_circle(Vector2(30, 35), 104.0, Color("ffe8d9"))
	draw_circle(Vector2(934, 678), 140.0, Color("e4f5ed"))
	draw_string(font, Vector2(142, 54), "QACK BLAST", HORIZONTAL_ALIGNMENT_LEFT, -1, 31, Color("403d57"))
	draw_string(font, Vector2(143, 78), "a tiny bomb battle for 2-6", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("867f91"))
	rounded_box(Rect2(704, 30, 114, 38), Color("ffe1a6"), 19.0)
	centered_text("ONLINE ROOM", Vector2(761, 55), 14, Color("73512d"))
	draw_duck(Vector2(84, 320), Color("65cfc6"))
	draw_duck(Vector2(876, 320), Color("f58fb1"))
	rounded_box(Rect2(142, 667, 414, 30), Color("e7f2ed"), 15.0)
	rounded_box(Rect2(574, 667, 244, 30), Color("f9e8ed"), 15.0)
	centered_text("CREATE  •  JOIN  •  PLAY", Vector2(349, 688), 14, Color("366b68"))
	centered_text("2–6 FRIENDS", Vector2(696, 688), 14, Color("92536b"))


func rounded_box(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(Rect2(rect.position + Vector2(radius, 0), Vector2(rect.size.x - radius * 2, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0, radius), Vector2(rect.size.x, rect.size.y - radius * 2)), color)
	for offset in [Vector2(radius, radius), Vector2(rect.size.x - radius, radius), Vector2(radius, rect.size.y - radius), Vector2(rect.size.x - radius, rect.size.y - radius)]:
		draw_circle(rect.position + offset, radius, color)


func centered_text(value: String, baseline: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_duck(pos: Vector2, color: Color) -> void:
	draw_circle(pos + Vector2(0, 8), 33.0, Color("78978a55"))
	draw_circle(pos + Vector2(-23, 2), 15.0, color.darkened(0.12))
	draw_circle(pos + Vector2(23, 2), 15.0, color.darkened(0.12))
	draw_circle(pos, 31.0, color)
	draw_circle(pos + Vector2(-12, -10), 11.0, color.lightened(0.35))
	draw_circle(pos + Vector2(-9, -8), 4.5, Color("403d57"))
	draw_circle(pos + Vector2(11, -8), 4.5, Color("403d57"))
	draw_colored_polygon(PackedVector2Array([pos + Vector2(-9, 7), pos + Vector2(9, 7), pos + Vector2(0, 19)]), Color("ffca79"))
	draw_circle(pos + Vector2(-20, 8), 4.5, Color("f9a8a0"))
	draw_circle(pos + Vector2(20, 8), 4.5, Color("f9a8a0"))
