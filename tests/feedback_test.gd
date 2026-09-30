extends SceneTree

const GameFeedback = preload("res://scripts/game_feedback.gd")
const ArenaGame = preload("res://scripts/arena_game.gd")

var failures := 0


func _initialize() -> void:
	test_event_is_presented_once()
	test_old_round_event_is_ignored()
	test_late_join_does_not_replay_history()
	test_new_round_events_wait_for_matching_state()
	test_muted_events_keep_visual_feedback()
	test_night_hidden_event_has_no_positional_cue()
	test_personal_elimination_and_causes()
	test_upgrade_notices()
	test_outcomes_do_not_assign_spectator_result()
	test_voice_cap_and_bounded_state()
	test_urgency_only_in_final_window()
	test_transient_effects_clear_on_reset()
	test_engine_events_drive_feedback()
	test_web_audio_waits_for_gesture()
	finish()


func make() -> GameFeedback:
	var feedback := GameFeedback.new()
	feedback.persist = false
	return feedback


func context(viewer := 0, extra := {}) -> Dictionary:
	var result := {"viewer_slot": viewer, "wall_mode": "fixed", "names": ["Ann", "Bo", "Cy"]}
	result.merge(extra, true)
	return result


func placed(id: int, tile := [3, 3], owner := 1) -> Dictionary:
	return {"event_id": id, "kind": "bomb_placed", "tile": tile, "owner": owner, "elapsed": 1.0}


func exploded(id: int, tile := [3, 3]) -> Dictionary:
	return {"event_id": id, "kind": "bomb_exploded", "tile": tile, "owner": 1, "danger": false, "elapsed": 1.0}


func eliminated(id: int, player: int, kind := "other_bomb", owner := 1) -> Dictionary:
	return {"event_id": id, "kind": "player_eliminated", "player": player, "tile": [4, 4], "cause": {"kind": kind, "owner": owner}, "elapsed": 2.0}


func test_event_is_presented_once() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	feedback.consume_events(1, [placed(1)], context())
	feedback.consume_events(1, [placed(1), placed(1)], context())
	check(feedback.cues == ["place"], "duplicate (round, event) presents once")
	feedback.consume_events(1, [placed(2)], context())
	check(feedback.cues == ["place", "place"], "next event id still presents")


func test_old_round_event_is_ignored() -> void:
	var feedback := make()
	feedback.reset(2, 0)
	feedback.consume_events(1, [exploded(1), eliminated(2, 0)], context())
	check(feedback.cues.is_empty() and feedback.effects.is_empty() and feedback.personal_cause.is_empty(), "older round events produce nothing")


func test_late_join_does_not_replay_history() -> void:
	var feedback := make()
	feedback.reset(3, 5)
	feedback.consume_events(3, [exploded(4), {"event_id": 5, "kind": "round_ended", "result": "DRAW", "winner": -1}, exploded(6)], context())
	check(feedback.cues == ["explode"], "events at or below the joined cursor are skipped, later ones play")
	check(feedback.outcome.is_empty(), "finished-round outcome is not replayed after joining")


func test_new_round_events_wait_for_matching_state() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	feedback.consume_events(2, [exploded(1)], context())
	check(feedback.cues.is_empty(), "future round events wait")
	feedback.reset(2, 0)
	check(feedback.cues == ["explode"], "queued events present once matching state arrives")
	feedback.consume_events(2, [exploded(1)], context())
	check(feedback.cues == ["explode"], "queued event is not presented twice")
	var flood := make()
	flood.reset(0, 0)
	for round in range(1, 40):
		flood.consume_events(round, [exploded(1)], context())
	check(flood.pending_count() <= GameFeedback.MAX_PENDING_BATCHES, "queued future batches stay bounded")


func test_muted_events_keep_visual_feedback() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	feedback.set_muted(true)
	feedback.consume_events(1, [eliminated(1, 1), {"event_id": 2, "kind": "pickup_collected", "player": 0, "tile": [1, 1], "pickup": ArenaGame.PICKUP_BOMB_CAPACITY, "granted": true}], context())
	check(feedback.cues.is_empty(), "muted plays no sound")
	check(not feedback.effects.is_empty() and feedback.notice == "BOMB +1", "muted still shows elimination effect and upgrade notice")
	feedback.set_muted(false)
	feedback.consume_events(1, [exploded(3)], context())
	check(feedback.cues == ["explode"], "unmuting resumes sound")


