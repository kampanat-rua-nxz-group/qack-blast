# Solo Bot Difficulty Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Let one human start and replay a server-backed room against one bot selectable as Easy, Medium, Hard, or Extreme.

**Architecture:** Run a scene-independent bot controller in `RoomRegistry`, feeding ordinary input into `ArenaGame.step()`. Separate difficulty profiles, permitted observations, and timed navigation from tactical decisions. Extend existing room commands, lobby, and results rather than creating another gameplay scene or transport.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility renderer, existing WebSocket/JSON protocol, plain SceneTree tests.

**Spec:** [Solo play and bot difficulty](../specs/2026-10-01-solo-bot-difficulty-design.md)

## Global Constraints

- Canonical identifiers are `easy`, `medium`, `hard`, and `extreme`. Display spelling is **Extreme**, not “Extream”.
- Controller code receives observations, never a live game, registry, human input buffers, or game RNG.
- Bots never become host, acquire disconnect grace, receive socket packets, or keep a room alive after the last human leaves.
- Admission counts connected humans, including spectators, plus the active bot against the existing ten-seat limit. Offline human history consumes no admission seat.
- Server-backed solo play requires the existing room server. Keep the local two-keyboard mode intact. Do not advertise offline solo support.
- Search limits are 8192 expanded states per route and the profile's candidate count per decision.
- Run every `tests/*_test.gd` headless before implementation is complete.
- Keep new `.gd.uid` files alongside their scripts; generated `.godot/` and `build/` stay untracked. No new dependencies.

## Review Focus

1. Hidden Nightfall state or pending human input must not change commands given identical permitted observation/history and seed — Tasks 2 and 4.
2. Water, forced ice slides, and planting after movement must not invalidate a claimed escape — Tasks 3 and 4.
3. Bomb chains, same-batch crates, moving bombs, and permanent closures must use the real rules — Tasks 1 and 3.
4. A peerless bot must not expire as a disconnected human, become host, or retain an empty room — Task 5.
5. Malformed requests, old snapshots, and a replay with only one connected human must leave authority and UI coherent — Tasks 6 and 7.

---

## File map

| File | Responsibility |
| --- | --- |
| Create `scripts/bot_profiles.gd` | Difficulty constants and validation |
| Create `scripts/bot_observation.gd` | Detached, visibility-limited observation and memory |
| Create `scripts/bot_navigation.gd` | Forecast known events and search time-safe routes |
| Create `scripts/bot_controller.gd` | Reaction clock, goals, tactics, ordinary commands |
| Modify `scripts/arena_game.gd` | Extract narrow pure blast/speed helpers without changing rules |
| Modify `scripts/room_registry.gd` | Bot identity, seat counting, permissions, controllers, snapshots |
| Modify `scripts/room_server.gd` | Validate and dispatch bot commands |
| Modify `scripts/online_app.gd`, `scripts/results_ui.gd` | Host controls, bot labels, start/replay gating |
| Create `tests/bot_test.gd` | Pure AI tests and deterministic simulations |
| Modify `tests/arena_test.gd`, `tests/rooms_test.gd`, `tests/network_test.gd`, `tests/online_test.gd`, `tests/results_test.gd` | Rule parity and integration regressions |
| Modify `README.md` | Solo instructions, server requirement, module map, checks |
| Create `docs/playtests/2026-10-01-solo-bot-acceptance.md` | Technical results, benchmark evidence, pending/completed human playtests |

Use existing `check(condition, message)` and failure-exit conventions; register each new `test_*` in the script's `_initialize()`. Test blocks below specify required assertions; fixtures are defined in the tasks that introduce them. Implementation is a later step, not part of writing this plan.

### Task 1: Profiles and reusable rule geometry

**Files:** Create `scripts/bot_profiles.gd`, `tests/bot_test.gd`; modify `scripts/arena_game.gd`, `tests/arena_test.gd`; include new UID files.

**Interfaces:**

