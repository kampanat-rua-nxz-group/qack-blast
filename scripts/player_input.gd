extends RefCounted

const DIRECTION_KEYS = {
	KEY_W: Vector2.UP, KEY_UP: Vector2.UP,
	KEY_S: Vector2.DOWN, KEY_DOWN: Vector2.DOWN,
	KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT,
	KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT,
}

var held_keys: Array[int] = []
var held_bombs: Array[int] = []
var move_press := Vector2.ZERO
var bomb_press := false


func handle_key(keycode: int, pressed: bool, echo: bool) -> void:
	if echo:
		return
	if DIRECTION_KEYS.has(keycode):
		if pressed and not held_keys.has(keycode):
			held_keys.append(keycode)
			move_press = DIRECTION_KEYS[keycode]
		elif not pressed:
			held_keys.erase(keycode)
	elif keycode in [KEY_SPACE, KEY_ENTER]:
		if pressed and not held_bombs.has(keycode):
			held_bombs.append(keycode)
			bomb_press = true
		elif not pressed:
			held_bombs.erase(keycode)


func direction() -> Vector2:
	return DIRECTION_KEYS[held_keys.back()] if not held_keys.is_empty() else Vector2.ZERO


func consume_move_press() -> Vector2:
	var pressed := move_press
	move_press = Vector2.ZERO
	return pressed


func consume_bomb_press() -> bool:
	var pressed := bomb_press
	bomb_press = false
	return pressed


func reset() -> void:
	held_keys.clear()
	held_bombs.clear()
	move_press = Vector2.ZERO
	bomb_press = false
