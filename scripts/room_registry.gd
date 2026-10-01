extends RefCounted

const ArenaGame = preload("res://scripts/arena_game.gd")
const CharacterCatalog = preload("res://scripts/character_catalog.gd")
const BotProfiles = preload("res://scripts/bot_profiles.gd")
const BotObservation = preload("res://scripts/bot_observation.gd")
const BotController = preload("res://scripts/bot_controller.gd")
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_CONNECTED = 10
const DISCONNECT_GRACE = 30.0
const MAX_ROOM_EVENTS = 256

var rng := RandomNumberGenerator.new()
var rooms: Dictionary = {}
var peer_rooms: Dictionary = {}
var next_person_id := 1


func create_room(peer_id: int, nickname: String) -> Dictionary:
	if peer_rooms.has(peer_id):
		return {"ok": false, "error": "Already in a room"}
	var code := make_code()
	rooms[code] = {"code": code, "host": 0, "people": [], "phase": "lobby", "countdown_remaining": 0.0, "notice": "", "round_id": 0, "snapshot_seq": 0, "wall_mode": "fixed", "game": null, "events": [], "lineup": [], "directions": [], "plants": [], "move_presses": [], "input_remaining": [], "bot_controllers": {}, "bot_memories": {}}
	return join_room(peer_id, code, nickname)


