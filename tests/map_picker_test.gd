extends SceneTree

var failures := 0
var selections: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	check(ResourceLoader.exists("res://scripts/map_catalog.gd"), "map catalog exists")
	check(ResourceLoader.exists("res://scripts/map_picker.gd"), "map picker exists")
	if failures:
		finish()
		return
	var catalog = load("res://scripts/map_catalog.gd")
	var expected := {"fixed": "Classic", "random": "Random", "pond": "Lily Pond", "frost": "Frost Garden", "night": "Nightfall"}
	for mode in expected:
		var entry: Dictionary = catalog.describe(mode)
		check(entry.name == expected[mode], "catalog names " + mode)
		for key in ["terrain_text", "pickup_text", "hazard_text", "preview"]:
			check(entry.has(key) and not entry[key].is_empty(), "catalog explains " + mode + " " + key)
	check(catalog.describe("frost").terrain_text.contains("one extra tile") and catalog.describe("frost").pickup_text.contains("Kick"), "Frost accurately explains slide and kick")
	check(catalog.describe("night").terrain_text.contains("1:00") and catalog.describe("night").terrain_text.contains("2:00"), "Nightfall explains timed reshuffles")
	check(catalog.describe("random").preview_text.contains("example"), "Random preview explicitly avoids promising upcoming layout")
	var picker = load("res://scripts/map_picker.gd").new()
	root.add_child(picker)
	picker.map_selected.connect(func(mode): selections.append(mode))
	picker.present("fixed", false)
	picker.inspect("frost")
	picker.select_button.pressed.emit()
	check(selections.is_empty() and picker.selected_mode == "fixed" and picker.title_label.text == "Frost Garden", "guest inspects without commands or changing selection")
	picker.present("fixed", true)
	picker.inspect("night")
	picker.select_button.pressed.emit()
	check(selections == ["night"] and picker.selected_mode == "fixed", "host requests map while selection waits for server")
	picker.present("fixed", true)
	check(picker.selected_label.text.contains("Classic"), "rejected request retains authoritative selected label")
	picker.present("pond", true)
	check(picker.selected_label.text.contains("Lily Pond"), "authoritative room update changes selected label")
	var game = load("res://scripts/arena_game.gd").new()
	game.rng.seed = 123
	game.new_round()
	var before: Array = game.board.duplicate(true)
	var rng_state: int = game.rng.state
	for mode in expected:
		picker.inspect(mode)
		catalog.describe(mode)
	check(game.rng.state == rng_state and game.board == before, "preview inspection does not consume game RNG or mutate map")
	finish()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func finish() -> void:
	print("Map picker checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
