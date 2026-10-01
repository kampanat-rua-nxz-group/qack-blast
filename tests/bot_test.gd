extends SceneTree

var failures := 0


func _initialize() -> void:
	test_profiles()
	print("Bot checks: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func test_profiles() -> void:
	var expected := {"easy": [0.60, 0.90, 0.0, 1], "medium": [0.30, 0.45, 0.0, 4], "hard": [0.15, 0.25, 0.50, 8], "extreme": [0.08, 0.15, 1.00, 12]}
	var profiles = load("res://scripts/bot_profiles.gd")
	check(profiles != null, "profile contract exists")
	if profiles == null:
		return
	for id in expected:
		var p: Dictionary = profiles.get_profile(id)
		check([p.interval_min, p.interval_max, p.prediction_seconds, p.candidate_limit] == expected[id], "exact profile " + id)
		check(profiles.is_valid(id), "valid canonical identifier " + id)
		p.interval_min = -1.0
		check(profiles.get_profile(id).interval_min == expected[id][0], "returned profile is detached " + id)
	check(profiles.get_profile("extream").is_empty(), "reject misspelled identifier")
	check(not profiles.is_valid("unknown"), "reject unknown identifier")
