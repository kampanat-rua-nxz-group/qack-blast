extends SceneTree

var failures := 0


func _initialize() -> void:
	var scene = load("res://scenes/results.tscn")
	check(scene != null, "results scene loads")
	if scene == null:
		finish()
		return
	var results = scene.instantiate()
	root.add_child(results)
	call_deferred("run_checks", results)


func run_checks(results) -> void:
	var room := {"code": "QACK42", "host": 1, "wall_mode": "night", "people": [
		{"id": 1, "name": "Host", "connected": true, "wins": 2, "kills": 1},
		{"id": 2, "name": "Leader", "connected": true, "wins": 3, "kills": 0},
		{"id": 3, "name": "Offline", "connected": false, "wins": 2, "kills": 5},
		{"id": 4, "name": "Tie A", "connected": false, "wins": 1, "kills": 2},
		{"id": 5, "name": "Tie B", "connected": false, "wins": 1, "kills": 2},
		{"id": 6, "name": "Another", "connected": false, "wins": 0, "kills": 0},
		{"id": 7, "name": "Late", "connected": true, "wins": 0, "kills": 0},
	]}
	results.present(room, {"round_over": false, "result": "PLAYER 1 WINS"}, 1)
	await process_frame
	check(results.find_child("ResultsCard", true, false).get_global_rect().end.y <= 664.0, "results card fits above footer")
	check(results.find_child("Outcome", true, false).get_global_rect().get_center().x > results.find_child("RoomCode", true, false).get_global_rect().get_center().x, "round result stands to the right of room details")
	check(results.find_child("RoomCode", true, false).text == "QACK42", "results show room code")
	check(results.find_child("Outcome", true, false).text == "Round complete", "results wait for final game snapshot")
	check(results.find_child("SelectedMap", true, false).text.contains("Nightfall"), "results show selected map")
	var rows = results.find_child("LeaderboardRows", true, false)
	check(rows.get_child_count() == 7, "leaderboard retains more than six room records")
	var names := []
	for row in rows.get_children():
		names.append(row.get_node("Name").text)
	check(names == ["Leader", "Offline (offline)", "Host (YOU) (host)", "Tie A (offline)", "Tie B (offline)", "Another (offline)", "Late"], "leaderboard sorts wins, kills, then roster order")
	var first_row = rows.get_child(0)
	results.present(room, {"round_over": false, "result": "PLAYER 1 WINS"}, 1)
	check(rows.get_child(0) == first_row, "unchanged roster keeps leaderboard rows stable")
	check(not results.find_child("ChangeMapButton", true, false).disabled and not results.find_child("PlayAgainButton", true, false).disabled, "host can change map and replay")
	test_bot_results_replay(results)
	var copy_button = results.find_child("CopyCodeButton", true, false)
	check(copy_button != null, "results have copy code button")
	copy_button.pressed.emit()
	check(results.find_child("Status", true, false).text.contains("copied"), "copy code confirms action")
	results.present(room, {"round_over": true, "result": "DRAW"}, 2)
	check(results.find_child("Outcome", true, false).text.contains("DRAW"), "results show draw")
	check(not results.find_child("ChangeMapButton", true, false).disabled and results.find_child("PlayAgainButton", true, false).disabled, "guest can inspect maps but cannot replay")
	room.host = 2
	results.present(room, {"round_over": true, "result": "PLAYER 2 WINS"}, 2)
	check(results.find_child("Outcome", true, false).text.contains("PLAYER 2 WINS") and not results.find_child("PlayAgainButton", true, false).disabled, "host transfer updates controls and winner")
	room.people[0].connected = false
	room.people[6].connected = false
	results.present(room, {"round_over": true, "result": "DRAW"}, 2)
	check(results.find_child("PlayAgainButton", true, false).disabled, "replay needs two connected players")
	room.people.append({"id": 8, "name": "New Duck", "connected": true, "wins": 0, "kills": 0})
	results.present(room, {"round_over": true, "result": "DRAW"}, 2)
	check(rows.get_child_count() == 8 and not results.find_child("PlayAgainButton", true, false).disabled, "late join updates leaderboard and replay availability")
	await test_ten_active_with_full_history(results)
	test_long_winner_remains_readable(results, room)
	test_personal_elimination_note_survives_result_race(results)
	finish()


