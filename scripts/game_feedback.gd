extends RefCounted
## Client-side presenter for authoritative game events: sounds, notices and
## elimination effects. Holds no gameplay rules; the server owns all state.

const ArenaGame = preload("res://scripts/arena_game.gd")

const MAX_PENDING_BATCHES := 4
const MAX_VOICES := 6
const MAX_LOG := 64
const MAX_EFFECTS := 16
const MAX_SEEN := 512
const NOTICE_SECONDS := 1.6
const EFFECT_SECONDS := 0.9
const VOICE_SECONDS := 1.2
const URGENCY_WINDOW := 0.6
const AUDIO_DIR := "res://assets/audio/"
const PREFERENCE_PATH := "user://feedback.cfg"
const PREFERENCE_SECTION := "audio"
const NIGHT_MODE := "night"
const EVENT_CUES := {"bomb_placed": "place", "bomb_exploded": "explode", "pickup_collected": "pickup", "player_eliminated": "eliminate"}
const PICKUP_NOTICES := {
	ArenaGame.PICKUP_BLAST_RANGE: "FIRE +1",
	ArenaGame.PICKUP_VISION: "SIGHT +1",
	ArenaGame.PICKUP_SPEED: "SPEED UP",
	ArenaGame.PICKUP_BOMB_KICK: "BOMB KICK",
}
const CAUSE_TEXT := {
	"own_bomb": "your own bomb",
	"ambiguous_blasts": "overlapping blasts",
	"danger_bomb": "a danger bomb",
	"flood": "the flood",
	"blizzard": "the blizzard",
	"random_burst": "a random burst",
	"closing_walls": "the closing walls",
	"disconnect": "a disconnect",
}

var persist := true
var unlocked := true
var muted := false
var round_id := -1
var cues: Array = []
var effects: Array = []
var notice := ""
var notice_age := 0.0
var personal_cause := ""
var outcome := ""
## Optional scene node that owns the AudioStreamPlayer children; null means no playback.
var host: Node = null

var floor_id := 0
var pending: Dictionary = {}
var seen: Dictionary = {}
var voices: Array = []
var streams: Dictionary = {}


func load_preference() -> void:
	var config := ConfigFile.new()
	if config.load(PREFERENCE_PATH) == OK:
		muted = bool(config.get_value(PREFERENCE_SECTION, "muted", false))


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		stop_voices()
	if not persist:
		return
	var config := ConfigFile.new()
	config.set_value(PREFERENCE_SECTION, "muted", muted)
	config.save(PREFERENCE_PATH)


func unlock() -> void:
	unlocked = true


func reset(next_round: int, event_cursor: int) -> void:
	if next_round != round_id:
		round_id = next_round
		floor_id = event_cursor
		effects.clear()
		notice = ""
		personal_cause = ""
		outcome = ""
		seen.clear()
		stop_voices()
		for queued in pending.keys():
			if queued < round_id:
				pending.erase(queued)
	if pending.has(round_id):
		var batch: Dictionary = pending[round_id]
		pending.erase(round_id)
		consume_events(round_id, batch.events, batch.context)


func clear() -> void:
	round_id = -1
	floor_id = 0
	cues.clear()
	effects.clear()
	notice = ""
	personal_cause = ""
	outcome = ""
	pending.clear()
	seen.clear()
	stop_voices()


func consume_events(event_round: int, events: Array, context: Dictionary) -> void:
	if event_round < round_id:
		return
	if event_round > round_id:
		var queued: Array = pending.get(event_round, {"events": []}).events
		queued.append_array(events.duplicate(true))
		while queued.size() > MAX_SEEN:
			queued.pop_front()
		pending[event_round] = {"events": queued, "context": context}
		while pending.size() > MAX_PENDING_BATCHES:
			pending.erase(pending.keys().min())
		return
	for event in events:
		var event_id := int(event.get("event_id", 0))
		var key := Vector2i(event_round, event_id)
		if event_id <= floor_id or seen.has(key):
			continue
		floor_id = event_id
		seen[key] = true
		if seen.size() > MAX_SEEN:
			seen.erase(seen.keys()[0])
		present(event, context)


