extends RefCounted

# Pure timing policy. Every socket action carries its transport generation.
const ATTEMPT_SECONDS := 12.0
const CONNECT_SECONDS := 90.0
const ROOM_SECONDS := 15.0
const WAKING_SECONDS := 8.0
const BACKOFF := [1.0, 2.0, 4.0, 8.0]

var phase := "idle"
var error_category := ""
var attempt_id := 0
var pending_request: Dictionary = {}
var retry_request: Dictionary = {}
var elapsed := 0.0
var waking := false
var _attempt_elapsed := 0.0
var _room_elapsed := 0.0
var _backoff_remaining := 0.0
var _retry_count := 0
var _transport_active := false
var _actions: Array = []


func busy() -> bool:
	return phase == "connecting" or phase == "waiting_room"


func begin(request: Dictionary) -> int:
	if busy():
		return attempt_id
	attempt_id += 1
	pending_request = request.duplicate(true)
	retry_request = request.duplicate(true)
	phase = "connecting"
	error_category = ""
	elapsed = 0.0
	waking = false
	_attempt_elapsed = 0.0
	_room_elapsed = 0.0
	_backoff_remaining = 0.0
	_retry_count = 0
	_transport_active = true
	_actions.append({"type": "connect", "attempt_id": attempt_id})
	_display()
	return attempt_id


func advance(delta: float) -> Array:
	var remaining := maxf(delta, 0.0)
	while phase == "connecting" and remaining > 0.0:
		var boundary := ATTEMPT_SECONDS - _attempt_elapsed if _transport_active else _backoff_remaining
		var step := minf(remaining, minf(boundary, CONNECT_SECONDS - elapsed))
		elapsed += step
		remaining -= step
		if _transport_active:
			_attempt_elapsed += step
		else:
			_backoff_remaining -= step
		if not waking and elapsed >= WAKING_SECONDS - 0.000001:
			waking = true
			_display()
		if elapsed >= CONNECT_SECONDS - 0.000001:
			_fail("connection")
		elif _transport_active and _attempt_elapsed >= ATTEMPT_SECONDS - 0.000001:
			_retry_transport()
		elif not _transport_active and _backoff_remaining <= 0.000001:
			attempt_id += 1
			_transport_active = true
			_attempt_elapsed = 0.0
			_actions.append({"type": "connect", "attempt_id": attempt_id})
	if phase == "waiting_room":
		_room_elapsed += remaining
		if _room_elapsed >= ROOM_SECONDS - 0.000001:
			_fail("room_timeout")
	return _take_actions()


func on_transport_result(id: int, connected: bool) -> Array:
	if id != attempt_id:
		return []
	if phase == "connecting" and _transport_active:
		if connected:
			phase = "waiting_room"
			_room_elapsed = 0.0
			_actions.append({"type": "send_request", "attempt_id": id, "request": pending_request.duplicate(true)})
			pending_request.clear()
			_display()
		else:
			_retry_transport()
	elif not connected and phase == "waiting_room":
		_fail("room_timeout")
	elif not connected and phase == "in_room":
		_fail("disconnected")
	return _take_actions()


func on_room_result(id: int, message: Dictionary) -> Array:
	if id != attempt_id or phase != "waiting_room":
		return []
	match str(message.get("type", "")):
		"joined":
			phase = "in_room"
			_display()
		"error":
			match str(message.get("message", "")):
				"Room not found": _fail("room_not_found")
				"Room is full": _fail("room_full")
				_: _fail("room_rejected")
	return _take_actions()


func cancel() -> void:
	_actions.clear()
	_actions.append({"type": "close", "attempt_id": attempt_id})
	attempt_id += 1
	phase = "idle"
	error_category = ""
	pending_request.clear()
	retry_request.clear()
	_transport_active = false
	_display()


func _retry_transport() -> void:
	_actions.append({"type": "close", "attempt_id": attempt_id})
	_transport_active = false
	_backoff_remaining = BACKOFF[mini(_retry_count, BACKOFF.size() - 1)]
	_retry_count += 1
	_display()


func _fail(category: String) -> void:
	_actions.append({"type": "close", "attempt_id": attempt_id})
	_transport_active = false
	phase = "failed"
	error_category = category
	pending_request.clear()
	_display()


func _display() -> void:
	_actions.append({"type": "display_state", "attempt_id": attempt_id, "phase": phase, "error_category": error_category, "waking": waking})


func _take_actions() -> Array:
	var actions := _actions
	_actions = []
	return actions
