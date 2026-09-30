extends SceneTree

var RoomClient = load("res://scripts/room_client.gd")
const RoomServer = preload("res://scripts/room_server.gd")
var Flow
var failures := 0
var smoke_client
var smoke_elapsed := 0.0
var smoke_reported := false
var integration_server
var integration_app
var integration_phase := 0
var integration_elapsed := 0.0
var integration_code := ""


func _initialize() -> void:
	if ResourceLoader.exists("res://scripts/connection_flow.gd"):
		Flow = load("res://scripts/connection_flow.gd")
	check(Flow != null, "deterministic connection controller exists")
	if Flow == null:
		finish()
		return
	test_timing_and_deadline()
	test_repeated_click_sends_one_request()
	test_cancel_ignores_old_attempt()
	test_sent_request_is_not_auto_replayed()
	test_room_rejection_does_not_retry_transport()
	test_transport_generation_ignores_late_packets()
	# Real transport smoke, kept separate from injected-time policy checks.
	smoke_client = RoomClient.new()
	root.add_child(smoke_client)
	smoke_client.transport_result.connect(func(_id, connected): smoke_reported = not connected)
	smoke_client.connect_to_server("ws://127.0.0.1:19089", 100)


func test_timing_and_deadline() -> void:
	var flow = Flow.new()
	flow.begin({"type": "create", "name": "Duck"})
	check(count_actions(flow.advance(0.0), "connect") == 1, "begin schedules initial transport")
	check(not flow.waking, "initial text does not claim server is waking")
	flow.advance(7.99)
	check(not flow.waking, "waking text waits eight seconds")
	flow.advance(0.01)
	check(flow.waking, "waking text appears at eight seconds")
	var actions: Array = flow.advance(4.0)
	check(count_actions(actions, "close") == 1 and count_actions(actions, "connect") == 0, "transport closes at twelve seconds before backoff")
	check(count_actions(flow.advance(0.99), "connect") == 0, "first retry waits one second")
	var old: int = flow.attempt_id
	check(count_actions(flow.advance(0.01), "connect") == 1, "first retry starts after one second")
	check(flow.on_transport_result(old, true).is_empty(), "timed-out generation cannot send on next attempt")
	for delay in [2.0, 4.0, 8.0, 8.0]:
		flow.on_transport_result(flow.attempt_id, false)
		check(count_actions(flow.advance(delay - 0.01), "connect") == 0, "retry waits %s seconds" % delay)
		check(count_actions(flow.advance(0.01), "connect") == 1, "retry starts at %s seconds" % delay)
	flow.advance(90.0 - flow.elapsed - 0.01)
	check(flow.phase == "connecting", "connection budget permits progress before ninety seconds")
	flow.advance(0.01)
	check(flow.phase == "failed" and flow.error_category == "connection", "ninety-second total deadline is final")
	check(count_actions(flow.advance(100.0), "connect") == 0, "deadline never reconnects automatically")


func test_repeated_click_sends_one_request() -> void:
	var flow = Flow.new()
	var id: int = flow.begin({"type": "create", "name": "First"})
	check(flow.begin({"type": "join", "name": "Second", "code": "ABCDEF"}) == id, "busy clicks do not supersede current attempt")
	flow.advance(0.0)
	var actions: Array = flow.on_transport_result(id, true)
	check(count_actions(actions, "send_request") == 1 and actions.filter(func(a): return a.type == "send_request")[0].request.name == "First", "busy clicks send only original request")
	check(count_actions(flow.on_transport_result(id, true), "send_request") == 0, "duplicate connected callback cannot resend")
	check(flow.pending_request.is_empty() and flow.retry_request.name == "First", "accepted command clears pending once and preserves retry input")


func test_cancel_ignores_old_attempt() -> void:
	var flow = Flow.new()
	var old: int = flow.begin({"type": "create", "name": "Old"})
	flow.advance(0.0)
	flow.cancel()
	check(flow.pending_request.is_empty() and flow.retry_request.is_empty(), "cancel discards unsent command and retry")
	check(count_actions(flow.advance(0.0), "close") == 1, "cancel closes transport")
	var current: int = flow.begin({"type": "join", "name": "New", "code": "ABCDEF"})
	flow.advance(0.0)
	check(current != old and flow.on_transport_result(old, true).is_empty(), "cancelled transport cannot send old request")
	check(flow.on_room_result(old, {"type": "joined"}).is_empty() and flow.phase == "connecting", "cancelled result cannot update phase")


