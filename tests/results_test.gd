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
	check(names == ["Leader", "Offline (offline)", "Host (host)", "Tie A (offline)", "Tie B (offline)", "Another (offline)", "Late"], "leaderboard sorts wins, kills, then roster order")
	var first_row = rows.get_child(0)
	results.present(room, {"round_over": false, "result": "PLAYER 1 WINS"}, 1)
	check(rows.get_child(0) == first_row, "unchanged roster keeps leaderboard rows stable")
	check(not results.find_child("ChangeMapButton", true, false).disabled and not results.find_child("PlayAgainButton", true, false).disabled, "host can change map and replay")
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
	test_long_winner_remains_readable(results, room)
	finish()


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