- Produce `BotProfiles.get_profile(difficulty: String) -> Dictionary` and `BotProfiles.is_valid(difficulty: String) -> bool` as static methods.
- Profile fields: `interval_min`, `interval_max`, `prediction_seconds`, `candidate_limit`. Values: Easy `(0.60, 0.90, 0.0, 1)`, Medium `(0.30, 0.45, 0.0, 4)`, Hard `(0.15, 0.25, 0.50, 8)`, Extreme `(0.08, 0.15, 1.00, 12)`.
- Produce pure static `ArenaGame.blast_tiles(cells: Array, origin: Vector2i, blast_range: int, danger: bool, crates_at_start: Dictionary) -> Array[Vector2i]` and `ArenaGame.movement_speed_for(mode: String, terrain_kind: int, speed_bonus: float) -> float`.
- `blast_tiles` includes origin once, uses dimensions from `cells`, and applies normal first-crate/wall stops or neutral full row/column geometry. It does not mutate cells. Caller supplies the shared same-batch crate set.

- [x] **Step 1: Add failing profile tests and rule-helper parity tests.** Required profile assertions:

```gdscript
func test_profiles() -> void:
    var expected := {"easy": [0.60, 0.90, 0.0, 1], "medium": [0.30, 0.45, 0.0, 4], "hard": [0.15, 0.25, 0.50, 8], "extreme": [0.08, 0.15, 1.00, 12]}
    var profiles = load("res://scripts/bot_profiles.gd")
    for id in expected:
        var p: Dictionary = profiles.get_profile(id)
        check([p.interval_min, p.interval_max, p.prediction_seconds, p.candidate_limit] == expected[id], "exact profile " + id)
    check(profiles.get_profile("extream").is_empty(), "reject misspelled identifier")
    check(not profiles.is_valid("unknown"), "reject unknown identifier")
```

Also assert modifying a returned profile cannot change a subsequent lookup. Rule fixtures assert blasts stop at the first crate, a removed crate still blocks another blast in the same batch, danger bombs cross ordinary walls, and Lily speeds are 94/75.2 at zero upgrades and 141/112.8 at the cap.
- [x] **Step 2: Run `rtk proxy /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/bot_test.gd` and the same command for `tests/arena_test.gd`.** New assertions fail because the contracts are absent; existing tests must remain diagnosable.
- [x] **Step 3: Implement profiles and extract the two helpers into the existing rule paths.** Preserve blast event order, chain queues, first-crate batching, kills, pickup RNG calls, and movement semantics. The bot uses these helpers later; do not introduce AI logic into the engine.
- [x] **Step 4: Rerun both scripts.** Expected exit 0 and no failed checks; compare deterministic rule fixtures before/after extraction.
- [x] **Step 5: Commit only Task 1 files and their UIDs** with `feat(bot): add difficulty profiles and shared rule geometry`.

### Task 2: Fair observation and Nightfall memory

**Files:** Create `scripts/bot_observation.gd`; extend `tests/bot_test.gd`.

**Interfaces:**

- Consume Task 1 helpers and existing `NightVisibility.darkness_at(distance, vision, cell)`.
- Produce static `BotObservation.capture(game, slot: int, memory: Dictionary) -> Dictionary`.
- Observation fields: `geometry` (width/height/cell/origin), `wall_mode`, `round_elapsed`, `round_over`, `self_slot`, `self` (own position, tile, movement target, slide, safe-bomb tile, alive and upgrades), `board`, `terrain`, `players`, `bombs`, `flames`, `pickups`, `hazards`. Use native vectors for internal AI data; this is not a wire snapshot.
- `players` contains only visible living opponents with slot/position/public upgrades, never `move_targets` or input. Bombs retain observed tile/owner/range/time/danger/kick fields. Unknown board/terrain cells are `-1`.
- Memory fields: `board`, `terrain`, `seen_bombs`, `last_elapsed`, `wall_epoch`. The caller passes `{}` for a new round. Remembered bombs include last observation time and never obtain hidden updates.

