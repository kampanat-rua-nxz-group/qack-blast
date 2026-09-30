extends SceneTree

const Registry = preload("res://scripts/room_registry.gd")
var failures := 0

func _initialize() -> void:
	test_catalog_has_ten_distinct_identities()
	test_avatar_survives_slot_reordering()
	test_disconnect_reserves_live_avatar()
	test_waiting_spectator_gets_identity_before_start()
	test_history_does_not_steal_active_identity()
	print("Character checks: %d failure(s)" % failures)
	quit(1 if failures else 0)

func test_catalog_has_ten_distinct_identities() -> void:
	check(ResourceLoader.exists("res://scripts/character_catalog.gd"), "shared catalog exists")
	if not ResourceLoader.exists("res://scripts/character_catalog.gd"):
		return
	var catalog = load("res://scripts/character_catalog.gd")
	var shapes := {}
	var colors := {}
	for i in range(10):
		var look: Dictionary = catalog.appearance(i)
		check(look.badge == str(i + 1), "stable numbered badge")
		shapes[look.accessory] = true
		colors[look.palette.body] = true
		check(not look.has("speed") and not look.has("range"), "appearance is cosmetic")
	check(shapes.size() == 10 and colors.size() == 10, "ten distinct colors and silhouettes")
	check(catalog.appearance(-1).badge == "?", "waiting identity is neutral")

func setup_room() -> Dictionary:
	var registry = Registry.new()
	var created: Dictionary = registry.create_room(1, "Host")
	registry.join_room(2, created.code, "Guest")
	return {"registry": registry, "room": registry.room_for_peer(1), "code": created.code}

func test_avatar_survives_slot_reordering() -> void:
	var setup := setup_room()
	var registry = setup.registry
	registry.join_room(3, setup.code, "Third")
	var guest: Dictionary = setup.room.people[1]
	check(guest.has("avatar_id"), "room participant owns appearance")
	if not guest.has("avatar_id"):
		return
	var identity: int = guest.avatar_id
	registry.leave(1)
	registry.start_round(2)
	check(guest.slot == 0 and guest.avatar_id == identity, "appearance survives slot reordering")
	check(registry.room_view(setup.room).people[1].avatar_id == identity, "room view carries identity")
	check(registry.game_view(setup.room).players[0].avatar_id == identity, "game view carries identity")

func test_disconnect_reserves_live_avatar() -> void:
	var setup := setup_room()
	var registry = setup.registry
	registry.start_round(1)
	registry.tick(3.0)
	var old: Dictionary = setup.room.people[1]
	if not old.has("avatar_id"):
		check(false, "disconnect reservation identity exists")
		return
	registry.leave(2)
	registry.join_room(3, setup.code, "Replacement")
	check(setup.room.people.back().avatar_id != old.avatar_id, "live disconnected duck reserves appearance")
	check(old.disconnect_remaining == 30.0, "identity preserves grace period")
	registry.tick(30.0)
	registry.join_room(4, setup.code, "After round")
	check(setup.room.people.back().avatar_id == old.avatar_id, "offline round reservation released after results")

func test_waiting_spectator_gets_identity_before_start() -> void:
	var setup := setup_room()
	var registry = setup.registry
	# Simulate ten reserved current-round records while capacity remains six in C.
	for i in range(2, 10):
		setup.room.people.append({"id": 100 + i, "peer": 0, "name": "Offline", "scores": {"wins": 0, "kills": 0}, "slot": i, "avatar_id": i, "disconnect_remaining": 30.0})
	setup.room.phase = "playing"
	setup.room.lineup = []
	for person in setup.room.people:
		setup.room.lineup.append(person.id)
	registry.join_room(3, setup.code, "Waiting")
	var waiting: Dictionary = setup.room.people.back()
	check(waiting.get("avatar_id", -2) == -1, "all reserved identities give spectator neutral portrait")
	setup.room.phase = "results"
	registry.start_round(1)
	check(waiting.get("avatar_id", -1) >= 0 and waiting.slot == 2, "waiting spectator assigned before countdown")

func test_history_does_not_steal_active_identity() -> void:
	var setup := setup_room()
	var registry = setup.registry
	registry.leave(2)
	registry.join_room(3, setup.code, "Fresh")
	var old: Dictionary = setup.room.people[1]
	var fresh: Dictionary = setup.room.people[2]
	check(old.get("avatar_id", -2) == fresh.get("avatar_id", -3), "historical cosmetics can be reused")
	registry.join_room(4, setup.code, "Another")
	check(setup.room.people.back().get("avatar_id", -2) != fresh.get("avatar_id", -2), "historical identity cannot steal active identity")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