func present(event: Dictionary, context: Dictionary) -> void:
	var viewer := int(context.get("viewer_slot", -1))
	var kind := str(event.get("kind", ""))
	if is_hidden(event, context, viewer):
		return
	match kind:
		"player_eliminated":
			var personal: bool = int(event.get("player", -1)) == viewer
			add_effect(event.get("tile", []), personal)
			if personal:
				personal_cause = out_text(event.get("cause", {}), context.get("names", []))
		"pickup_collected":
			if int(event.get("player", -1)) == viewer or context.get("local_play", false):
				var text := pickup_notice(int(event.get("pickup", -1)), bool(event.get("granted", false)))
				if context.get("local_play", false):
					text = "P%d: %s" % [int(event.get("player", -1)) + 1, text]
				show_notice(text)
		"round_ended":
			finish_round(int(event.get("winner", -1)), viewer)
			return
	if EVENT_CUES.has(kind) and within_audio_reach(event, context, viewer):
		play_cue(EVENT_CUES[kind])


func finish_round(winner: int, viewer: int) -> void:
	if viewer < 0:
		return
	outcome = "draw" if winner < 0 else ("win" if winner == viewer else "loss")
	play_cue(outcome)


func is_hidden(event: Dictionary, context: Dictionary, viewer: int) -> bool:
	if context.get("local_play", false) or str(context.get("wall_mode", "")) != NIGHT_MODE:
		return false
	var visible = context.get("visible")
	if not event.has("tile") or not visible is Callable:
		return false
	var subject := int(event.get("player", event.get("owner", -1)))
	return subject != viewer and not visible.call(event.tile)


## Spatial-audio gate; narrower than the visual reach that `is_hidden` uses.
func within_audio_reach(event: Dictionary, context: Dictionary, viewer: int) -> bool:
	if context.get("local_play", false) or str(context.get("wall_mode", "")) != NIGHT_MODE:
		return true
	var audio_reach = context.get("audio_reach")
	if not audio_reach is Callable or not event.has("tile"):
		return true
	var subject := int(event.get("player", event.get("owner", -1)))
	return subject == viewer or audio_reach.call(event.tile)


func add_effect(tile: Array, personal: bool) -> void:
	effects.append({"kind": "elimination", "tile": tile, "age": 0.0, "personal": personal})
	while effects.size() > MAX_EFFECTS:
		effects.pop_front()


func show_notice(text: String) -> void:
	notice = text
	notice_age = 0.0


func play_cue(cue: String) -> void:
	if muted or not unlocked:
		return
	cues.append(cue)
	while cues.size() > MAX_LOG:
		cues.pop_front()
	while voices.size() >= MAX_VOICES:
		release_voice(voices.pop_front())
	voices.append({"remaining": VOICE_SECONDS, "player": start_player(cue)})


func start_player(cue: String) -> AudioStreamPlayer:
	if host == null or DisplayServer.get_name() == "headless":
		return null
	if not streams.has(cue):
		var path := AUDIO_DIR + cue + ".wav"
		streams[cue] = load(path) if ResourceLoader.exists(path) else null
	if streams[cue] == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = streams[cue]
	host.add_child(player)
	player.play()
	return player


func release_voice(voice: Dictionary) -> void:
	if voice.player != null and is_instance_valid(voice.player):
		voice.player.queue_free()


func stop_voices() -> void:
	for voice in voices:
		release_voice(voice)
	voices.clear()


func tick(delta: float) -> void:
	for voice in voices.duplicate():
		voice.remaining -= delta
		if voice.remaining <= 0.0:
			voices.erase(voice)
			release_voice(voice)
	if not notice.is_empty():
		notice_age += delta
		if notice_age >= NOTICE_SECONDS:
			notice = ""
	for effect in effects.duplicate():
		effect.age += delta
		if effect.age >= EFFECT_SECONDS:
			effects.erase(effect)


func voice_count() -> int:
	return voices.size()


func seen_count() -> int:
	return seen.size()


func pending_count() -> int:
	return pending.size()


static func pickup_notice(pickup: int, granted: bool) -> String:
	match pickup:
		ArenaGame.PICKUP_BOMB_CAPACITY:
			return "BOMB +1" if granted else "BOMB MAX"
		ArenaGame.PICKUP_MYSTERY:
			return "MYSTERY UPGRADE" if granted else "MYSTERY: NO CHANGE"
	return PICKUP_NOTICES.get(pickup, "")


static func cause_text(cause: Dictionary, names: Array) -> String:
	var kind := str(cause.get("kind", ""))
	if kind == "other_bomb":
		var owner := int(cause.get("owner", -1))
		var who := str(names[owner]) if owner >= 0 and owner < names.size() and not str(names[owner]).is_empty() else "another duck"
		return "%s's blast" % who
	return CAUSE_TEXT.get(kind, "")


static func out_text(cause: Dictionary, names: Array) -> String:
	var text := cause_text(cause, names)
	return "OUT: " + text if not text.is_empty() else "OUT"


static func urgency(remaining: float) -> float:
	return clampf(1.0 - remaining / URGENCY_WINDOW, 0.0, 1.0)