func test_bot_results_replay(results) -> void:
	var room := {"code": "BOT777", "host": 1, "wall_mode": "fixed", "phase": "results", "ready_player_count": 2, "people": [
		{"id": 1, "name": "Solo", "slot": 0, "connected": true, "kind": "human", "wins": 1, "kills": 0},
		{"id": 2, "name": "Bot", "slot": 1, "connected": false, "kind": "bot", "difficulty": "hard", "wins": 0, "kills": 2},
	]}
	results.present(room, {"round_over": true, "result": "PLAYER 1 WINS"}, 1)
	var rows = results.find_child("LeaderboardRows", true, false)
	check(rows.get_child(1).get_node("Name").text.contains("BOT") and rows.get_child(1).get_node("Name").text.contains("Hard") and not rows.get_child(1).get_node("Name").text.contains("offline"), "results labels bot with difficulty instead of offline")
	check(not results.find_child("PlayAgainButton", true, false).disabled, "one human plus ready bot enables play again")
	check(results.has_signal("bot_add_requested") and results.has_signal("bot_remove_requested") and results.has_signal("bot_difficulty_requested"), "results exposes bot management signals")
	results.present(room, {"round_over": true, "result": "PLAYER 1 WINS"}, 99)
	check(results.find_child("RemoveBotButton", true, false).visible == false and results.find_child("BotDifficulty", true, false).disabled and results.find_child("PlayAgainButton", true, false).disabled, "guest cannot manage the bot or replay")
	results.present(room, {"round_over": true, "result": "PLAYER 1 WINS"}, 1)
	var add_requests := []
	var remove_requests := []
	var difficulty_requests := []
	results.bot_add_requested.connect(func(): add_requests.append(true))
	results.bot_remove_requested.connect(func(id): remove_requests.append(id))
	results.bot_difficulty_requested.connect(func(id, difficulty): difficulty_requests.append([id, difficulty]))
	var add_button := results.find_child("AddBotButton", true, false) as Button
	var remove_button := results.find_child("RemoveBotButton", true, false) as Button
	var selector := results.find_child("BotDifficulty", true, false) as OptionButton
	check(add_button != null and remove_button != null and selector != null, "results exposes bot controls")
	check(selector != null and selector.custom_minimum_size.x >= 112.0 and results.find_child("AddBotButton", true, false).get_global_rect().end.x <= results.find_child("ResultsCard", true, false).get_global_rect().end.x, "results bot controls fit the 960 by 720 card")
	if add_button != null and remove_button != null and selector != null:
		add_button.pressed.emit()
		remove_button.pressed.emit()
		selector.select(3)
		selector.item_selected.emit(3)
	check(add_requests.size() == 1 and remove_requests == [2] and difficulty_requests == [[2, "extreme"]], "results bot controls emit target IDs and canonical difficulty")
	room.people[1].difficulty = "extreme"
	results.present(room, {"round_over": true, "result": "PLAYER 1 WINS"}, 1)
	check(add_requests.size() == 1 and remove_requests == [2] and difficulty_requests == [[2, "extreme"]], "snapshot difficulty updates do not emit another request")
	room.phase = "playing"
	results.present(room, {}, 1)
	var playing_remove := results.find_child("RemoveBotButton", true, false) as Button
	var playing_selector := results.find_child("BotDifficulty", true, false) as OptionButton
	check(add_button.disabled and playing_remove.disabled and playing_selector.disabled and results.find_child("PlayAgainButton", true, false).disabled, "results mutations disable during play")
	var old_snapshot := {"code": "OLD123", "host": 1, "phase": "results", "people": [{"id": 1, "name": "Solo", "connected": true, "wins": 0, "kills": 0}, {"id": 3, "name": "Friend", "connected": true, "wins": 0, "kills": 0}]}
	results.present(old_snapshot, {"round_over": true, "result": "DRAW"}, 1)
	check(not results.find_child("PlayAgainButton", true, false).disabled, "old snapshots fall back to connected-human count without errors")