func test_sent_request_is_not_auto_replayed() -> void:
	var flow = Flow.new()
	var id: int = flow.begin({"type": "create", "name": "Duck"})
	flow.advance(0.0)
	flow.on_transport_result(id, true)
	flow.advance(14.99)
	check(flow.phase == "waiting_room", "sent command waits fifteen seconds for outcome")
	var actions: Array = flow.advance(0.01)
	check(flow.phase == "failed" and flow.error_category == "room_timeout", "uncertain room outcome times out at fifteen seconds")
	check(count_actions(actions + flow.advance(100.0), "connect") == 0, "sent command never retries transport automatically")
	check(flow.on_room_result(id, {"type": "joined"}).is_empty(), "late accepted result cannot revive timed-out request")
	var retry: int = flow.begin(flow.retry_request)
	flow.advance(0.0)
	check(retry != id and count_actions(flow.on_transport_result(retry, true), "send_request") == 1, "explicit retry starts fresh command")
	var lost = Flow.new()
	id = lost.begin({"type": "create", "name": "Duck"})
	lost.advance(0.0)
	lost.on_transport_result(id, true)
	lost.on_transport_result(id, false)
	check(lost.phase == "failed" and count_actions(lost.advance(100.0), "connect") == 0, "disconnect after send cannot replay uncertain command")


func test_room_rejection_does_not_retry_transport() -> void:
	for rejection in [{"message": "Room not found", "category": "room_not_found"}, {"message": "Room is full", "category": "room_full"}, {"message": "Already in a room", "category": "room_rejected"}]:
		var flow = Flow.new()
		var id: int = flow.begin({"type": "join", "name": "Duck", "code": "ABCDEF"})
		flow.advance(0.0)
		flow.on_transport_result(id, true)
		flow.on_room_result(id, {"type": "error", "message": rejection.message})
		check(flow.phase == "failed" and flow.error_category == rejection.category, "authoritative rejection is distinct: %s" % rejection.message)
		check(count_actions(flow.advance(100.0), "connect") == 0, "room rejection does not retry transport")


func test_transport_generation_ignores_late_packets() -> void:
	var client = RoomClient.new()
	client.connect_to_server("ws://127.0.0.1:19089", 10)
	client.close_transport(10)
	client.connect_to_server("ws://127.0.0.1:19089", 20)
	client.accept({"type": "joined", "person_id": 99}, 10)
	client.accept({"type": "error", "message": "Old error"}, 10)
	check(client.person_id == 0 and client.transport_generation == 20, "late packet cannot restore cancelled identity")
	client.close_transport(10)
	check(client.transport_generation == 20, "old socket close cannot close new transport")
	client.close_transport(20)
	client.free()


func count_actions(actions: Array, kind: String) -> int:
	return actions.filter(func(action): return action.type == kind).size()


func _process(delta: float) -> bool:
	if smoke_client != null:
		smoke_elapsed += delta
		if smoke_reported or smoke_elapsed >= 2.0:
			check(smoke_reported, "unreachable loopback reports transport failure")
			smoke_client.close_transport(100)
			smoke_client.queue_free()
			smoke_client = null
			call_deferred("start_reachable_check")
		return false
	if integration_server == null:
		return false
	integration_server.poll(delta)
	integration_elapsed += delta
	if integration_elapsed >= 5.0:
		check(false, "reachable connection/restart smoke completes within five seconds")
		integration_server.socket.close()
		integration_app._cancel_connection()
		finish()
		return false
	match integration_phase:
		0:
			if not integration_app.client.room.is_empty():
				integration_code = integration_app.client.room.code
				check(integration_server.registry.rooms.size() == 1 and integration_app.pending_request.is_empty(), "reachable repeated clicks create exactly one room and clear pending")
				check(integration_app.connection_flow.phase == "in_room" and integration_app.waiting_card.visible, "real joined and snapshot reach waiting lobby")
				integration_server.socket.close()
				integration_phase = 1
		1:
			if integration_app.rejoin_button.visible:
				check(integration_app.code_field.text == integration_code and integration_app.client.person_id == 0, "real disconnect preserves code and clears identity")
				integration_server = RoomServer.new()
				check(integration_server.listen(19090) == OK, "server restart listens")
				integration_app._rejoin_room()
				integration_phase = 2
		2:
			if integration_app.connection_flow.phase == "failed":
				check(integration_app.connection_flow.error_category == "room_not_found", "rejoin after actual restart gets missing room category")
				check(integration_app.status_label.text.contains("server restart") and integration_app.retry_button.visible, "missing room offers clear recovery after restart")
				integration_server.socket.close()
				integration_app._cancel_connection()
				finish()
	return false


func start_reachable_check() -> void:
	integration_server = RoomServer.new()
	var result: int = integration_server.listen(19090)
	check(result == OK, "reachable server binds localhost")
	if result != OK:
		finish()
		return
	integration_app = load("res://scenes/online.tscn").instantiate()
	root.add_child(integration_app)
	integration_app.server_url = "ws://127.0.0.1:19090"
	integration_app.name_field.text = "Network Duck"
	integration_app.request({"type": "create", "name": "Network Duck"})
	integration_app.request({"type": "create", "name": "Duplicate Duck"})


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Connection checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
