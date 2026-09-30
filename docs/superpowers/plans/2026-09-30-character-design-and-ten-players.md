# Character Design and Ten-Player Expansion Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development when execution is requested. Steps use checkbox (`- [ ]`) syntax for tracking. This document is an analysis and implementation proposal, not evidence that ten-player support exists.

**Goal:** Support 2–10 online players whose characters remain recognizable during crowded play, while preserving the game's friendly duck identity and existing rules.

**Architecture:** Separate board display scale from authoritative coordinates, extend board/spawn profiles, and introduce a shared cosmetic identity catalog used by the arena and room UI. Enable the higher room limit only after rules and rendering support it.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility, authoritative WebSocket server, existing `SceneTree` test pattern.

**Spec:** The analysis and proposed design decisions below extend the [player experience plan](2026-09-30-player-experience-improvements.md). Existing [map rules](../specs/2026-09-29-map-identities-and-sudden-death-design.md) and [room/results semantics](../specs/2026-09-29-in-room-results-design.md) remain applicable.

**Status — September 30, 2026:** The user requested character-design analysis and a maximum of **10 players**, and selected **ten duck looks with different colors and costumes**. Those are the requested direction and capacity target. Individual costume designs, map sizes, and layout choices below are proposed defaults pending visual/playtest feedback; no new character art or gameplay code has been implemented. The current baseline supports 2–6 players.

## Character design analysis

Evidence comes from the current six-player arena render and `arena.gd::draw_duck`, `draw_player_card`, and `lobby_art.gd::draw_duck`.

| Area | Current assessment | Recommended direction |
|---|---|---|
| Overall identity | Round bodies, little wings, blush, and pastel colors match the friendly lobby. The simple shape survives small rendering sizes. | Keep the round duck family and a shared body/hitbox. |
| Duck recognition | A small triangular beak and a nearly circular head/body can read as a generic chick or round creature at arena scale. This is a visual judgment, not a functional defect. | Try a broader, flatter bill and a modest tail cue; keep eyes and bill readable at actual game size. |
| Player recognition | All six ducks have the same silhouette and facial features; color carries most of the distinction. | Use color plus one large accessory silhouette plus a stable badge. Ten slightly different pastel colors alone are insufficient as the identification plan. |
| Facing | The whole face/body rotates; the bill is the main direction cue. | Preserve a clear bill/front and tail/back relationship in every direction. Accessories must not cover the bill or imply the wrong facing. |
| Motion/personality | Local play has wing/body movement; the online snapshot path currently resets walking animation. | Complete the original movement-presentation task; then add restrained idle, walk, placement, elimination, and victory poses using the same identity. |
| Contrast | Soft colors fit the style, but some bodies compete with similarly colored terrain and flames. | Add a consistent darker outer contour and a local-player ring/marker. Coordinate contrast checks with the original plan's M6 ice and Nightfall presentation changes. |
| Consistency | Lobby and arena independently draw a similar duck at different scales. | Reuse a shared drawing/asset definition for portraits, arena, waiting roster, and results. Avoid designing a detailed portrait that becomes unrecognizable in the arena. |

### Proposed identity system

- Keep all characters mechanically identical. Costume, body color, badge, and animation variation do not change speed, collision radius, bomb count, blast range, or visibility.
- Make identity redundant: **body color + accessory shape + badge 1–10**. The badge is especially useful when colors become hard to distinguish. Show it in the HUD and at spawn; keep the local YOU indicator visible. Avoid ten long floating names covering the board.
- Keep the body and collision footprint visually consistent across all looks. Accessories stay within a defined cosmetic envelope; they never create a misleading extra collision area or hide a nearby bomb.
- Assign appearances on the server. Store `avatar_id` on the participant record independently of the round's slot index; a surviving participant should not change costume when another player leaves or lineup order changes.
- Reserve an appearance while its participant is connected or its old avatar is still part of the current round, including the disconnect grace period. If all ten appearances are reserved, a new spectator may have `avatar_id = -1` until the next lineup is prepared; show a neutral waiting portrait. Release offline round reservations at round end and allocate available identities before the next countdown.
- Historical result rows retain their recorded portrait but are distinguished by participant ID/name and offline status; a reused cosmetic in an old row does not identify the current live player. Concurrent active ducks must always have distinct identities.
- No cosmetic shop, character powers, account persistence, or manual character-selection UI is included in this first expansion.

### Candidate visual set

The user selected the duck/color/costume direction. The individual examples below are silhouette studies to compare at game size, not approved final artwork or ten mandatory named characters.