func test_long_winner_remains_readable(results, room: Dictionary) -> void:
	var long_room := room.duplicate(true)
	long_room.people[0].name = "ExtraLongHostDuck"
	long_room.people[0].slot = 0
	results.present(long_room, {"round_over": true, "result": "PLAYER 1 WINS"}, 2)
	var label: Label = results.outcome_label
	var size: int = label.get_theme_font_size("font_size")
	check(size >= 18 and label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= 268.0, "long winner name fits without splitting nickname")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Results UI checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func test_ten_active_with_full_history(results) -> void:
	var people := []
	for i in range(16):
		people.append({"id": i+1,"name": "FullHistoricalNickname%d" % i,"connected": i<10,"avatar_id": i%10,"wins": i,"kills": 16-i})
	var room := {"code":"QACK42","host": 1,"wall_mode":"fixed","phase":"results","people": people}
	results.present(room,{"round_over":true,"result":"DRAW"},3)
	await process_frame
	await process_frame
	check(results.leaderboard_rows.get_child_count() == 16, "ten active plus offline history retained")
	var markers := 0
	for row in results.leaderboard_rows.get_children():
		if row.get_node("Name").text.contains("YOU"):
			markers += 1
		check(row.get_node_or_null("Portrait") != null, "every historical result has shared portrait")
		check(not row.get_node("Name").tooltip_text.is_empty(), "full historical names available")
	check(markers == 1, "results identify exactly one local participant")
	check(results.leaderboard_rows.get_child(0).get_node("Wins").text == "15", "full history keeps rank ordering")
	check(results.find_child("PlayAgainButton",true,false).get_global_rect().end.y <= 644, "results controls clear footer with history")


func note_room() -> Dictionary:
	return {"code": "QACK42", "host": 1, "wall_mode": "fixed", "phase": "results", "people": [
		{"id": 1, "name": "Ann", "slot": 0, "connected": true, "wins": 1, "kills": 0},
		{"id": 2, "name": "Bo", "slot": 1, "connected": true, "wins": 0, "kills": 1},
		{"id": 3, "name": "Late", "slot": -1, "connected": true, "wins": 0, "kills": 0},
	]}


func note_game(result: String, cause: Dictionary) -> Dictionary:
	return {"round_over": true, "result": result, "players": [
		{"alive": result == "PLAYER 1 WINS", "elimination_cause": {}},
		{"alive": false, "elimination_cause": cause},
	]}


func test_personal_elimination_note_survives_result_race(results) -> void:
	var room := note_room()
	var note: Label = results.find_child("PersonalNote", true, false)
	check(note != null, "results have a personal note label")
	if note == null:
		return
	var cause := {"kind": "other_bomb", "owner": 0}
	# Loss: cause comes from the snapshot alone.
	results.present(room, note_game("PLAYER 1 WINS", cause), 2)
	check(note.visible and note.text.begins_with("OUT") and note.text.contains("Ann"), "loser sees personal cause from snapshot")
	check(not note.text.to_upper().contains("YOU LOSE") and not note.text.to_upper().contains("KILLED BY"), "no false outcome or credited killer wording")
	# Results phase arrives before the final game snapshot: event text bridges the gap.
	results.present(room, {}, 2, "OUT: Ann's blast")
	check(note.visible and note.text == "OUT: Ann's blast", "event cause persists when game state is not yet present")
	results.present(room, note_game("PLAYER 1 WINS", cause), 2, "OUT: Ann's blast")
	check(note.text.begins_with("OUT"), "final game message keeps the cause")
	# Win: no elimination text, no loss wording.
	results.present(room, note_game("PLAYER 1 WINS", cause), 1)
	check(note.visible and note.text.to_upper().contains("WON") and not note.text.begins_with("OUT"), "winner sees a win note")
	# Draw: eliminated player still sees why they were out.
	results.present(room, note_game("DRAW", {"kind": "ambiguous_blasts", "owner": -1}), 2)
	check(note.text.begins_with("OUT"), "draw keeps personal cause")
	# Spectator: no personal outcome at all.
	results.present(room, note_game("PLAYER 1 WINS", cause), 3, "OUT: stale")
	check(not note.visible or note.text.is_empty(), "spectator has no personal outcome or cause")
	results.present(room, {}, 3)
	check(not note.visible or note.text.is_empty(), "spectator without game has no note")
