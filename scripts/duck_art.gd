extends RefCounted

# Draw in a 52 px cosmetic envelope, scaled with the board. Front is +Y.
static func draw(target: CanvasItem, appearance: Dictionary, pos: Vector2, facing: float, phase: float, size: float) -> void:
	var color: Color = appearance.palette.body
	var ink: Color = appearance.palette.outline
	var factor := size / 52.0
	var bounce := -absf(sin(phase)) * 1.8
	var wing := absf(sin(phase)) * 1.0
	target.draw_circle(pos + Vector2(0, 7) * factor, 17.0 * factor, Color("403d5728"))
	target.draw_set_transform(pos + Vector2(0, bounce) * factor, facing, Vector2.ONE * factor)
	polygon(target, [Vector2(-5,-10), Vector2(0,-21), Vector2(6,-10)], ink)
	polygon(target, [Vector2(-3,-11), Vector2(0,-18), Vector2(4,-11)], color)
	circle(target, Vector2(-13-wing, 1), 7.0, color.darkened(0.12), ink)
	circle(target, Vector2(13+wing, 1), 7.0, color.darkened(0.12), ink)
	circle(target, Vector2.ZERO, 15.0, color, ink)
	target.draw_circle(Vector2(-6,-5), 5.0, color.lightened(0.35))
	accessory(target, appearance.accessory, appearance.palette.accent, ink)
	# Broad flat bill stays in front of every costume, and rotates with facing.
	polygon(target, [Vector2(-8,5), Vector2(8,5), Vector2(9,11), Vector2(5,14), Vector2(-5,14), Vector2(-9,11)], ink)
	polygon(target, [Vector2(-6,6), Vector2(6,6), Vector2(7,10), Vector2(4,12), Vector2(-4,12), Vector2(-7,10)], Color("ffca79"))
	target.draw_line(Vector2(-4,9), Vector2(4,9), Color("ca884b"), 1.0, true)
	target.draw_circle(Vector2(-5,-1), 2.2, ink)
	target.draw_circle(Vector2(5,-1), 2.2, ink)
	target.draw_circle(Vector2(-10,5), 2.0, Color("f9a8a0"))
	target.draw_circle(Vector2(10,5), 2.0, Color("f9a8a0"))
	target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func circle(target: CanvasItem, pos: Vector2, radius: float, fill: Color, ink: Color) -> void:
	target.draw_circle(pos, radius + 1.3, ink)
	target.draw_circle(pos, radius, fill)

static func polygon(target: CanvasItem, points: Array, color: Color) -> void:
	target.draw_colored_polygon(PackedVector2Array(points), color)

static func accessory(target: CanvasItem, kind: String, accent: Color, ink: Color) -> void:
	match kind:
		"sailor":
			target.draw_rect(Rect2(-12,-18,24,9), ink)
			target.draw_rect(Rect2(-10,-17,20,6), Color("fffdf7"))
			target.draw_line(Vector2(-12,-10), Vector2(12,-10), Color("45739c"), 3.0, true)
		"goggles":
			target.draw_line(Vector2(-13,-9), Vector2(13,-9), ink, 4.0, true)
			circle(target, Vector2(-6,-10), 5.0, Color("e1f7ff"), ink)
			circle(target, Vector2(6,-10), 5.0, Color("e1f7ff"), ink)
		"chef":
			circle(target, Vector2(-7,-18), 5.0, Color("fffdf7"), ink)
			circle(target, Vector2(0,-20), 5.0, Color("fffdf7"), ink)
			circle(target, Vector2(7,-18), 5.0, Color("fffdf7"), ink)
			target.draw_rect(Rect2(-9,-18,18,10), ink)
			target.draw_rect(Rect2(-7,-19,14,9), Color("fffdf7"))
			target.draw_line(Vector2(-8,-9), Vector2(8,-9), accent, 2.0, true)

		"sprout":
			# Tall thin stem with one large leaf on a single side.
			target.draw_line(Vector2(0,-10),Vector2(0,-27),ink,3.5,true)
			target.draw_line(Vector2(0,-10),Vector2(0,-27),Color("36794f"),1.5,true)
			polygon(target,[Vector2(0,-19),Vector2(14,-30),Vector2(15,-20),Vector2(7,-13)],ink)
			polygon(target,[Vector2(1,-20),Vector2(12,-28),Vector2(12,-21),Vector2(6,-15)],Color("5cb96b"))
		"bow":
			polygon(target,[Vector2(0,-13),Vector2(-13,-22),Vector2(-13,-9)],ink)
			polygon(target,[Vector2(0,-13),Vector2(13,-22),Vector2(13,-9)],ink)
			polygon(target,[Vector2(-2,-14),Vector2(-11,-19),Vector2(-11,-11)],Color("e85f83"))
			polygon(target,[Vector2(2,-14),Vector2(11,-19),Vector2(11,-11)],Color("e85f83"))
			circle(target,Vector2(0,-14),3.0,accent,ink)
		"visor":
			target.draw_arc(Vector2(0,-4),10.0,PI,TAU,16,ink,5.0,true)
			polygon(target,[Vector2(-11,-10),Vector2(12,-10),Vector2(18,-6),Vector2(4,-6)],ink)
			polygon(target,[Vector2(-9,-10),Vector2(11,-10),Vector2(14,-8),Vector2(0,-8)],Color("faf3d5"))
		"crown":
			polygon(target,[Vector2(-11,-10),Vector2(-13,-23),Vector2(-5,-17),Vector2(0,-25),Vector2(5,-17),Vector2(13,-23),Vector2(11,-10)],ink)
			polygon(target,[Vector2(-9,-12),Vector2(-10,-20),Vector2(-4,-15),Vector2(0,-22),Vector2(4,-15),Vector2(10,-20),Vector2(9,-12)],Color("ffe09b"))
		"detective":
			polygon(target,[Vector2(-10,-11),Vector2(-7,-22),Vector2(7,-22),Vector2(10,-11)],ink)
			polygon(target,[Vector2(-8,-12),Vector2(-5,-20),Vector2(5,-20),Vector2(8,-12)],Color("af7854"))
			target.draw_line(Vector2(-17,-10),Vector2(17,-10),ink,4.0,true)
			target.draw_line(Vector2(-16,-11),Vector2(16,-11),Color("d9b182"),2.0,true)
		"knit":
			circle(target,Vector2(0,-12),10.0,Color("aa597e"),ink)
			target.draw_rect(Rect2(-12,-13,24,5),ink)
			target.draw_rect(Rect2(-10,-12,20,3),accent)
			circle(target,Vector2(6,-21),3.0,Color("fffdf7"),ink)
		"crest":
			# Wide, low comb of five short spikes across the head.
			var comb := [Vector2(-14,-9),Vector2(-13,-19),Vector2(-7,-13),Vector2(-4,-22),Vector2(0,-14),Vector2(4,-22),Vector2(7,-13),Vector2(13,-19),Vector2(14,-9)]
			polygon(target,comb,ink)
			polygon(target,[Vector2(-11,-10),Vector2(-11,-16),Vector2(-6,-12),Vector2(-4,-19),Vector2(0,-12),Vector2(4,-19),Vector2(6,-12),Vector2(11,-16),Vector2(11,-10)],Color("cc633e"))


static func portrait(appearance: Dictionary, size: float = 36.0) -> Control:
	var control := Control.new()
	control.name = "Portrait"
	control.custom_minimum_size = Vector2.ONE * size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.draw.connect(func(): draw(control, appearance, Vector2.ONE * size * 0.5, 0.0, 0.0, size))
	return control