| Badge | Candidate distinguishing feature | What must remain legible |
|---|---|---|
| 1 | Flat sailor cap | Wide, low top silhouette |
| 2 | Pilot goggles | Two bold connected circles without hiding the eyes/bill |
| 3 | Chef hat | Tall rounded top |
| 4 | Leaf sprout | Two asymmetric leaves |
| 5 | Bow | Two broad side lobes |
| 6 | Sport visor | Short forward brim, distinct from the sailor cap |
| 7 | Crown | Three clearly separated points |
| 8 | Detective hat | Broad brim and narrow crown |
| 9 | Knit cap with pom-pom | Round cap with one offset round accent |
| 10 | Feather crest | Short swept/spiked accent |

Begin with three deliberately different silhouettes, inspect their four facings in motion, then expand the selected style to ten. Reject accessories that collapse into the same blob in a **32 px tile**. Inspect in grayscale and representative color-vision simulations; these inspections are checks, not a claim of accessibility certification. Use original procedural shapes or original/licensed assets with source information.

## Ten-player feasibility and current constraints

The server-authoritative structure can be extended, but changing the room constant alone does not deliver ten-player support.

| Existing constraint | Evidence | Required change |
|---|---|---|
| Room admission stops at six | `room_registry.gd::MAX_CONNECTED = 6`; the seventh join is explicitly rejected by tests | Accept connected participants 1–10 and reject the 11th; require at least two to start |
| Six spawn entries | `arena_game.gd::new_round` resizes an array containing only six positions | Produce valid, unique spawns for every count 2–10; resizing alone does not invent valid positions |
| Six color entries | `arena.gd::COLORS[player_index]` | Use a validated ten-entry identity catalog; do not wrap indices to duplicate live identities |
| Seven overlap offsets | `arena.gd::draw_flame` indexes a seven-element offsets array | Render up to ten player owners plus the neutral owner without fixed-array overflow or unreadable eleven-dot effects |
| HUD only fits three rows per side | Existing compact cards use `y = 82 + row * 192`, height 181 | Fourth-row cards end at y=839; fifth-row cards end at y=1031, outside the 704 px viewport |
| Two board profiles | 13×11 for 2–3, 15×13 for 4–6 | Add profiles and prove spawn safety/connectivity for larger rounds |
| Pixel dimensions also define rules | `CELL`, `SPEED = 188`, and `RADIUS = 15` share coordinates | Scale the board visually without shrinking authoritative cells |
| Snapshot construction runs per peer | `room_server.gd::push_state` sends full room/game data per connected peer at about 20 Hz | Measure ten-client serialization, bandwidth, frame time, and event bursts before proposing networking optimization |
| Old six-player copy/tests | Lobby, arena tagline, README, room and online fixtures | Update capacity-related copy and coverage; preserve the six-character room code |

Shrinking authoritative `CELL` from 44 to 32 while retaining `SPEED = 188` would increase nominal tiles travelled per second by **37.5%**. It also changes collision clearance and bomb escape distances. Display-only scaling avoids that accidental rules change.

### Proposed board profiles

| Players | Board | Interior tiles before walls/crates | Interior tiles/player at upper count | Initial display tile target |
|---|---|---:|---:|---:|
| 2–3 | 13×11, existing | 99 | 33.0 | 52 px, existing |
| 4–6 | 15×13, existing | 143 | 23.8 | 44 px, existing |
| 7–8 | 17×15, proposed | 195 | 24.4 | 38 px |
| 9–10 | 19×17, proposed | 255 | 25.5 | 32 px |

The new profiles roughly preserve the existing six-player interior-area-per-player ratio. This is a starting hypothesis; usable routes, crates, and encounters matter more than raw area. Ten players on 15×13 are not the proposed default because the interior area per player would fall to 14.3 tiles.

- Retain existing authoritative geometry for 2–6 players. Use **44-unit** authoritative cells and existing speed/radius for 7–10; fit the board using a scene transform. Keep whole-board visibility and the existing 960×704 viewport for the initial implementation.
- Reserve the board's current screen region: `Rect2(142, 82, 676, 572)`. Center a 17×15 board at 38 display px per tile or a 19×17 board at 32 px per tile inside it. HUD text remains outside the board transform.
- Carry `width`, `height`, `cell`, and `origin` in authoritative snapshot geometry. The client must not guess geometry only from player count. Use one world-to-display transform for ducks, bombs, pickups, walls, terrain, flames, warnings, and Nightfall masks.
- Larger boards retain the five existing map identities and hazard algorithms. Geometry expansion is in scope. The user has now supplied item 4 feedback: M6 of the original plan adds distinct ice/sliding visuals and a longer Nightfall outer fade, preserving the fully clear starting radius and slide mechanics.
- Larger closing-ring maps contain more rings and may increase late-round duration. Keep the current 3:00 warning start and 15-second interval, record actual durations, and propose later tuning separately if needed.