func test_night_hidden_event_has_no_positional_cue() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	var hidden := func(_tile: Array) -> bool: return false
	var night := context(0, {"wall_mode": "night", "visible": hidden})
	feedback.consume_events(1, [placed(1), exploded(2), eliminated(3, 2), {"event_id": 4, "kind": "pickup_collected", "player": 2, "tile": [5, 5], "pickup": 0, "granted": true}], night)
	check(feedback.cues.is_empty() and feedback.effects.is_empty(), "hidden Nightfall events add no sound, effect, or marker")
	feedback.consume_events(1, [{"event_id": 5, "kind": "pickup_collected", "player": 0, "tile": [5, 5], "pickup": ArenaGame.PICKUP_VISION, "granted": true}], night)
	check(feedback.cues == ["pickup"] and feedback.notice == "SIGHT +1", "own pickup stays available in Nightfall")
	feedback.play_cue("countdown")
	check(feedback.cues.back() == "countdown", "global countdown cue stays available")
	var seen := make()
	seen.reset(1, 0)
	seen.consume_events(1, [exploded(1)], context(0, {"wall_mode": "night", "visible": func(_tile: Array) -> bool: return true}))
	check(seen.cues == ["explode"], "visible Nightfall tile still sounds")


func test_personal_elimination_and_causes() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	feedback.consume_events(1, [eliminated(1, 0, "other_bomb", 1)], context())
	check(feedback.cues == ["eliminate"] and feedback.personal_cause.contains("Bo") and feedback.personal_cause.begins_with("OUT"), "personal elimination names cause, not a credited kill")
	check(not feedback.personal_cause.to_lower().contains("kill"), "wording does not claim a kill")
	check(GameFeedback.cause_text({"kind": "own_bomb", "owner": 0}, []).to_lower().contains("own"), "own bomb")
	for kind in ["ambiguous_blasts", "danger_bomb", "flood", "blizzard", "random_burst", "closing_walls", "disconnect"]:
		check(not GameFeedback.cause_text({"kind": kind, "owner": -1}, []).is_empty(), "cause text for " + kind)
	check(GameFeedback.cause_text({}, []).is_empty(), "missing cause yields no invented text")
	var other := make()
	other.reset(1, 0)
	other.consume_events(1, [eliminated(1, 2)], context(0))
	check(other.personal_cause.is_empty() and not other.effects.is_empty(), "another duck's elimination is an effect only")


func test_upgrade_notices() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	var cases := [[ArenaGame.PICKUP_BOMB_CAPACITY, true, "BOMB +1"], [ArenaGame.PICKUP_BLAST_RANGE, true, "FIRE +1"], [ArenaGame.PICKUP_SPEED, true, "SPEED UP"], [ArenaGame.PICKUP_BOMB_KICK, true, "BOMB KICK"], [ArenaGame.PICKUP_BOMB_CAPACITY, false, "BOMB MAX"], [ArenaGame.PICKUP_MYSTERY, false, "MYSTERY: NO CHANGE"], [ArenaGame.PICKUP_MYSTERY, true, "MYSTERY UPGRADE"]]
	var id := 0
	for entry in cases:
		id += 1
		feedback.consume_events(1, [{"event_id": id, "kind": "pickup_collected", "player": 0, "tile": [1, 1], "pickup": entry[0], "granted": entry[1]}], context())
		check(feedback.notice == entry[2], "upgrade notice %s (got %s)" % [entry[2], feedback.notice])
	feedback.tick(GameFeedback.NOTICE_SECONDS + 0.1)
	check(feedback.notice.is_empty(), "notice expires")