- [x] **Step 1: Add `test_observation_detached`, `test_night_visibility_boundary`, `test_night_memory_shuffle`, and `test_observation_hidden_state_independence`.** Assert modifying returned arrays cannot modify the game; own state is present; hidden opponents/pickups are absent; darkness exactly 1.0 is hidden; warnings remain present globally; a Sight pickup expands visible cells. At 60 and 120 seconds, unseen interior knowledge becomes unknown. Two games differing only in hidden crates/bombs/opponent targets/RNG/input produce identical observations for equal memory. A seen bomb is retained conservatively, merged once when visible again, and retired after projected blast lifetime.
- [x] **Step 2: Run the bot test script.** Expect the new observation checks to fail.
- [x] **Step 3: Implement the adapter and memory policy from the spec.** Reject invalid/dead slots with `{}`. Deep-copy permitted data and never advance game RNG. Dynamic opponents are forgotten outside vision; unknown tiles stay blocked. Infer no exact hidden position from sound.
- [x] **Step 4: Rerun bot tests.** Expected exit 0, including both normal-map and Nightfall observations.
- [x] **Step 5: Commit Task 2 files/UIds** with `feat(bot): capture fair visibility-limited observations`.

### Task 3: Known-danger forecast and timed routes

**Files:** Create `scripts/bot_navigation.gd`; extend `tests/bot_test.gd`.

**Interfaces:**

- Consume Task 2 observations and Task 1 pure geometry/speed helpers.
- Produce static `forecast(observation: Dictionary, candidate: Dictionary = {}) -> Dictionary` and `find_route(observation: Dictionary, forecast: Dictionary, goal_tiles: Array, max_nodes: int = 8192) -> Dictionary`.
- Candidate is an observed-style hypothetical player bomb with `tile`, `owner`, `range`, `time`; `{}` means none.
- Forecast fields: `horizon`, `complete`, `danger_intervals` (Vector2i → arrays of `[start,end]`), `blocked_intervals` (same representation; `INF` end for permanent closure). Route fields: `found`, `tiles`, `arrival_times`, `expanded_nodes`; `found=false` cannot be used as escape proof.
- Add test-only helpers in `tests/bot_test.gd`: `make_open_game(mode: String = "fixed", count: int = 2)` creates an ArenaGame with seed 7 and clears interior crates; `observe(game, slot: int = 0) -> Dictionary` calls capture with new memory. Place players/bombs explicitly in each test rather than depending on spawn randomness.

- [x] **Step 1: Add the following failing route/forecast tests with explicit tile and timing assertions:**

| Test | Required assertion |
| --- | --- |
| `test_chain_forecast` | A bomb with 0.50 s fuse triggers a bomb with 2.50 s fuse in its ray at 0.50 s; danger lasts through 1.00 s |
| `test_same_batch_crate_forecast` | Two bombs detonating together cannot reach behind a crate destroyed by the first |
| `test_moving_bomb_forecast` | A bomb moving at four tiles/s detonates on the predicted tile, stops at each legal blocker, and can chain early |
| `test_hazard_forecast` | Random/blizzard strikes trigger bombs; flood/closing walls remain blocked; neutral Classic geometry crosses walls |
| `test_route_wait_and_margin` | Search can wait for flames, rejects occupancy during a blast, and includes the 0.20 s placement margin |
| `test_pond_route_duration` | Upward-rounded travel accounts for water crossing and speed upgrades rather than using 188 px/s |
| `test_frost_committed_slide` | An in-progress move finishes first, and entering ice adds the forced tile; an unsafe slide cannot be chosen |
| `test_own_bomb_egress` | A route can leave its newly planted bomb but cannot later walk back through it |
| `test_unknown_and_budget` | Unknown cells cannot form a route; expansion count is at most the requested budget; no incomplete proof returns safe |

- [x] **Step 2: Run bot tests.** Expected new tests fail with absent navigation contracts.
- [x] **Step 3: Implement forecast as an event-ordered projection of known state.** Use engine geometry helpers, predicted kick motion, same-time crate batching, chain triggers, flame intervals, and observed warnings. Do not create future random hazards or pickups. Set horizon to latest known event plus flame lifetime and 0.20 s, capped at 6.0 s; mark incomplete when known events exceed it.
- [x] **Step 4: Implement bounded time-expanded shortest-path search.** State includes tile, upward-quantized time at 0.05 s, forced movement, and own-bomb egress status. Use cardinal moves/wait; validate whole travel segments and committed motion, collision radius, terrain-dependent durations, and post-arrival survival. Reject unsafe kicks as planned actions. Use stable neighbor order for seeded repeatability.
- [x] **Step 5: Run bot and arena tests.** Expected exit 0; forecast tests must compare against actual rule outcomes, including a kicked bomb, not merely assert the forecast agrees with itself.
- [x] **Step 6: Commit Task 3 files/UIds** with `feat(bot): forecast hazards and find timed escape routes`.