### Spawns and fairness

- Keep current 2–6 spawn behavior as the regression baseline. For 7–8 and 9–10, use symmetric perimeter candidates rather than appending four arbitrary center positions.
- Initial eight-candidate set for 17×15: corners `(1,1)`, `(15,13)`, `(15,1)`, `(1,13)`, then `(7,1)`, `(9,13)`, `(1,7)`, `(15,7)`.
- Initial ten-candidate set for 19×17: corners `(1,1)`, `(17,15)`, `(17,1)`, `(1,15)`, then `(9,1)`, `(9,15)`, `(1,5)`, `(17,11)`, `(17,5)`, `(1,11)`.
- For odd counts, rotate the omitted candidate using round RNG; assign participants to candidates through a seeded permutation so host/join order does not permanently own the same position. Cosmetic identity is independent of this permutation.
- Protect selected spawn cells before permanent-wall generation. Ensure two distinct legal first moves and a traversable escape from an initial range-1 bomb before its 2.5-second fuse, including a safe destination beyond its blast. Clear the necessary local crate escape paths without removing permanent map identity arbitrarily.
- Validate all selected spawns are inside, open, distinct, dry/non-sliding initially, at least four Manhattan tiles apart on the new profiles, and structurally connected to other spawns. Exercise deterministic seeds across all five maps; do not claim random maps are balanced from one seed.

### UI and effects at ten players

- Keep five compact rows on each side at 7–10 players: at most **108 px high**, **112 px pitch**, starting at y=82. The fifth row ends at y=638, leaving the existing footer clear. Use the existing larger layouts for 2–6.
- Prioritize portrait, badge, readable shortened nickname, and alive/OUT status. The local player's upgrades remain visible; full names and cumulative scores remain available in results. Do not shrink names to unreadable text to force ten detailed cards to fit.
- Make waiting-roster content scroll if needed so ten names plus disconnected history cannot push Start/Leave offscreen. Results already scroll; test ten active rows plus historical offline rows and preserve rank ordering.
- Treat player flames as equally lethal. For crowded overlapping ownership, draw a bounded common lethal effect with limited cosmetic owner accents instead of one dot per owner. Kill attribution remains authoritative and is explained by the original feedback plan.
- Verify accessories and badges at 32 px tile size without hiding bomb fuses, pickups, or warnings. YOU markers and global warnings retain their priority; hidden enemies must remain hidden by Nightfall.

## Global constraints

- Target online capacity is **2–10 connected participants per room**, including spectators; only the current lineup controls ducks. An 11th connection receives the existing full-room error. Offline history does not consume a connection slot.
- Keep the local two-player keyboard mode. This request does not add ten local keyboard/controller assignments.
- Preserve bomb fuse, flame lifetime, pickup caps, Kill attribution, host transfer, disconnect grace, and score persistence. Five simultaneous bombs per player means stress cases may contain **50 player bombs**.
- Keep all original improvement-plan milestones. Ensure countdown, feedback, input, slide presentation, and Nightfall falloff handle 10 slots. Reuse the original plan's M6 visibility/state interfaces rather than implementing competing map effects.
- Every new script requires its `.gd.uid`; use current `SceneTree` tests and run the complete suite before completion.
- Proposed map sizes and costume studies require validation at real size and with players. The requested maximum is ten; the presentation and map proposals are not already proven design decisions.

## Review focus

1. Counts **7, 8, 9, 10, and 11** must exercise the boundary explicitly; keeping only old 2/6-player tests is insufficient.
2. Slot changes, disconnect grace, and late spectators must preserve live visual identities without exceeding ten active ducks.
3. Resizing the rendered board must not change travel time, collision, blast reach in tiles, warning targets, or Nightfall visibility in tiles.
4. All ten player owners plus the neutral owner can overlap on one flame tile without crashes or incorrectly credited Kills.
5. A ten-client round must reach results/rematch correctly and retain every player's score, while the HUD, waiting room, and results remain usable.

## Tasks and integration order