func test_outcomes_do_not_assign_spectator_result() -> void:
	var win := make()
	win.reset(1, 0)
	win.consume_events(1, [{"event_id": 1, "kind": "round_ended", "result": "PLAYER 1 WINS", "winner": 0}], context(0))
	check(win.outcome == "win" and win.cues == ["win"], "winner hears win")
	var loss := make()
	loss.reset(1, 0)
	loss.consume_events(1, [{"event_id": 1, "kind": "round_ended", "result": "PLAYER 1 WINS", "winner": 0}], context(1))
	check(loss.outcome == "loss" and loss.cues == ["loss"], "loser hears loss")
	var draw := make()
	draw.reset(1, 0)
	draw.consume_events(1, [{"event_id": 1, "kind": "round_ended", "result": "DRAW", "winner": -1}], context(1))
	check(draw.outcome == "draw" and draw.cues == ["draw"], "draw cue")
	var spectator := make()
	spectator.reset(1, 0)
	spectator.consume_events(1, [{"event_id": 1, "kind": "round_ended", "result": "PLAYER 1 WINS", "winner": 0}], context(-1))
	check(spectator.outcome.is_empty() and spectator.cues.is_empty(), "spectator gets no personal outcome")


func test_voice_cap_and_bounded_state() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	var batch: Array = []
	for i in range(1, 60):
		batch.append(exploded(i, [i % 10, 2]))
	feedback.consume_events(1, batch, context())
	check(feedback.voice_count() <= GameFeedback.MAX_VOICES, "overlapping voices are capped")
	check(feedback.cues.size() <= GameFeedback.MAX_LOG and feedback.effects.size() <= GameFeedback.MAX_EFFECTS, "logs and effects stay bounded")
	feedback.tick(5.0)
	check(feedback.voice_count() == 0, "voices finish")
	var big: Array = []
	for i in range(1000, 3000):
		big.append(placed(i))
	feedback.consume_events(1, big, context())
	check(feedback.seen_count() <= GameFeedback.MAX_SEEN, "dedupe memory stays bounded")


func test_urgency_only_in_final_window() -> void:
	check(GameFeedback.urgency(2.5) == 0.0 and GameFeedback.urgency(0.61) == 0.0, "no urgency before the final 0.6 seconds")
	check(GameFeedback.urgency(0.6) == 0.0 and GameFeedback.urgency(0.3) > 0.0 and GameFeedback.urgency(0.0) == 1.0, "urgency ramps to full at detonation")
	check(GameFeedback.urgency(0.1) > GameFeedback.urgency(0.4), "urgency increases as time runs out")


func test_transient_effects_clear_on_reset() -> void:
	var feedback := make()
	feedback.reset(1, 0)
	feedback.consume_events(1, [eliminated(1, 0), eliminated(2, 2)], context())
	check(not feedback.effects.is_empty() and not feedback.personal_cause.is_empty(), "effects present")
	feedback.reset(2, 0)
	check(feedback.effects.is_empty() and feedback.notice.is_empty() and feedback.personal_cause.is_empty(), "new round clears transient feedback")
	feedback.consume_events(2, [eliminated(1, 0)], context())
	feedback.clear()
	check(feedback.round_id == -1 and feedback.effects.is_empty() and feedback.personal_cause.is_empty() and feedback.pending_count() == 0, "clear resets everything for room changes")
	feedback.consume_events(1, [exploded(1)], context())
	check(feedback.cues.is_empty(), "cleared feedback holds events until a round is reset")


func test_engine_events_drive_feedback() -> void:
	var game := ArenaGame.new()
	game.rng.seed = 7
	game.new_round()
	var feedback := make()
	feedback.reset(1, 0)
	game.place_bomb(0)
	feedback.consume_events(1, game.take_events(), context(-1, {"local_play": true}))
	check(feedback.cues == ["place"], "engine placement event yields sound")


func test_web_audio_waits_for_gesture() -> void:
	var feedback := make()
	feedback.unlocked = false
	feedback.reset(1, 0)
	feedback.consume_events(1, [exploded(1)], context())
	check(feedback.cues.is_empty(), "no audio before a user gesture")
	feedback.unlock()
	feedback.consume_events(1, [exploded(2)], context())
	check(feedback.cues == ["explode"], "audio after gesture")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func finish() -> void:
	print("Feedback checks: %d failure(s)" % failures)
	quit(1 if failures else 0)