func join_room(peer_id: int, code: String, nickname: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if peer_rooms.has(peer_id):
		return {"ok": false, "error": "Already in a room"}
	if not rooms.has(code):
		return {"ok": false, "error": "Room not found"}
	var room: Dictionary = rooms[code]
	if admission_count(room) >= MAX_CONNECTED:
		return {"ok": false, "error": "Room is full"}
	var base := nickname.strip_edges().substr(0, 20)
	if base.is_empty():
		base = "Player"
	var used := {}
	for person in room.people:
		used[person.name] = true
	var name := base
	var suffix := 1
	while used.has(name):
		name = "%s#%d" % [base, suffix]
		suffix += 1
	var person := {"id": next_person_id, "peer": peer_id, "name": name, "scores": {"wins": 0, "kills": 0}, "slot": -1, "disconnect_remaining": 0.0, "avatar_id": available_avatar(room), "kind": "human", "difficulty": ""}
	next_person_id += 1
	room.people.append(person)
	peer_rooms[peer_id] = code
	if room.host == 0:
		room.host = person.id
	return {"ok": true, "code": code, "person_id": person.id, "name": name}


func admission_count(room: Dictionary) -> int:
	var count := 0
	for person in room.people:
		if person.get("kind", "human") == "bot" or person.peer != 0:
			count += 1
	return count


func ready_people(room: Dictionary) -> Array:
	var ready: Array = []
	for person in room.people:
		if person.get("kind", "human") == "bot" or person.peer != 0:
			ready.append(person)
	return ready


func add_bot(peer_id: int, difficulty: String = "medium") -> Dictionary:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase not in ["lobby", "results"]:
		return {"ok": false, "error": "Bots can only be changed between rounds"}
	var caller := person_for_peer(room, peer_id)
	if caller.is_empty() or caller.id != room.host:
		return {"ok": false, "error": "Only the host can manage the bot"}
	if not BotProfiles.is_valid(difficulty):
		return {"ok": false, "error": "Unknown bot difficulty"}
	for person in room.people:
		if person.get("kind", "human") == "bot":
			return {"ok": false, "error": "Room already has a bot"}
	if admission_count(room) >= MAX_CONNECTED:
		return {"ok": false, "error": "Room is full"}
	var used := {}
	for person in room.people:
		used[person.name] = true
	var name := "Bot"
	var suffix := 1
	while used.has(name):
		name = "Bot#%d" % suffix
		suffix += 1
	var bot := {"id": next_person_id, "peer": 0, "name": name, "scores": {"wins": 0, "kills": 0}, "slot": -1, "disconnect_remaining": 0.0, "avatar_id": available_avatar(room), "kind": "bot", "difficulty": difficulty}
	next_person_id += 1
	room.people.append(bot)
	return {"ok": true, "person_id": bot.id}


func remove_bot(peer_id: int, person_id: int) -> Dictionary:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase not in ["lobby", "results"]:
		return {"ok": false, "error": "Bots can only be changed between rounds"}
	var caller := person_for_peer(room, peer_id)
	if caller.is_empty() or caller.id != room.host:
		return {"ok": false, "error": "Only the host can manage the bot"}
	for index in range(room.people.size()):
		var person: Dictionary = room.people[index]
		if person.id == person_id and person.get("kind", "human") == "bot":
			room.bot_controllers.erase(person_id)
			room.bot_memories.erase(person_id)
			room.people.remove_at(index)
			return {"ok": true}
	return {"ok": false, "error": "Bot not found"}


func set_bot_difficulty(peer_id: int, person_id: int, difficulty: String) -> Dictionary:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase not in ["lobby", "results"]:
		return {"ok": false, "error": "Bots can only be changed between rounds"}
	var caller := person_for_peer(room, peer_id)
	if caller.is_empty() or caller.id != room.host:
		return {"ok": false, "error": "Only the host can manage the bot"}
	if not BotProfiles.is_valid(difficulty):
		return {"ok": false, "error": "Unknown bot difficulty"}
	for person in room.people:
		if person.id == person_id and person.get("kind", "human") == "bot":
			person.difficulty = difficulty
			return {"ok": true}
	return {"ok": false, "error": "Bot not found"}


func available_avatar(room: Dictionary) -> int:
	var reserved := {}
	for person in room.people:
		if person.peer != 0 or person.get("kind", "human") == "bot" or (room.phase in ["countdown", "playing"] and person.id in room.lineup):
			reserved[person.get("avatar_id", -1)] = true
	for avatar_id in range(10):
		if not reserved.has(avatar_id):
			return avatar_id
	return -1


func leave(peer_id: int) -> void:
	if not peer_rooms.has(peer_id):
		return
	var code: String = peer_rooms[peer_id]
	peer_rooms.erase(peer_id)
	var room: Dictionary = rooms[code]
	var leaving: Dictionary = person_for_peer(room, peer_id)
	leaving.peer = 0
	if room.phase == "countdown" and leaving.id in room.lineup:
		cancel_countdown(room)
	if room.phase == "playing" and leaving.slot >= 0 and room.game.players[leaving.slot].alive:
		leaving.disconnect_remaining = DISCONNECT_GRACE
		room.directions[leaving.slot] = Vector2.ZERO
		room.plants[leaving.slot] = false
		room.move_presses[leaving.slot] = Vector2.ZERO
		room.input_remaining[leaving.slot] = 0.0
	var connected: Array = []
	for person in room.people:
		if person.peer != 0:
			connected.append(person)
	if connected.is_empty():
		rooms.erase(code)
	elif room.host == leaving.id:
		room.host = connected[0].id


func choose_map(peer_id: int, mode: String) -> bool:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase in ["countdown", "playing"] or not mode in ArenaGame.MAP_MODES:
		return false
	if person_for_peer(room, peer_id).id != room.host:
		return false
	room.wall_mode = mode
	return true


func start_round(peer_id: int) -> bool:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase in ["countdown", "playing"] or person_for_peer(room, peer_id).id != room.host:
		return false
	var connected: Array = []
	for person in room.people:
		if person.peer != 0 or person.get("kind", "human") == "bot":
			connected.append(person)
		person.slot = -1
	var human_count := 0
	for person in connected:
		if person.get("kind", "human") == "human":
			human_count += 1
	if connected.size() < 2 or connected.size() > MAX_CONNECTED or human_count < 1:
		return false
	for person in connected:
		if person.avatar_id < 0:
			person.avatar_id = available_avatar(room)
	room.lineup = []
	room.directions = []
	room.plants = []
	room.move_presses = []
	room.input_remaining = []
	var game = ArenaGame.new()
	game.rng.randomize()
	game.player_count = connected.size()
	game.wall_mode = room.wall_mode
	game.scores.clear()
	for i in range(connected.size()):
		var person: Dictionary = connected[i]
		person.slot = i
		person.disconnect_remaining = 0.0
		room.lineup.append(person.id)
		room.directions.append(Vector2.ZERO)
		room.plants.append(false)
		room.move_presses.append(Vector2.ZERO)
		room.input_remaining.append(0.0)
		game.scores.append(person.scores)
	room.round_id += 1
	game.new_round()
	for i in range(connected.size()):
		game.players[i]["avatar_id"] = connected[i].avatar_id
	room.game = game
	room.bot_controllers.clear()
	room.bot_memories.clear()
	for i in range(connected.size()):
		var person: Dictionary = connected[i]
		if person.get("kind", "human") == "bot":
			var controller = BotController.new()
			controller.configure(i, person.difficulty, rng.randi())
			room.bot_controllers[person.id] = controller
			room.bot_memories[person.id] = {}
	room.events.clear()
	room.phase = "countdown"
	room.countdown_remaining = 3.0
	room.notice = ""
	return true


func set_input(peer_id: int, direction: Vector2, plant: bool, move_press: Vector2 = Vector2.ZERO) -> bool:
	var room := room_for_peer(peer_id)
	if room.is_empty() or room.phase != "playing":
		return false
	var person := person_for_peer(room, peer_id)
	if person.slot < 0 or not room.game.players[person.slot].alive:
		return false
	if direction not in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		return false
	if move_press not in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		return false
	room.directions[person.slot] = direction
	# Neutral releases keep the latest press until the simulation consumes it.
	if move_press != Vector2.ZERO:
		room.move_presses[person.slot] = move_press
	room.input_remaining[person.slot] = 0.2
	if plant:
		room.plants[person.slot] = true
	return true


func cancel_countdown(room: Dictionary) -> void:
	room.phase = "lobby"
	room.countdown_remaining = 0.0
	room.notice = "Countdown cancelled: a player left. Waiting for the host to start again."
	room.game = null
	room.lineup.clear()
	room.directions.clear()
	room.plants.clear()
	room.move_presses.clear()
	room.input_remaining.clear()
	room.bot_controllers.clear()
	room.bot_memories.clear()
	for person in room.people:
		person.slot = -1
		person.disconnect_remaining = 0.0


func tick(delta: float) -> void:
	for room in rooms.values():
		var play_delta := delta
		if room.phase == "countdown":
			play_delta = maxf(0.0, delta - room.countdown_remaining)
			room.countdown_remaining = maxf(0.0, room.countdown_remaining - delta)
			if room.countdown_remaining > 0.0:
				continue
			room.phase = "playing"
			room.plants.fill(false)
			room.move_presses.fill(Vector2.ZERO)
		if room.phase != "playing":
			continue
		for i in range(room.input_remaining.size()):
			if i < room.lineup.size() and person_for_id(room, room.lineup[i]).get("kind", "human") == "bot":
				continue
			room.input_remaining[i] -= play_delta
			if room.input_remaining[i] <= 0.0:
				room.directions[i] = Vector2.ZERO
				room.move_presses[i] = Vector2.ZERO
		for person in room.people:
			if person.peer == 0 and person.slot >= 0 and person.disconnect_remaining > 0.0:
				person.disconnect_remaining -= play_delta
				if person.disconnect_remaining <= 0.0:
					room.game.eliminate_disconnected(person.slot)
		if room.phase == "playing":
			for person_id in room.bot_controllers:
				var bot_person := person_for_id(room, person_id)
				if bot_person.is_empty() or bot_person.slot < 0 or not room.game.players[bot_person.slot].alive:
					if not bot_person.is_empty() and bot_person.slot >= 0:
						room.directions[bot_person.slot] = Vector2.ZERO
						room.plants[bot_person.slot] = false
						room.move_presses[bot_person.slot] = Vector2.ZERO
					continue
				var observation := BotObservation.capture(room.game, bot_person.slot, room.bot_memories[person_id])
				var controller = room.bot_controllers[person_id]
				var previous_decisions: int = controller.diagnostics().decision_count
				var command: Dictionary = controller.advance(play_delta, observation)
				if controller.diagnostics().decision_count != previous_decisions:
					room.directions[bot_person.slot] = command.direction
				room.move_presses[bot_person.slot] = command.move_press
				room.plants[bot_person.slot] = command.plant
		room.game.step(play_delta, room.directions, room.plants, room.move_presses)
		room.events.append_array(room.game.take_events())
		if room.events.size() > MAX_ROOM_EVENTS:
			room.events = room.events.slice(room.events.size() - MAX_ROOM_EVENTS)
		room.move_presses.fill(Vector2.ZERO)
		for i in range(room.plants.size()):
			room.plants[i] = false
		if room.game.round_over:
			room.phase = "results"
			for person_id in room.bot_controllers:
				room.bot_controllers[person_id].reset()
			room.bot_controllers.clear()
			room.bot_memories.clear()
			for i in range(room.directions.size()):
				room.directions[i] = Vector2.ZERO


func take_room_events(room: Dictionary) -> Array:
	var events: Array = room.events
	room.events = []
	return events


func event_cursor(room: Dictionary) -> int:
	return room.game.event_counter if room.game != null else 0


func room_for_peer(peer_id: int) -> Dictionary:
	if not peer_rooms.has(peer_id):
		return {}
	return rooms.get(peer_rooms[peer_id], {})


func person_for_peer(room: Dictionary, peer_id: int) -> Dictionary:
	for person in room.people:
		if person.peer == peer_id:
			return person
	return {}


func person_for_id(room: Dictionary, person_id: int) -> Dictionary:
	for person in room.people:
		if person.id == person_id:
			return person
	return {}


func room_view(room: Dictionary) -> Dictionary:
	var people := []
	for person in room.people:
		people.append({"id": person.id, "name": person.name, "connected": person.peer != 0, "kind": person.get("kind", "human"), "difficulty": person.get("difficulty", ""), "slot": person.slot, "avatar_id": person.avatar_id, "wins": person.scores.wins, "kills": person.scores.kills})
	return {"type": "room", "code": room.code, "host": room.host, "phase": room.phase, "countdown_remaining": room.countdown_remaining, "notice": room.notice, "round_id": room.round_id, "event_cursor": event_cursor(room), "wall_mode": room.wall_mode, "ready_player_count": ready_people(room).size(), "people": people}


func game_view(room: Dictionary) -> Dictionary:
	room.snapshot_seq += 1
	var game = room.game
	var players := []
	for i in range(game.players.size()):
		var player: Dictionary = game.players[i]
		var target: Vector2 = game.move_targets[i]
		players.append({"pos": [player.pos.x, player.pos.y], "move_target": [target.x, target.y], "sliding": game.is_sliding(i), "alive": player.alive, "bomb_limit": player.bomb_limit, "range": player.range, "vision": player.vision, "speed_bonus": player.speed_bonus, "can_kick": player.can_kick, "facing": player.facing, "avatar_id": player.get("avatar_id", i), "elimination_cause": player.get("elimination_cause", {}).duplicate(true)})
	var bombs := []
	for bomb in game.bombs:
		var kick_direction: Vector2i = bomb.get("kick_direction", Vector2i.ZERO)
		bombs.append({"tile": [bomb.tile.x, bomb.tile.y], "owner": bomb.owner, "time": bomb.time, "danger": bomb.get("danger", false), "kick_direction": [kick_direction.x, kick_direction.y], "kick_progress": bomb.get("kick_progress", 0.0)})
	var flames := []
	for flame in game.flames:
		flames.append({"tile": [flame.tile.x, flame.tile.y], "owner": flame.owner, "time": flame.time, "kind": flame.get("kind", "")})
	var pickups := []
	for tile in game.pickups:
		pickups.append({"tile": [tile.x, tile.y], "kind": game.pickups[tile]})
	var hazards := []
	for hazard in game.hazards:
		var tiles := []
		for tile in hazard.tiles:
			tiles.append([tile.x, tile.y])
		hazards.append({"kind": hazard.kind, "tiles": tiles, "time": hazard.time})
	return {"type": "game", "round_id": room.round_id, "snapshot_seq": room.snapshot_seq, "event_cursor": game.event_counter, "geometry": {"width": game.WIDTH, "height": game.HEIGHT, "cell": game.CELL, "origin": [game.ORIGIN.x, game.ORIGIN.y]}, "board": game.board, "terrain": game.terrain, "players": players, "bombs": bombs, "hazards": hazards, "flames": flames, "pickups": pickups, "scores": game.scores, "round_elapsed": game.round_elapsed, "round_over": game.round_over, "result": game.result, "wall_mode": game.wall_mode}


func make_code() -> String:
	while true:
		var code := ""
		for i in range(6):
			code += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not rooms.has(code):
			return code
	return ""