### Task 4: Reaction scheduling and difficulty tactics

**Files:** Create `scripts/bot_controller.gd`; extend `tests/bot_test.gd`.

**Interfaces:**

- Consume profile, observation, forecast, and route interfaces from Tasks 1–3.
- Produce `configure(slot: int, difficulty: String, seed_value: int) -> bool`, `reset() -> void`, `advance(delta: float, observation: Dictionary) -> Dictionary`.
- Command always has cardinal/neutral `direction` and `move_press`, and boolean `plant`. Expose read-only diagnostics via `diagnostics() -> Dictionary` containing `decision_count`, `expanded_nodes`, `candidate_count`, and `next_decision_in` for tests/benchmarks. Diagnostics do not enter network snapshots.

- [x] **Step 1: Add `test_seeded_reactions`, `test_no_catchup_actions`, `test_safe_placement`, `test_difficulty_tactics`, `test_controller_fairness`, and `test_controller_reset`.** Required assertions:
  - First post-GO call makes one decision; subsequent intervals fall within exact profile bounds; equal seeds/observations yield equal sequences.
  - Changed danger before the deadline cannot change held direction; plant and move-press are false/neutral after their emission tick.
  - A 5.0 s delta causes at most one decision, never multiple retroactive bombs.
  - A dead/invalid/round-over observation returns neutral; reset drops opponent history and old intents.
  - A dead-end placement is refused; a proven escape permits planting; no plant while self has a move target or slide.
  - Easy only evaluates one nearby placement; Hard/Extreme evaluate at most 8/12 and prefer a fixture that restricts opponent exits over a harmless crate bomb when both are safe.
  - Hidden-state variants from Task 2 produce equal commands over a sequence; game state and game RNG are unchanged by controller calls.
- [x] **Step 2: Run bot tests.** New controller tests must fail before implementation.
- [x] **Step 3: Implement scheduling and survival-first goal selection.** Sample one deadline per decision, preserve movement between decisions, and never replan through a safety bypass. Select safe pickup/crate/attack goals using timed routes. When idle with no known goal, move toward a reachable visibility frontier or a seeded safe exploration tile. Capacity checks count known own bombs conservatively.
- [x] **Step 4: Implement profile tactics and planting revalidation.** Medium targets current visible positions; Hard/Extreme branch predictions at intersections through 0.50/1.00 s using observed displacement. Rank candidates by opponent safe exits, useful upgrades, and crates, in that order for Hard/Extreme after survival. Validate candidate placement at the actual current planting tile with a complete escape forecast. Exhausted searches never authorize planting.
- [x] **Step 5: Run bot tests.** Expected exit 0; test behavior fixtures, not a win-rate claim.
- [x] **Step 6: Commit Task 4 files/UIds** with `feat(bot): add scheduled difficulty tactics`.

### Task 5: Bot room membership and authoritative ticking

**Files:** Modify `scripts/room_registry.gd`, `tests/rooms_test.gd`; extend `tests/bot_test.gd` for simulated room rounds.

**Interfaces:**

- Consume `BotObservation.capture()` and controller APIs.
- Produce registry `add_bot(peer_id: int, difficulty: String = "medium") -> Dictionary`, `remove_bot(peer_id: int, person_id: int) -> Dictionary`, `set_bot_difficulty(peer_id: int, person_id: int, difficulty: String) -> Dictionary`.
- Add `admission_count(room: Dictionary) -> int` and `ready_people(room: Dictionary) -> Array` helpers; keep connected-human selection distinct for hosting and cleanup.
- Add internal room `bot_controllers` dictionary keyed by bot person ID. Persons have `kind` defaulting to human and validated bot `difficulty`. Room views add `kind`, `difficulty`, `ready_player_count`; do not serialize controllers or memories.