Follow the [execution order across both plans](2026-09-30-player-experience-improvements.md#execution-order-across-both-plans). The lettered task order below does not mean completing this entire document before the main plan. Expansion A/B run in Stage 2, C in Stage 3, D in Stage 5, and E in Stage 6; character concept studies can be prepared earlier.

### Task A: Separate board rendering scale from rules

**Files:** Create `scripts/arena_board.gd` and its UID; modify `scripts/arena.gd`, `scenes/arena.tscn`, `scripts/online_app.gd`, `scripts/room_registry.gd`, `tests/arena_test.gd`, and `tests/online_test.gd`.

**Interfaces:** `ArenaBoard.present(game, display_state: Dictionary, viewer_slot: int) -> void` and `fit_to(region: Rect2, display_cell: float) -> void`. An empty `display_state` uses authoritative positions/facing and existing animation state; Main Task 2 later provides sampled `positions`, `facing`, and `walk_phase` arrays of the same player count. The child Node2D owns board drawing and its transform; parent HUD/text stay unscaled. Snapshot `geometry` has `width`, `height`, `cell`, and JSON-array `origin`.

- [ ] Add `test_display_scale_does_not_change_rules` and `test_snapshot_geometry_round_trip`; compare one-tile movement time, collision, blast tiles, warnings, and Nightfall visible tiles before/after display-scale changes.
- [ ] Run arena/online checks and confirm new geometry/presentation assertions fail.
- [ ] Move board-only drawing into the child while reusing existing primitives. Do not apply a temporary draw transform that duck drawing later resets. Initially render from current authoritative state via the empty-display-state fallback and project every board-space element consistently. The following Main Task 2 plugs in interpolation through the same interface; this task does not require interpolation to exist yet.
- [ ] Rerun affected tests; inspect existing 2/6-player scenes for identical layout and all five map effects. Check overlays are not covered by the board child.
- [ ] Commit: `refactor(arena): separate board display scale from rule coordinates`.

### Task B: Extend rules geometry and spawn generation

**Files:** Modify `scripts/arena_game.gd`, `scripts/room_registry.gd`, `tests/arena_test.gd`, and `tests/rooms_test.gd`.

**Interfaces:** Extend `configure_map(count: int) -> bool` and `new_round() -> bool` to reject unsupported counts before mutating the board; existing valid callers may ignore the success return. Add `spawn_candidates(count: int) -> Array[Vector2i]`. Keep rule coordinates at 44-unit cells for all counts >=4, with the existing origin convention. Carry chosen geometry in snapshots.

- [ ] Add profile checks for every count 2–10 and invalid counts outside that range. Add deterministic spawn uniqueness/clearance/escape/connectivity cases for counts 7–10, all five maps, and seeds 0–99; keep 2–6 regressions.
- [ ] Add ten-player winner/draw/chain-credit, all special pickups, kicked-bomb blocking, Nightfall reshuffle protection, and hazard progression tests on larger geometry.
- [ ] Run rule/room tests and confirm unsupported counts fail; implement profiles, candidate selection, permutation, and spawn escape protection. Do not raise public room capacity yet.
- [ ] Rerun tests and inspect generated maps for all new counts. Record crate-clearing and route fairness observations; the numeric area ratio is not sufficient acceptance evidence.
- [ ] Commit: `feat(arena): support ten-player boards and safe spawn sets`.

### Task C: Shared identities, character direction, and ten-player HUD

**Files:** Create `scripts/character_catalog.gd`, `scripts/duck_art.gd`, and `tests/character_test.gd` with UIDs; modify `scripts/arena.gd`, `scripts/arena_board.gd`, `scripts/lobby_art.gd`, `scripts/online_app.gd`, `scripts/results_ui.gd`, `scripts/room_registry.gd`, `tests/online_test.gd`, and `tests/results_test.gd`.

**Interfaces:** `CharacterCatalog.appearance(avatar_id: int) -> Dictionary` returns badge, palette, and accessory definition; `DuckArt.draw(target: CanvasItem, appearance: Dictionary, pos: Vector2, facing: float, phase: float, size: float) -> void`. Room-person and game-player views include `avatar_id`; local mode uses a deterministic catalog assignment.

- [ ] Add `test_catalog_has_ten_distinct_identities`, `test_avatar_survives_slot_reordering`, `test_disconnect_reserves_live_avatar`, `test_waiting_spectator_gets_identity_before_start`, and `test_history_does_not_steal_active_identity`.
- [ ] Add HUD bounds checks for 7–10 players and render smoke cases for 1–11 simultaneous flame owners including neutral. Verify full result history and exactly one local YOU marker.
- [ ] Produce three duck costume silhouettes at 32/38/44/52 px tiles and four facings, then review at actual size before expanding the chosen style to ten. Keep the user's selected duck/color/costume direction; treat the individual candidate accessories as proposals for review.
- [ ] Implement shared art/catalog, server-assigned identities, compact rows, bounded flame visuals, and scrollable room roster. Keep identical gameplay stats and no character-selection feature.
- [ ] Run character/room/online/results checks. Visually check existing map backgrounds, grayscale, dense explosions, elimination, victory, long names, and ten slots. Confirm the broad bill/front remains visible when accessories rotate.
- [ ] Commit: `feat(characters): add distinct duck identities and ten-player HUD`.

### Task D: Enable and transport ten-player rooms

**Files:** Modify `scripts/room_registry.gd`, `scripts/room_server.gd`, `scripts/room_client.gd`, `scripts/online_app.gd`, `scripts/lobby_art.gd`, `scripts/arena.gd`, `tests/rooms_test.gd`, `tests/network_test.gd`, `tests/online_test.gd`, `tests/connection_test.gd`, `tests/results_test.gd`, and `README.md`.

- [ ] Add admission cases accepting the tenth and rejecting the eleventh connected participant, including spectators, offline history, and a join after departure. Preserve the six-character code and current nickname suffix behavior.
- [ ] Extend loopback integration to ten clients and verify the tenth client's movement/bomb ownership, the 11th-client full-room error, countdown/cancellation, host departure, results, and rematch with preserved scores/identities.
- [ ] Raise `MAX_CONNECTED` to 10 only after Tasks A–C pass. Update capacity copy and assertions without globally replacing every occurrence of `6`; the room code and blast-range cap are unrelated.
- [ ] Rerun all affected checks, including original-plan input/feedback/connection checks with slot 9. Update README to describe the actual supported profiles and local two-player controls.
- [ ] Commit: `feat(rooms): allow up to ten online players`.

### Task E: Capacity and readability acceptance

**Files:** Record actual validation in the original plan's playtest document; add a focused `tests/ten_player_test.gd` and UID for repeatable stress/regression scenarios where existing files do not fit.

- [ ] Run every `tests/*_test.gd` using the full-suite command in the original plan. Require no failures. Ensure malformed or mismatched snapshot geometry does not crash client rendering.
- [ ] Exercise counts 2, 6, 8, and 10 across all five maps through countdown/play/results/rematch. Test both minimum viewport and browser resizing; inspect that frame, HUD, warnings, avatars, and footer fit.
- [ ] Measure ten-client server tick time, per-peer serialized bytes/second, aggregate room outbound bytes, browser frame time, and input/snapshot delay under normal play and 50-bomb/range-6 chain stress. Record device/build details. Aim for p95 server work below a 16.7 ms frame budget and 60 fps client rendering on the selected reference device; these are proposed measured targets, not current performance claims.
- [ ] Run a 10-minute automated room soak with repeated rematches, disconnects, joins, and host changes. Check bounded event queues and no growth caused by retaining presentation history across rounds. Historical scoreboard records may grow by design; separate that from leaked transient state.
- [ ] Repeat the original 0/100/150 ms RTT and jitter checks with ten clients. Optimize only a measured bottleneck; do not introduce compression/delta protocols or lower simulation fidelity speculatively.
- [ ] Playtest with up to ten actual people: can each locate their duck immediately after GO, identify others without color alone, read the bill/facing, and understand crowded eliminations? Record wrong-character reports, early spawn deaths, first encounters, round duration, and spectator waiting time. Ten windows are technical coverage, not a ten-person usability result.
- [ ] Verify M6's ice pattern/sliding cues and gradual Nightfall outer fade remain readable at ten-player display scale. Preserve the fully clear Nightfall radius in tile units and unchanged slide mechanics. Record remaining character-style or larger-map fairness feedback before declaring the expansion ready.

## Relationship to the existing plan

Implement this extension interleaved with the main plan's six-stage schedule. Task A establishes board rendering before Main 2; Task B supplies larger geometry before Task C's ten-slot visual acceptance; Main 3 supplies the YOU marker before Task C incorporates it. Main 4's countdown and Main 5–6's event/feedback system are in place before Task D's full ten-client integration. Main 8–9 complete map presentation before the selected ten-player enablement checkpoint. Task E collects capacity/readability evidence once, which Main 10 incorporates into overall acceptance. Reuse these interfaces rather than implementing a second input, marker, event, countdown, or visibility system.

The original 2/6-player regressions remain; add 8/10-player acceptance and explicit 7/9/11 boundaries. Character visuals and ten-player capacity are new scope. Item 4 feedback is now recorded in the original plan's M6: distinguish ice and actual gliding, keep Nightfall's clear range, and extend the gradual fade into full darkness.
