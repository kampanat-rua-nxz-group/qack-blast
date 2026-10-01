# Player Experience Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task when execution is requested. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make online play respond predictably, explain the game before a round, communicate important events, help friends connect without developer instructions, and support up to ten recognizable duck characters.

**Architecture:** Keep gameplay and room lifecycle authoritative on the server. Add focused client input, presentation, map-selection, and feedback helpers around the existing scenes. Deliver six reviewable milestones, including the character/capacity extension and map-readability feedback; avoid unrelated rewrites.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility, WebSocket snapshots, plain `SceneTree` tests.

**Spec:** The scope and proposed behavior in [Design decisions](#design-decisions), together with the existing [game rules](../specs/qack-blast-game-design.md), [online rooms](../specs/2026-09-28-online-rooms-design.md), [results flow](../specs/2026-09-29-in-room-results-design.md), and [map identities](../specs/2026-09-29-map-identities-and-sudden-death-design.md). Current code and README support 2–6 players; older documents that say 2–4 do not reduce that support.

**Status — October 1, 2026:** Tasks 1–9 are implemented and reviewed; Task 10 technical validation and documentation are complete, while human acceptance remains open. All 13 headless scripts and the final Web export passed. Browser lifecycle coverage, a ten-minute automated soak, 36 causal presented-pose trials, and six valid-map 50-bomb cascades are recorded in the [acceptance record](../../playtests/2026-10-01-player-experience-acceptance.md). Nightfall misses the proposed 60 fps Web target; an artificial all-open stress fixture exceeds the queued transport buffer. Changes after the recorded commits remain uncommitted by instruction. Approved tuning now includes roughly doubled Frost ice/Lily water coverage and Lily starting speed at 50% of normal.

**Baseline checked on September 30, 2026:** All six existing headless scripts passed (`arena`, `connection`, `network`, `online`, `results`, `rooms`), with localhost access enabled for network verification. Document links and task coverage were checked. This validates the current baseline; the new regression cases and human playtest remain future implementation work.

## Scope and milestones

| Milestone | Review item | Deliverable | Tasks | Depends on |
|---|---|---|---|---|
| M1 | 1 | Predictable directional input and smoother online movement | 1–2 | Existing rules and network |
| M2 | 2 | Map explanation, player identification, shared start countdown | 3–4 | Round identity from Task 2 |
| M3 | 3 | Authoritative event feedback, sound, elimination explanation, bomb urgency | 5–6 | Round identity from Task 2 |
| M4 | 5 | Clear connection states, bounded retries, useful recovery | 7 | Existing room semantics |
| M5 | New user request | Ten distinct duck looks, larger-room rules, board/HUD support, and 2–10 capacity | [Extension Tasks A–E](2026-09-30-character-design-and-ten-players.md#tasks-and-integration-order) | Coordinate with Tasks 2–4 and 6 |
| M6 | 4, feedback received | Distinct ice/sliding feedback and a longer Nightfall fade outside the existing clear region | 8–9 | Coordinate with Tasks 2/6 and M5 board rendering |
| Acceptance | All included items | Automated regression checks and a recorded human playtest | 10 | M1–M6 |

Milestone numbers group related outcomes; they are not the task execution order. Use the cross-document execution order below. M4's connection work is independently testable and is scheduled early to support later multiplayer checks.

**Item 4 feedback received:** Frost changes should make the slippery surface recognizable before entry and the forced slide recognizable during movement. Nightfall should remain suspenseful, keep its current fully clear range, and reveal progressively fainter detail outside that region before reaching full darkness. The user did not request faster/longer slides, a larger fully lit circle, or unrestricted visibility across the map. M6 owns these changes. **Approved later amendment:** roughly double Frost ice and Lily water coverage, preserve safe spawn exits, and reduce Lily starting speed to 50% of normal with its existing water factor and proportional Speed upgrades. Other balance changes remain outside this plan.

## Execution order across both plans

This is the authoritative execution order for the combined scope. **Main N** refers to a numbered task in this document; **Expansion A–E** refers to the lettered tasks in the [character/ten-player plan](2026-09-30-character-design-and-ten-players.md). Follow this sequence rather than completing either document from top to bottom independently. Each task retains its own tests and review checkpoint.

| Stage | Outcome | Exact task order | Why it belongs here | Exit check |
|---|---|---|---|---|
| 1 | Reliable controls and room access | Main 1 → Main 7 | Fix input intent and connection recovery before evaluating later multiplayer behavior. Neither task requires new art or larger maps. | Latest-key input, short taps, focus loss, one-shot room requests, retry/cancel all pass; existing 2–6-player flow works. |
| 2 | One scalable board renderer and smooth movement | Expansion A → Main 2 → Expansion B | Establish world/display separation before interpolation and larger boards, so later art/effects have one rendering home and display scaling cannot change movement rules. | Existing 2/6-player layout and movement remain correct; 7–10-player geometry/spawns pass engine tests with the public room limit still six. |
| 3 | Clear round setup and recognizable ducks | Main 4 → Main 3 → Expansion C | Establish countdown phase rules, then map/YOU UI, then fit the shared ten-look characters and HUD around those controls. | Host/guest/countdown/rematch tests pass; ten-slot rendering fixtures fit; identities survive slot changes. |
| 4 | Readable gameplay, ice, and darkness | Main 5 → Main 6 → Main 9 → Main 8 | Emit authoritative events before playing feedback; finish effects on the shared board/character renderer. Apply the Nightfall policy before integrating the remaining map effects. | Sounds/effects occur once, death causes are correct, Nightfall retains its clear center with a gradual fade, and actual ice slides visibly differ from walking. |
| 5 | Enable ten-player online rooms | Expansion D | Raise the admission limit once the complete rules/rendering/UI path can represent every participant; run ten clients through the integrated flow. | Ten clients can join, play, finish, and replay; the 11th is rejected; disconnects, host transfer, scores, and slot 9 inputs work. |
| 6 | Validate the complete experience | Expansion E → Main 10 | Measure capacity/readability first, then consolidate all acceptance evidence and player instructions for the final result. | Full automated suite, Web smoke test, load/latency evidence, and recorded human feedback cover the combined scope. Missing human/browser coverage is explicitly outstanding. |

### Dependency rules

- **Expansion A before Main 2 and Expansion C:** all three touch board presentation. A first establishes the child renderer using current authoritative positions; Main 2 supplies interpolation afterward; C supplies shared character art. Do not create separate competing renderers in each task.
- **Main 2 before Main 4/Main 5:** the countdown and event stream use its round identity. A matching room/game `round_id` must exist before either feature depends on it.
- **Main 4 before Main 3 in this sequence:** the map picker can test its countdown lock against the actual phase, rather than a future placeholder. Main 3 owns the YOU marker; Expansion C reuses it in the compact HUD.
- **Expansion A/B before Expansion C's full acceptance:** the ten-slot HUD and smallest character scale must be checked against real larger-board geometry. Early costume studies do not require completed gameplay code.
- **Main 5 before Main 6:** sounds and elimination feedback consume authoritative events, not guesses from snapshot differences.
- **Main 6 plus Main 2 and Expansion C before Main 8:** slide cues use the feedback controller, sampled movement state, and shared duck drawing. **Main 6 plus Expansion A before Main 9:** the Nightfall update wires the common board mask and audio visibility policy together.
- **Main 8 and Main 9 have no hard dependency on each other.** Nightfall first is the selected sequence; they may be exchanged while preserving their other prerequisites. Neither depends on enabling ten-player admission.
- **Expansion A–C are hard prerequisites for Expansion D.** Waiting until Stage 4 also finishes is the chosen delivery checkpoint for this combined scope, so ten-player validation runs against the complete intended experience.
- **Expansion E and Main 10 share one evidence record.** E owns capacity/soak measurements; Main 10 checks the overall acceptance list and documentation. Reuse overlapping test/playtest results from the same build; repeat them only after relevant changes or unresolved failures.

### Work that can progress independently

- Character silhouette studies and sound-asset preparation may begin while Stage 1 is being implemented. Their integration and final small-scale/contrast review wait for the shared board and character interfaces.
- Main 7 is logically independent of Main 1, but both edit `online_app.gd`; the default is sequential execution. Separate workers would need explicit file ownership and integration, not simultaneous edits to the same scene coordinator.
- The pure Nightfall falloff math can be checked in isolation early. Its task is complete only after the board mask, event visibility, and rendered-view checks are integrated.
- Do not let independent asset/design work bypass the ten-player admission or final acceptance checkpoints. Planning for concurrent work does not itself dispatch agents or start implementation.

### Incremental review checkpoints

- After Stage 1: test joining and control feel using the current art and current capacity.
- After Stage 2: review movement smoothness and display scaling; leave ordinary online rooms at six players while larger-board fixtures are evaluated.
- After Stage 3: review the ten duck looks, map selection, countdown, and compact HUD at actual display size.
- After Stage 4: review the complete Frost/Nightfall presentation and audiovisual feedback; confirm unchanged slide mechanics and clear vision radius.
- After Stage 5: perform integrated ten-client checks before claiming ten-player functionality is ready for broad playtesting.
- After Stage 6: assess release readiness from recorded evidence. Deployment remains a separate action; this schedule does not deploy anything.

## Global constraints

- Expand online capacity from the current 2–6 to **2–10** through M5, keeping existing 2–6 behavior as regression coverage. Preserve host-only map/start controls, cumulative Wins/Kills, replay in the same room, and local two-player controls.
- The server owns movement legality, bomb placement, damage, score attribution, countdown, and round outcome. Client smoothing never changes rule state or resolves collisions.
- Preserve tile-center movement, bomb fuse **2.5 seconds**, flame lifetime **0.5 seconds**, and existing map-specific rules. The later approved Frost/Lily coverage and Lily 50% starting-speed amendment is the explicit tuning exception; M5 adds larger-board geometry and safe spawns for 7–10 players.
- Preserve Frost's existing one-extra-tile slide distance, speed, trigger, and blockers. Preserve Nightfall's starting `vision = 1`, current fully clear radius, and Sight pickup increment. M6 intentionally extends partial visibility through a longer outer fade; this is a visibility change even though the clear radius stays the same.
- Retain the **30-second** disconnected-avatar grace period during active play. Rejoining remains a new participant; it does not recover the previous avatar or score record.
- Preserve the **960 × 704** viewport, duck art direction, keyboard controls, and Godot Web export. M5 adds ten costume/color identities, display-scaled boards, and compact HUD rows inside that viewport; costumes do not change gameplay stats.
- Keep the existing English game UI; this plan does not add localization, touch controls, bots, accounts, matchmaking, progression, or music.
- Keep each new `.gd.uid` beside its script. Add `test_*` functions with the existing `check` helper and nonzero failure exit; no test framework dependency.
- Tests for logic must be deterministic. Audio quality, animation readability, and perceived responsiveness require visual/audio or human checks, not screenshot pixel assertions.
- Run every `tests/*_test.gd` headless before declaring implementation complete. A sandbox preventing a loopback bind is an environment limitation, not a passing network test.

## Review focus

1. **Input aliases and lost focus:** holding W and Up, releasing one, switching direction, or leaving the browser must not lose the intended held key or leave a duck moving. Task 1 owns these tests.
2. **New rounds and stale presentation:** rematches, room changes, stationary snapshots, and network stalls must not animate a duck across the map or replay an old event. Tasks 2, 5, and 6 own these tests.
3. **Countdown membership changes:** duplicate starts, host departure, late joins, and held bomb keys must not start a second round or produce a bomb before GO. Task 4 owns these tests.
4. **Ambiguous or hidden events:** simultaneous blasts must retain existing Kill attribution, and Nightfall feedback must not reveal hidden event positions. Tasks 5 and 6 own these tests.
5. **Slow or interrupted connection attempts:** repeated clicks, late callbacks, cancellation, and room rejection must not send duplicate create/join commands or trap the user on a loading screen. Task 7 owns these tests.

## Design decisions

### M1: Input and movement presentation

Current evidence: `online_app.gd::_physics_process` prioritizes Up, Down, Left, Right in that order; local play already tracks recently pressed directions. The online renderer replaces positions on each snapshot and resets `walk_phase` to zero. The server sends snapshots about every **50 ms**, while clients send input about every **33 ms**.

- Track physical direction keys in press order. The newest still-held key wins; releasing it falls back to the next held key. WASD and arrow aliases remain separate held keys. Ignore keyboard-repeat events.
- Send a direction change or bomb press immediately, and keep the existing **30 Hz** held-input heartbeat. Preserve the server's **0.2-second** input expiry. Send neutral input and clear held state on focus loss, leaving a round, and disconnect.
- Preserve a short press/release occurring between server ticks: extend an input command with optional `move_press: [x, y]`. The registry retains the latest pending press until the next simulation tick; it starts one tile step only if that duck is at rest, then consumes the press. Held direction still determines later steps. Validate the field against the four cardinal directions; it cannot override the sender's slot or bypass `ArenaGame` movement checks.
- Keep authoritative state separate from display positions. Smooth over received samples with an initial **50 ms** presentation buffer; do not add client gameplay prediction in this milestone. This improves continuity, not the underlying network round-trip time.
- Give room and game snapshots a matching, monotonically increasing per-room `round_id`. Give each game snapshot a `snapshot_seq`; use `round_elapsed` for active-round sample timing. First samples and new rounds display immediately and reset old history.
- Interpolate along authoritative movement segments, including tile centers at turns, rather than drawing a diagonal through a corner. Include each player's current `move_target` in the snapshot when needed to reconstruct that segment. Animate facing and walking from displayed motion; stationary repeated snapshots must not restart a walk cycle.
- When no newer sample is available, hold the latest received position; never extrapolate through a wall or bomb. On a gap over **250 ms**, discard interpolation history and resume from fresh state. Board changes and elimination invalidate affected movement segments immediately.
- Draw a locally owned duck's Nightfall spotlight at its displayed position. During Main 2, use the current falloff and preserve its clear radius. Main 9 later replaces that falloff with the shared M6 function while retaining the same position input. This avoids making movement presentation depend on unfinished lighting work.

### M2: Understanding and starting a round

- Replace the cycling-only map interaction with a reusable selector used from waiting and results screens. Show all five names, a representative thumbnail, terrain effect, special pickup, and sudden-death behavior. Random thumbnails are explicitly examples, not the upcoming random layout. Generating a preview must not consume gameplay RNG or mutate the room.
- The host selects a map through the existing `map` command. Guests can inspect descriptions; only an authoritative room update changes the selected indicator. Selection stays locked during countdown and play.
- Add a persistent **YOU** marker to the local player's card and a short spawn indicator. Spectators see **SPECTATING — next round** instead of a marker on someone else's duck. Keep the existing keyboard hint visible.
- Hide the local-only `NEXT: ...` indicator online. Use `room.wall_mode` for the next selected map in lobby/results and `game.wall_mode` for the active arena.
- A host's first Start and every Play Again enter a server-owned **3-second countdown**: `lobby/results → countdown → playing → results`. Freeze gameplay and `round_elapsed` until GO; clients render `ceil(countdown_remaining)` from room state and may animate between updates without deciding when play begins.
- Freeze the lineup at countdown start. New joiners during countdown spectate until the next round. A lineup member leaving cancels countdown, clears the prepared game and input buffers, resets slots, and returns everyone to the waiting lobby with an explanation; scores and selected map remain. Existing host transfer and empty-room cleanup still apply. A spectator leaving does not cancel countdown.
- Reject map changes and repeated start commands during countdown. Ignore gameplay inputs until playing. Clear pending bomb presses at the boundary; a held Space/Enter must be released and pressed again to plant. Direction keys may begin movement after GO.

### M3: Event feedback and sound

- Produce events at authoritative rule transitions: bomb placed, bomb exploded, pickup collected, player eliminated, and round ended. Include each event's elapsed time, tile when relevant, player/owner identifiers, and a monotonic event ID within its round.
- Record elimination cause where damage is resolved. Distinguish own bomb, another player's bomb, simultaneous ambiguous blasts, neutral danger bomb, flood, blizzard, random burst, closing walls, and disconnect expiry. Existing nearest-bomb/tie rules still determine Kills; UI wording must not invent a credited killer.
- The engine exposes `take_events() -> Array` for both local play and the registry. The registry drains events into a bounded outgoing room batch; the server sends an `events` message with `round_id` to connected room peers after each tick, including the tick that enters results. Clear each batch after dispatch. Keep the final elimination cause in player state so a later snapshot can explain OUT without replaying historical sounds.
- Clients deduplicate by `(round_id, event_id)`. Joining or reconnecting initializes at the current event cursor; do not replay earlier explosions or a finished victory sound. At a round boundary, queue messages for the new round until its matching room/game state is present, with a small bounded queue that is cleared on disconnect.
- Use short sounds for placement, explosion, pickup, elimination, countdown, win, loss, and draw. Add a visible mute control available in lobby, arena, and results; persist it locally. Audio must start only after a browser-supported user interaction and must not block play if unavailable. Use original/generated or suitably licensed files with provenance in `assets/audio/README.md`.
- Play spatial gameplay cues only within the visibility permitted by the active Nightfall feedback policy; M6 keeps positional audio within the previous outer reach while allowing fainter visuals farther out. Local pickup/elimination notices and global countdown/outcome cues remain available. Do not add offscreen positional markers that reveal hidden opponents.
- Add a brief elimination effect and a persistent personal cause message while spectating; repeat the personal cause on results if the round ends immediately. Show collected upgrade text such as `BOMB +1`, and respect capped/no-change Mystery outcomes.
- Make bomb pulse/fuse urgency increase in the final **0.6 seconds** using authoritative remaining time. Effects do not move the explosion boundary, extend flame damage, cover hazard warnings, or require screen shake. Existing immediate transition to results stays intact.

### M4: Connection and recovery

- Replace the production-facing instruction to start a room server with player-facing connection status. A local development hint may appear only for an actual loopback server configuration.
- Make connection state explicit: idle, connecting, waiting for room response, in room, failed. Disable duplicate Create/Join actions while busy; offer Cancel. Preserve nickname and room code after failure.
- Allow up to **90 seconds** total for connecting to a sleeping server. After **8 seconds**, show `The server may be waking up. This can take about a minute.` Before any room command has been sent, retry failed transport attempts with **1, 2, 4, 8, 8… second** delays within that budget. Treat each transport attempt as at most **12 seconds**. These are proposed UX defaults to validate against the deployed service.
- Send the pending create/join command once after connection succeeds. After transmission, wait at most **15 seconds** for a room outcome; do not automatically retransmit an action whose result is uncertain. Show Retry after failure and begin a fresh attempt only on that user action. Cancel closes the attempt and discards its pending command.
- Distinguish connection failures from `Room not found`, `Room is full`, and other authoritative room rejections. Room rejection does not trigger transport retries. Keep any raw endpoint/technical diagnostic out of the normal player message.
- Use an attempt generation token so a cancelled or superseded attempt cannot update the current UI or send its old command. Inject elapsed time into the connection controller for deterministic tests.
- On mid-round disconnection, preserve the nickname and last room code, explain the loss, and offer an explicit rejoin action. Rejoining is a new player who waits for the next round if one is running. Do not silently create a replacement room or promise restored scores/avatar. A missing room after server restart gets a clear message.

### M6: Frost readability and Nightfall falloff

**User feedback:** Ice currently looks too much like normal floor, and sliding looks too much like ordinary movement. Nightfall's viewing distance feels right and should remain suspenseful; visibility outside the current lit area should fade over a longer distance instead of quickly becoming solid black.

**Frost — show both the surface and the movement state:**

- Give ice a distinct surface pattern: a cool translucent-looking fill, a thin light rim, and two or three restrained diagonal shine/skid strokes. Keep ordinary floor plain. Avoid the X motif used by crates, wall-like height/shadows, or warning-style flashing; the tile should read as flat and slippery.
- Add a low-intensity moving sheen on ice so its material remains recognizable at 32 px display tiles. Static pattern/contrast must still distinguish ice when animation is paused or difficult to notice. Do not change where ice is generated.
- During the actual forced slide, suppress the normal walking bounce and use a stable gliding pose with a slight body lean plus a short pale trail behind the duck. Preserve the bill/facing and costume silhouette. End the gliding pose when the forced movement ends; brief trail remnants may fade naturally.
- Drive this from the server's slide state, not from whether the duck is currently over an ice tile or moving quickly. A forced slide may finish on normal floor, and walking onto a blocked ice tile does not imply a successful slide.
- Expose `ArenaGame.is_sliding(player_index: int) -> bool`, true only for a living player with an active slide and a nonzero movement target. Include `sliding: bool` per player in snapshots. For online rendering, sample it alongside position at the same presentation timestamp so the pose/trail cannot lead or lag the displayed slide.
- A short skate sound may accompany the start of a visible slide through M3's feedback system, once per slide, respecting mute. Visual cues must explain the slide without sound. Keep the existing one-extra-tile distance, movement speed, collision, and bomb-kick rules.
- Clear slide presentation on elimination, blocked/cancelled movement, room change, and new round. Spectators may see the correct animation but cannot control it.

**Nightfall — keep a clear center, lengthen the dim outer region:**

- The current renderer already fades over the last **0.5 tile** of its light radius. With `vision = 1`, its fully clear radius is **1.4 tiles** and its fully dark boundary is **1.9 tiles**. The requested improvement is a longer falloff, not merely adding a gradient that already exists.
- Keep `clear_radius = (vision + 0.4) * CELL`. Keep the former outer radius `(vision + 0.9) * CELL` as the transition to a very dim region. Initial proposed appearance: darkness rises smoothly from **0.0 to 0.8** between those radii, then from **0.8 to 1.0** over another **1.5 tiles**, reaching full darkness at `(vision + 2.4) * CELL`. Thus starting clear vision is unchanged while faint detail extends farther.
- Use a continuous monotonic smoothstep curve in each segment. At both segment boundaries, opacity is continuous with no hard ring. `0` means unobscured and `1` means fully dark. The 0.8 darkness anchor and 1.5-tile outer width are proposed visual tuning values to inspect with the user, not user-specified numerical requirements.
- Apply the common mask to the whole board, including terrain, ducks, bombs, pickups, flames, and slide effects. Objects in the outer region may be faintly visible; do not silently implement terrain-only vision. At/beyond the final radius, all ordinary board detail is hidden. Keep global lethal hazard warnings above the mask as specified by the existing rules.
- Make the drawn mask, `vision_darkness`, and visual visibility queries use the same function. A Sight pickup increases each radius by one tile, retaining the gradient width and starting clear-range policy.
- Keep the circle centered on the displayed duck. Online living players use only their own spotlight; local two-player play combines both with minimum darkness; spectators and round-over views retain their existing full-board view.
- Do not let the new faint region create clear floating markers or enlarge positional-audio awareness. Spatial event audio remains gated to the previous outer reach `(vision + 0.9) * CELL`; visual event effects beyond it stay under the mask. Local elimination notices and global warnings/outcomes retain their existing treatment.
- Reuse the board's world/display transform so larger 7–10-player maps do not change visibility in tiles. Inspect the gradient on the five-map UI's smallest supported scale without changing the chosen clear radius to compensate for display size.

## File ownership

| File | Planned responsibility |
|---|---|
| `scripts/player_input.gd` (new) | Physical-key ordering, aliases, direction/bomb edges, reset |
| `scripts/arena_presentation.gd` (new) | Display sample buffer, position/facing/walk state; no rules |
| `scripts/night_visibility.gd` (new) | Pure darkness/falloff function and spatial-audio reach policy shared by rendering and feedback |
| `scripts/map_catalog.gd`, `scripts/map_picker.gd` (new) | Descriptions/representative previews and reusable map selection UI |
| `scripts/game_feedback.gd` (new) | Event consumption, deduplication, effects, short sounds, mute setting |
| `scripts/connection_flow.gd` (new) | Attempt state, bounded retry schedule, cancellation, error categories |
| `scripts/arena_game.gd` | Existing rules plus authoritative feedback event/cause records and truthful slide-state query |
| `scripts/room_registry.gd` | Pending input edges, round identity, countdown, event batches |
| `scripts/room_server.gd`, `scripts/room_client.gd` | Validate/transport added input, snapshots, and event messages |
| `scripts/online_app.gd` | Compose helpers, wire commands, phase visibility and connection UI |
| `scripts/arena.gd` | Draw display state, YOU/countdown/effects; local feedback integration |
| `scripts/results_ui.gd`, `scripts/lobby_ui.gd` | Reuse map picker and connection/feedback controls where appropriate |
| `assets/audio/` (new) | Short sound files and provenance |
| `tests/*_test.gd` | Deterministic behavioral coverage below; new scripts receive `.uid` companions |
| `README.md` | Updated player instructions, countdown/recovery behavior, complete check list |

## Implementation tasks

For each behavioral task: add the named regression cases, run them and confirm the expected failure, implement the scoped behavior, rerun affected checks, and review the diff before committing. Pure copy/layout changes need visual inspection rather than tests that merely repeat the text.

### Task 1: Direction intent and input edges — M1

**Task status:** Implemented/reviewed; deterministic input and focus-loss checks pass. The manual local/Web control-feel comparison remains unverified.

**Files:** Create `scripts/player_input.gd` and `tests/input_test.gd`; modify `scripts/online_app.gd`, `scripts/room_server.gd`, `scripts/room_registry.gd`, `tests/rooms_test.gd`, and `tests/network_test.gd`.

**Interfaces:** `PlayerInput.handle_key(keycode: int, pressed: bool, echo: bool) -> void`, `direction() -> Vector2`, `consume_move_press() -> Vector2`, `consume_bomb_press() -> bool`, `reset() -> void`. Extend `RoomRegistry.set_input(peer_id: int, direction: Vector2, plant: bool, move_press: Vector2 = Vector2.ZERO) -> bool`; old callers remain valid.

- [x] Add `test_latest_held_key_wins`, `test_alias_release_keeps_other_key`, `test_repeat_does_not_reorder`, `test_bomb_press_is_consumed_once`, and `test_focus_loss_resets_input` in `tests/input_test.gd`.
- [x] Add registry/network cases for invalid/diagonal `move_press`, press+release before one server tick producing exactly one step from rest, no extra queued step while already moving, and neutral input/expiry stopping continued movement.
- [x] Run the input, room, and network scripts; confirm new cases fail for the missing behavior.
- [x] Implement the helper and wire key changes to immediate input sends plus the existing 30 Hz heartbeat. Do not let lobby text entry produce gameplay commands. Pass validated press intent into the existing rules at the next tick.
- [x] Rerun input, room, and network scripts; deterministic key/focus regressions pass.
- [ ] Manually compare keyboard turns with local play, nickname typing, and browser focus switching.
- [x] Commit: `fix(input): honor latest direction and preserve input edges`.

### Task 2: Smooth authoritative online presentation — M1

**Task status:** Implemented/reviewed; interpolation regressions and 0/100/150 ms RTT/jitter presented-pose trials pass. Complete recorded visual motion review (turns/kicks/death) remains open.

**Files:** Create `scripts/arena_presentation.gd` and `tests/presentation_test.gd`; modify `scripts/arena.gd`, `scripts/online_app.gd`, `scripts/room_registry.gd`, `scripts/room_server.gd`, `tests/rooms_test.gd`, and `tests/online_test.gd`.

**Interfaces:** `ArenaPresentation.reset() -> void`, `push_snapshot(snapshot: Dictionary, received_at: float) -> void`, `sample(now: float) -> Dictionary`. `sample` returns display positions, facing, and walk phase for the matching round; it does not modify `arena.game`. Add `round_id` to room/game snapshots, `snapshot_seq` to game snapshots, and JSON-safe player `move_target` values (`[x, y]`, with `[0, 0]` meaning no target).

- [x] Add deterministic `test_interpolation_between_samples`, `test_turn_uses_tile_center`, `test_duplicate_sample_does_not_restart_walk`, `test_stall_holds_position`, `test_round_change_resets_samples`, and `test_death_or_board_change_invalidates_motion`.
- [x] Add snapshot round-trip tests and an online assertion that displaying an interpolated position leaves authoritative position/board unchanged. Verify the Nightfall spotlight follows the displayed duck using the current curve and its original fully clear radius. Main 9 later reruns this check with the M6 curve; Main 2 does not require that future helper.
- [x] Run presentation, room, and online scripts; confirm missing interface/behavior failures.
- [x] Implement the 50 ms initial buffer and 250 ms reset boundary. Increment round identity when preparing each new round, advance snapshot sequence centrally, reject stale sequences, and clear history on leave/disconnect. Remove the per-snapshot walk-phase reset.
- [x] Rerun affected tests and record causal presented-pose onset under 0/100/150 ms RTT and jitter in the bounded headless harness.
- [ ] Complete the recorded normal-frame-rate visual motion review of turns, kicks, death, and rematch; interpolation does not eliminate input latency.
- [x] Commit: `feat(online): smooth movement from authoritative snapshots`.

### Task 3: Map explanation and player identity — M2

**Task status:** Implemented/reviewed; map picker, YOU/spectator markers, layout and preview checks pass.

**Files:** Create `scripts/map_catalog.gd`, `scripts/map_picker.gd`, and `tests/map_picker_test.gd`; modify `scripts/online_app.gd`, `scripts/results_ui.gd`, `scripts/arena.gd`, `tests/online_test.gd`, and `tests/results_test.gd`.

**Interfaces:** `MapCatalog.describe(mode: String) -> Dictionary` returns `name`, `terrain_text`, `pickup_text`, `hazard_text`, and representative preview data. `MapPicker.present(selected_mode: String, can_select: bool) -> void` and `signal map_selected(mode: String)`; the app sends the existing map command.

- [x] Add coverage for all five map entries, host-only selection, guest inspection without commands, authoritative selection updates after rejection, and identical picker behavior from lobby/results.
- [x] Add `test_online_hides_local_next_map`, `test_local_player_marker_follows_person_slot`, and `test_spectator_has_no_player_marker` to online checks.
- [x] Run map-picker, online, and results scripts; confirm missing behavior fails.
- [x] Implement catalog/picker and marker integration. Keep the local scene's M/R next-map behavior. Show current mechanics accurately, including Frost sliding/kick and Nightfall reshuffles, without changing terrain or vision values.
- [x] Rerun affected checks and inspect waiting/results/arena at 960 × 704 with six players and long nicknames. Verify previews do not mutate map generation or imply an exact Random board.
- [x] Commit: `feat(lobby): explain maps and identify the local duck`.

### Task 4: Shared countdown and lifecycle — M2

**Task status:** Implemented/reviewed; countdown/lifecycle tests and multi-client Web flow pass.

**Files:** Modify `scripts/room_registry.gd`, `scripts/room_server.gd`, `scripts/online_app.gd`, `scripts/arena.gd`, `tests/rooms_test.gd`, `tests/network_test.gd`, `tests/online_test.gd`, and `tests/results_test.gd`.

**Interfaces:** Preserve `start_round(peer_id: int) -> bool`, but enter `phase = "countdown"` with `countdown_remaining = 3.0`. `tick(delta: float)` owns the transition. Include `countdown_remaining` and matching `round_id` in room views. `set_input` accepts only `playing`.

- [x] Add `test_countdown_freezes_game_clock`, `test_countdown_transitions_once`, `test_countdown_rejects_start_map_and_input`, `test_lineup_departure_cancels_countdown`, `test_late_join_spectates`, and `test_held_bomb_does_not_fire_at_go`.
- [x] Update existing room/network/UI fixtures that assume Start immediately enters playing: assert countdown explicitly, then advance the authoritative clock. Cover first start and rematch, host transfer, empty-room deletion, retained scores, and fresh lineup after cancellation.
- [x] Run affected tests and confirm lifecycle expectations fail before implementation.
- [x] Implement countdown/cancellation and a visible 3–2–1–GO overlay. Match room/game round IDs before showing the board; display a preparing state rather than the prior round's arena. Use only the time left after countdown expiry for gameplay when one large tick crosses GO.
- [x] Rerun checks and verify two browser clients observe one start, no movement/bombs before GO, and no stale bomb press after results. Confirm active-play disconnect grace remains 30 seconds.
- [x] Commit: `feat(rooms): synchronize round start countdown`.

### Task 5: Reliable gameplay event and cause records — M3

**Task status:** Implemented/reviewed; event/cause/scoring regressions pass. Event work is included in f881a6f rather than the originally proposed commit title.

**Files:** Modify `scripts/arena_game.gd`, `scripts/room_registry.gd`, `scripts/room_server.gd`, `scripts/room_client.gd`, `tests/arena_test.gd`, `tests/rooms_test.gd`, and `tests/network_test.gd`.

**Interfaces:** `ArenaGame.take_events() -> Array`; events carry `event_id`, `kind`, `elapsed`, and the relevant payload. `RoomRegistry.take_room_events(room: Dictionary) -> Array` drains the dispatch batch. `RoomClient` emits `events_received(round_id: int, events: Array)`. Room/game views carry `event_cursor`; player snapshots retain `elimination_cause`. Wire message: `{ "type": "events", "round_id": <int>, "events": [...] }`. Tile/vector values are JSON arrays.

- [x] Add exact-once emission cases for placement, explosion chains, actual pickup grants/capped pickups, elimination, and round end. Pin self-kill, nearest-blast credit, equal-distance ambiguity, every neutral hazard, and disconnect expiry to the existing score expectations.
- [x] Add round-trip cases for ordered event IDs, batch draining, final events when the phase becomes results, late-join cursor initialization, and per-round counter reset. Verify no indefinitely growing event history.
- [x] Run arena, room, and network scripts and confirm the absent event contract fails.
- [x] Emit events at existing rule-resolution points. Let the registry record disconnect elimination through a focused engine method so causes/events stay consistent. Transport drained batches once per server tick; serialize causes without exposing mutable rule dictionaries to UI consumers.
- [x] Rerun all scoring/draw/map regressions and the new transport cases. Require unchanged Wins/Kills and round outcomes for existing scenarios.
- [x] Commit: `feat(arena): expose gameplay events and elimination causes`.

### Task 6: Sound and visual feedback — M3

**Task status:** Implemented/reviewed; automated feedback/result-race/mute/visibility checks pass. Subjective local/Web audio listening remains open; no additional commit authorized.

**Files:** Create `scripts/game_feedback.gd`, `tests/feedback_test.gd`, sound files under `assets/audio/`, and `assets/audio/README.md`; modify `scripts/arena.gd`, `scripts/online_app.gd`, `scripts/results_ui.gd`, `tests/online_test.gd`, and `tests/results_test.gd`.

**Interfaces:** `GameFeedback.reset(round_id: int, event_cursor: int) -> void`, `consume_events(round_id: int, events: Array, context: Dictionary) -> void`, `set_muted(value: bool) -> void`. Context supplies viewer slot, current map, visibility, and player names; effects never grant an upgrade, change alive state, or award a score. Local arena drains the same engine event API.

- [x] Add `test_event_is_presented_once`, `test_old_round_event_is_ignored`, `test_late_join_does_not_replay_history`, `test_new_round_events_wait_for_matching_state`, `test_muted_events_keep_visual_feedback`, and `test_night_hidden_event_has_no_positional_cue`.
- [x] Add result-race coverage: final personal elimination cause remains visible if the results phase arrives before/after the final game/event message. Cover win, loss, draw, and spectators without assigning a false personal outcome.
- [x] Run feedback, online, and results scripts; confirm missing event consumption behavior fails.
- [x] Implement sound/effect playback, bounded deduplication/queued events, the visible mute control, personal elimination text, upgrade notices, and stronger final-0.6-second bomb urgency. Clear transient effects on room changes. Use current event/cause data rather than guessing from missing snapshot entities.
- [x] Rerun feedback, online, and results checks; exact-once, mute and visibility regressions pass.
- [ ] Inspect/listen in local and Web builds after the first user gesture, with mute on/off, overlapping explosions, hidden Nightfall events, and immediate round end. Cap overlapping voices to avoid clipping; warnings and controls must remain readable.
- [ ] Commit: `feat(feedback): add sound and readable gameplay events`. **Deferred by instruction: leave the working tree uncommitted; not an implementation blocker.**

### Task 7: Connection progress, retry, and recovery — M4

**Task status:** Implemented/reviewed; deterministic recovery and loopback checks pass. Complete manual slow-public-connection/server-restart matrix remains unverified.

**Files:** Create `scripts/connection_flow.gd`; modify `scripts/room_client.gd`, `scripts/online_app.gd`, `scripts/lobby_ui.gd`, `tests/connection_test.gd`, and `tests/online_test.gd`.

**Interfaces:** `ConnectionFlow.begin(request: Dictionary) -> int` returns the attempt ID; `advance(delta: float) -> Array` returns scheduled actions; `on_transport_result(attempt_id: int, connected: bool) -> Array`, `on_room_result(attempt_id: int, message: Dictionary) -> Array`, and `cancel() -> void`. Actions are connect, close, send request, or display state; the helper owns timing/attempt identity, while `RoomClient` owns sockets. The flow exposes the current phase/error category and preserves retry input independently of `pending_request`.

- [x] Replace the existing one-second real-time failure check with deterministic cases for 8-second waking text, 12-second transport attempts, 1/2/4/8-second backoff, 90-second total deadline, and 15-second room-response timeout.
- [x] Add `test_repeated_click_sends_one_request`, `test_cancel_ignores_old_attempt`, `test_sent_request_is_not_auto_replayed`, `test_room_rejection_does_not_retry_transport`, and `test_rejoin_preserves_code_without_resuming_identity`. Retain an actual unreachable-loopback smoke check separately.
- [x] Run connection and online scripts; confirm the new state/recovery checks fail.
- [x] Implement the controller and clear busy/failed/retry/cancel UI. Bind callback handling to the current transport generation. Ensure closing a timed-out socket cannot overwrite a newer attempt, and an accepted command is cleared exactly once.
- [x] Rerun connection and online checks, including deterministic retry/cancel/rejection and loopback smoke coverage.
- [ ] Complete the manual matrix: reachable localhost, a closed port, a slow public connection, invalid/full room, cancellation, and server restart. Verify production copy gives the player an action and local-only server hints are limited to loopback configurations.
- [x] Commit: `feat(connection): add clear progress and bounded recovery`.

### Task 8: Distinct ice surface and slide feedback — M6

**Task status:** Implemented/reviewed; authoritative slide state, sampled pose, patterned ice and timing regressions pass. Static native/Web ice views checked; the full visual glide/overlap matrix and human comprehension remain open.

**Files:** Modify `scripts/arena_game.gd`, `scripts/room_registry.gd`, `scripts/online_app.gd`, `scripts/arena_presentation.gd`, `scripts/arena.gd`, `scripts/arena_board.gd` from Expansion A, and `scripts/game_feedback.gd`; test in `tests/arena_test.gd`, `tests/rooms_test.gd`, `tests/presentation_test.gd`, `tests/online_test.gd`, and `tests/feedback_test.gd`.

**Interfaces:** `ArenaGame.is_sliding(player_index: int) -> bool`; snapshot player field `sliding: bool`. `ArenaPresentation.sample(now)` returns the slide flag for the sampled movement segment. The renderer consumes it for pose/trail; it never changes movement targets.

- [x] Add `test_slide_state_covers_only_forced_segment`, `test_blocked_ice_does_not_report_sliding`, `test_slide_state_clears_on_death_and_new_round`, and `test_slide_snapshot_round_trip`. Assert unchanged one-extra-tile distance and movement timing, including a slide ending on ordinary floor.
- [x] Add `test_slide_pose_matches_sampled_position` with delayed snapshots, repeated samples, and stalled input; add a once-per-slide sound check when audio is implemented. Ensure walking over ordinary floor and merely holding a direction do not produce slide trails.
- [x] Run the affected test scripts; confirm missing state/query/presentation behavior fails before implementation.
- [x] Implement the state query and snapshot transport, patterned ice drawing, gliding pose, and short trail. Use the shared ten-look duck renderer and original movement-presentation buffer; do not add a second simulation or speed multiplier.
- [x] Rerun affected slide/presentation tests; inspect static native/Web ice at supported player profiles.
- [ ] Complete the visual motion matrix: stationary ice, ordinary walking, released-key sliding, blocked sliding, bomb kicking, elimination, and six/ten-player overlap at 32/38/44/52 px display tiles. Verify the material is identifiable before entry and the extra movement is recognizably a glide without audio.
- [ ] Commit: `feat(frost): distinguish slippery tiles and sliding movement`. **Deferred by instruction: leave the working tree uncommitted; not an implementation blocker.**

### Task 9: Extend Nightfall's gradual outer fade — M6

**Task status:** Implemented/reviewed; shared fade/audio policy and clear-radius regressions pass. Native/Web still views checked; the complete moving/upgrade/overlap visual matrix remains open.

**Files:** Create `scripts/night_visibility.gd` and its UID; modify `scripts/arena.gd`, `scripts/arena_board.gd` from Expansion A, and `scripts/game_feedback.gd`; test in `tests/arena_test.gd`, `tests/online_test.gd`, and `tests/feedback_test.gd`.

**Interfaces:** `NightVisibility.darkness_at(distance: float, vision: int, cell: float) -> float` and `within_audio_reach(distance: float, vision: int, cell: float) -> bool`. Rendering and point/tile visibility queries call the same darkness function; multi-player/local composition remains a minimum over valid viewers.

- [x] Add exact tests for `vision = 1`: darkness is 0 through 1.4 tiles, 0.8 at 1.9 tiles, between 0.8 and 1 at 2.4 tiles, and 1 at/beyond 3.4 tiles. Test continuity immediately either side of 1.4/1.9/3.4, monotonicity, circular symmetry, and equivalent results for different `CELL` sizes.
- [x] Add `test_sight_pickup_shifts_both_regions_one_tile`, `test_outer_fade_does_not_expand_audio_reach`, and regression cases for viewer isolation, combined local light, spectators, results, and warnings over darkness. Update old second-ring/1.65-diagonal expectations intentionally because those points now lie in the faint region; retain evidence that farther points stay fully dark.
- [x] Run arena/online/feedback checks and confirm the newly specified falloff fails against the previous short fade.
- [x] Implement the shared piecewise smoothstep function with named 0.8/1.5-tile tuning constants. Keep the current fully clear radius and Sight progression. Update mask drawing and feedback gating together; avoid a second hard clipping radius that would hide objects before the gradient reaches full darkness.
- [x] Rerun arena/online/feedback checks and inspect native/Web still spotlight views.
- [ ] Complete the visual matrix: still/moving spotlights, dim ducks/bombs at the outer edge, overlapping local circles, upgrades, and the 32 px display scale. Confirm gradual fading, continued suspense, no visible hard ring, no clear hidden-player marker, and unchanged bright-center size. Compare alternative outer widths only if visual review shows the proposed 1.5 tiles is too faint or too revealing.
- [ ] Commit: `feat(nightfall): extend the dim outer visibility falloff`. **Deferred by instruction: leave the working tree uncommitted; not an implementation blocker.**

### Task 10: Acceptance and documentation

**Task status:** Technical checks/documentation complete within the acceptance record; human rounds and overall milestone sign-off remain open. Commit deferred by instruction.

**Files:** Update `README.md`; create `docs/playtests/2026-09-30-player-experience-checklist.md` when implementation reaches playtest. Record observations and actual test dates; do not pre-fill results as passed.

- [x] Update controls, map picker, countdown, sound/mute, retry/rejoin instructions, and the full test-script list in README. Document the intentional countdown amendment to the previous immediate-start flow.
- [x] Run every headless script using the command below; require exit code 0 from the whole loop and no assertion failures. Confirm generated UIDs accompany new scripts and that M6 preserves slide mechanics and Nightfall's clear radius while implementing the requested surface/motion/falloff changes.
- [x] Export the Web build with the matching templates and test create/join/countdown/play/results/replay from 2, 6, 8, and 10 clients. Verify 7/9-player boundary profiles and 11th-player rejection through M5. Record any unavailable export capability as unverified, not passed.
- [x] Use a local test harness/network shaper to test movement with 0/100/150 ms RTT and 0/±30 ms jitter, plus a 250+ ms stall. Apply delay to both input and snapshot directions; do not infer end-to-end latency from delayed rendering alone. Keep the harness out of production behavior.
- [ ] Run at least three rounds each at 2, 6, and 10 players with people. Record time to join, wrong-direction/missed-input reports, whether each person can identify their duck and map mechanic before GO, whether they understand why they died, and whether retry needs developer help. If enough humans are unavailable, distinguish technical multi-client coverage from an outstanding human playtest at that count.
- [ ] Accept the milestone only when there are no stuck inputs/duplicate starts/duplicate sounds, the UI fits at 960 × 704, room/score rules still pass, and feedback is understandable to the participants. Record observed round length and waiting time without changing balance under this plan.
- [x] Include explicit M6 questions in the acceptance record.
- [ ] Obtain and record answers: can players identify ice before stepping on it, distinguish the forced slide from walking, and see the Nightfall outer fade while still finding the map suspenseful? Record whether the brighter center feels unchanged and whether faint outer objects reveal too much.
- [ ] Commit documentation and validation evidence: `docs(game): document player experience improvements and validation`. **Deferred by instruction: leave the working tree uncommitted; not an implementation blocker.**

## Verification commands

Run individual scripts from the repository root during each task:

```sh
rtk proxy /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/online_test.gd
```

Use the matching test path named by the task. Expected: process exit code **0**, each script reports no failures. Confirm the added regression fails before implementing its behavior; a parse error in unrelated code is not the intended red test.

Run the complete suite with failure propagation:

```sh
rtk proxy zsh -c 'failed=0; for t in tests/*_test.gd; do /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || { echo "FAIL $t"; failed=1; }; done; exit "$failed"'
```

Web export after implementation, when matching templates are installed:

```sh
rtk proxy /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Web build/web/index.html
```

## Completion boundaries

- Writing and reviewing this document completes the requested planning task. Implementation, commits of product changes, and deployment are subsequent work.
- The implementation is complete only after the included milestone criteria and recorded validation are satisfied; automated tests alone do not establish that the game feels better.
- **Item 4 feedback is incorporated in M6.** Ice/material and sliding feedback plus a longer Nightfall outer fade are included. Faster/longer sliding, a larger fully clear starting circle, and unrelated map-balance changes remain outside scope.