- [x] **Step 1: Add room tests:** `test_solo_bot_start`, `test_bot_host_permissions`, `test_bot_capacity`, `test_bot_disconnect_lifecycle`, `test_bot_scores_and_readd`, `test_bot_countdown_reset`, `test_bot_input_not_expired`, `test_bot_metadata_roundtrip`.
  - One human alone cannot start; adding Medium permits the existing countdown; bot does not act before GO.
  - Second bot, guest mutations, invalid difficulty, and active-round mutations fail without state change.
  - Nine connected humans plus bot fills ten seats; another join fails; offline history does not consume a seat; active spectators do.
  - Bot retains a unique avatar/name, never gets disconnect grace, and never receives host rights. Last human departure deletes the room even during a round.
  - Bot held movement survives beyond 0.2 s; input by a human controls only that human's slot; elimination/results/cancel neutralize bot actions.
  - Bot kills/wins persist across replay and difficulty changes. Remove/re-add produces a fresh ID and zero scores.
  - Snapshot round-trip keeps bot `connected=false`, kind/difficulty and the authoritative ready count.
- [x] **Step 2: Run room and bot tests.** Expected bot lifecycle checks fail against existing human-only logic.
- [x] **Step 3: Implement explicit participant kind and the three mutation methods.** Update admission/avatar reservation, lineup construction, human-only host transfer and cleanup, and snapshots. Physically remove a bot record only outside active phases. Retain existing disconnected-human history semantics.
- [x] **Step 4: Integrate controllers into `start_round()`, `cancel_countdown()`, and `tick()`.** Create fresh per-round bot RNG seeds without consuming gameplay RNG. Capture observations and generate commands only in active play after human input expiry, before `game.step()`. Keep bot memory per controller/room, reset on round/cancel, and preserve game event draining and final score attribution.
- [x] **Step 5: Run rooms, bot, ten-player, and ten-network tests.** Expected exit 0. Include a full ten-slot lineup with the bot to pin expanded geometry and avatar allocation.
- [x] **Step 6: Commit Task 5 files** with `feat(rooms): support an authoritative bot participant`.

### Task 6: Bot protocol validation and loopback transport

**Files:** Modify `scripts/room_server.gd`, `tests/network_test.gd`.

**Interfaces:**

- Consume registry mutation APIs from Task 5.
- Produce dispatch for `bot_add`, `bot_remove`, `bot_difficulty` using spec field names. Successful mutations push room state through the existing mechanism; rejected mutations use existing error messages. No new client transport API is necessary: use `RoomClient.send(message)`.

- [x] **Step 1: Add `test_bot_protocol_validation` and `test_solo_bot_loopback`.** Assert malformed IDs (string, float, boolean, negative), non-string/unknown difficulties, guest commands, nonexistent targets, and a human target are rejected without mutation. A real socket client creates a room, adds/changes a bot, receives metadata, starts solo, receives two-player game snapshots, and can replay after results. Bots receive no socket deliveries.
- [x] **Step 2: Run network tests.** Expected failures for unsupported bot messages.
- [x] **Step 3: Validate types before conversion, dispatch to registry, and reuse existing broadcasts.** Do not accept a target slot or impersonation field in human input; retain the peer-to-person mapping.
- [x] **Step 4: Rerun network and ten-network tests.** Expected exit 0, including unchanged human-only create/join/start flows.
- [x] **Step 5: Commit Task 6 files** with `feat(network): validate bot management commands`.

### Task 7: Lobby controls and solo results/replay

**Files:** Modify `scripts/online_app.gd`, `scripts/results_ui.gd`, `tests/online_test.gd`, `tests/results_test.gd`.

**Interfaces:**

- Consume room snapshot `kind`, `difficulty`, `ready_player_count` and Task 6 messages.
- Add `bot_add_button: Button` named `AddBotButton`, bot-row `OptionButton` named `BotDifficulty`, and `Button` named `RemoveBotButton` in lobby/results.
- Add results signals `bot_add_requested`, `bot_remove_requested(person_id: int)`, and `bot_difficulty_requested(person_id: int, difficulty: String)`; `online_app.gd` connects them to `client.send()`.
- Difficulty selector options are exactly `Easy`, `Medium`, `Hard`, `Extreme`, mapped to canonical IDs by item metadata. Present snapshot changes without emitting a new request.

- [x] **Step 1: Add `test_bot_lobby_controls`, `test_bot_results_replay`, and `test_old_room_snapshot_compatibility`.** Check host-only visibility/enabling; add default Medium request; exact selector labels and IDs; target ID in removal/change messages; all mutation controls disabled during countdown/play. Bot rows say BOT/difficulty and never offline. One connected human plus ready count 2 enables Start/Play Again; guests remain disabled. Missing new fields falls back to connected-human behavior without errors. Results mutations preserve existing room code/map/outcome presentation.
- [x] **Step 2: Run online and results tests.** Expect missing-control/gating failures.
- [x] **Step 3: Build lobby bot controls and update roster/start gating.** Use existing Ui helpers; allow only one bot and capacity below ten. Update waiting copy to explain that a bot can satisfy the second seat. Display rejected-command feedback using the existing error channel.
- [x] **Step 4: Add results management controls and replay gating.** Emit the declared signals and use the ready count. Keep roster/leaderboard identities and scores based on authoritative metadata, not local selection state.
- [x] **Step 5: Run online/results tests and inspect at the existing 960×720 viewport.** Ensure controls and ten-entry scrolling fit, dropdown labels remain readable, and keyboard focus does not leak movement into the game. Check desktop and Web where export templates are available.
- [x] **Step 6: Commit Task 7 files** with `feat(lobby): expose solo bot difficulty and replay controls`.

### Task 8: End-to-end evidence, tuning record, and player instructions

**Files:** Extend `tests/bot_test.gd`; modify `README.md`; create the acceptance record listed in the file map.

**Interfaces:**

- Consume room/controller diagnostics and existing game outcome/events.
- Add bounded `test_seeded_bot_smoke_rounds()` to ordinary tests. Add optional benchmark mode selected by `-- --benchmark-bots`, so timing reports do not make default tests depend on machine speed.

- [x] **Step 1: Add smoke fixtures for seeds 7, 42, 101, and 2026, all five maps, every difficulty, and counts 2 and 10.** Advance with fixed 1/60 s ticks for 10 simulated seconds per fixture. Assert valid commands, no pre-GO actions, bounded candidate/expanded-node counts, normal map progression, and no exceptions. These checks do not require a winner in ten seconds.
- [x] **Step 2: Run bot tests.** Fix integration regressions without weakening behavior assertions. If tuning changes a specified profile value, update spec and exact profile tests together and record the reason.
- [x] **Step 3: Run the complete suite with a failure-propagating wrapper:**

```sh
rtk proxy sh -c 'failed=0; for t in tests/*_test.gd; do /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || { echo "FAIL $t"; failed=1; }; done; exit "$failed"'
```

Expected: every script exits 0; no FAIL lines; wrapper exit 0. The README's original loop prints failures but does not reliably fail as a whole; preserve this stronger evidence in the acceptance record.
- [x] **Step 4: Run `rtk proxy /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/bot_test.gd -- --benchmark-bots`.** Record decision count, candidate count, expanded states, and p50/p95/max decision milliseconds by map/difficulty/geometry. If decisions materially block the 60 Hz server tick, reduce repeated work/candidate evaluation before shipping; do not remove safety or visibility limits.
- [x] **Step 5: Exercise one-human create → add bot → choose difficulty/map → countdown → play → results → change difficulty → replay → remove bot.** Verify last-human exit cleans up, Nightfall never targets unseen opponents, and human-only rooms still work. Ask an experienced player to assess Extreme; record human checks as pending until actually performed, not passed based on simulation.
- [x] **Step 6: Update README and acceptance evidence.** State the server requirement and one-bot scope, instructions and difficulty audience, new module ownership, and new bot test script. Record measured values separately from proposed tuning. Preserve unrelated user edits already present in README.
- [x] **Step 7: Commit Task 8 files** with `test(bot): validate solo play and document difficulty tuning`.

## Completion boundary

Implementation is complete and all task checkboxes are checked. The automated test suite passed. Human difficulty assessment and browser/performance evidence remain pending; Extreme is not playtest-validated merely because tests pass.
