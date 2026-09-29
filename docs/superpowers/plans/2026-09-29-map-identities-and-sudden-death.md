# Map Identities and Sudden Death Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give all five maps their approved effect and pickup, and end rounds through map-specific sudden death while more than one duck survives.

**Architecture:** `scripts/arena_game.gd` owns all terrain, pickups, bomb motion, wall changes, timed hazards, and round resolution. `scripts/room_registry.gd` serializes new state; `scripts/online_app.gd` reconstructs snapshots; `scripts/arena.gd` draws it. Extend the existing board and player dictionaries rather than adding a second rules engine.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility renderer, plain `SceneTree` test scripts.

**Spec:** `docs/superpowers/specs/2026-09-29-map-identities-and-sudden-death-design.md`

## Global Constraints

- The server alone owns gameplay state; clients send commands and render snapshots.
- Keep the original bomb-capacity and blast-range pickups and their caps; crate item drop chance stays 20%.
- First sudden-death warning is at 3:00, strike at 3:05, then a wave every 15 seconds with a five-second warning.
- Never resolve a round with multiple ducks alive; allow a draw only when the final ducks die in the same update.
- Run every `tests/*_test.gd` script headless before completion. Preserve each `*.gd.uid` beside its script.
- The approved Nightfall spotlight edit already exists uncommitted in `scripts/arena.gd` and `tests/arena_test.gd`; preserve it.

## Review Focus

- A large `delta` crosses multiple scheduled events: each warning and strike is scheduled once, in order (Task 2 test).
- A Nightfall wall reshuffle catches a duck between tile centers: neither occupied tile nor movement target becomes a wall (Task 6 test).
- A kicked bomb's fuse expires between movement ticks: it explodes at its current tile with its original owner (Task 5 test).
- A Pond duck stands on the ring that floods next: it dies at strike time, not warning time (Task 4 test).
- An online spectator or eliminated player receives the same hazard board and sees the whole Nightfall board (Tasks 6 and 7 tests).

---

### Task 1: Finish the existing Nightfall spotlight change

**Files:** Modify `scripts/arena.gd`, `tests/arena_test.gd` only as needed.

**Interfaces:** `vision_darkness(point: Vector2) -> float`; `visible_tile(tile: Vector2i) -> bool` delegates to the circular mask. No new rule-engine interface.

- [ ] **Step 1: Review the current uncommitted spotlight diff** against the spec: soft circular edge, local union, online viewer only, spectators unrestricted, warnings above darkness.
- [ ] **Step 2: Run the existing red-green test**: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/arena_test.gd`; expect `Arena checks: 0 failure(s)`.
- [ ] **Step 3: Correct any visual or performance issue found in local play** without changing vision pickup range, then rerun the arena test.
- [ ] **Step 4: Commit only the spotlight files** with `feat(arena): soften nightfall vision`.

### Task 2: Shared timed hazards and earlier Classic pressure

**Files:** Modify `scripts/arena_game.gd`, `scripts/arena.gd`, `scripts/room_registry.gd`, `scripts/online_app.gd`, `tests/arena_test.gd`, `tests/online_test.gd`.

**Interfaces:** Add `const SUDDEN_DEATH_START = 180.0`, `const HAZARD_INTERVAL = 15.0`, `const HAZARD_WARNING = 5.0`; `var hazards: Array = []` with entries `{kind: String, tiles: Array[Vector2i], time: float}`; `schedule_hazards(previous_elapsed: float) -> void`; `resolve_hazard(hazard: Dictionary) -> void`. Keep `warning_tiles() -> Array[Vector2i]`, now merging Classic danger warnings and `hazards`.

- [ ] **Step 1: Write failing tests**: Classic has no danger bomb at 179.9, warns at 180.0, strikes at 185.0, doubles bomb count on later waves, and retains simultaneous-final-death draw. Test a large time step crossing two waves without duplicate schedules. Test `hazards` and warnings survive a server snapshot and client reconstruction.
- [ ] **Step 2: Run arena and online tests**; expect the new timing/snapshot assertions to fail.
- [ ] **Step 3: Implement the shared schedule and snapshot fields**. Classic uses its existing danger-bomb path with the new timing and counts. `step` advances scheduled hazards once per boundary and resolves expired events before `resolve_round`; the renderer draws generic warning tiles above Nightfall darkness.
- [ ] **Step 4: Run arena and online tests**; expect zero failures.
- [ ] **Step 5: Commit** `feat(arena): add timed map hazards` with only Task 2 files.

### Task 3: Random map mystery pickup and burst hazard

**Files:** Modify `scripts/arena_game.gd`, `scripts/arena.gd`, `tests/arena_test.gd`, `tests/online_test.gd`.

**Interfaces:** `const PICKUP_MYSTERY = 3`; `resolve_hazard` handles `kind == "random_burst"`; the shared `hazards` snapshot carries warning tiles. `draw_pickup` and warning rendering recognize the new kind.

- [ ] **Step 1: Write failing tests**: Mystery picks a non-capped bomb/range upgrade, respects both caps, and is consumed. At 3:00 the first Random burst warns one open tile, later waves mark 2 then 4, and a burst kills a duck on a marked tile while keeping other survivors playing. Assert a burst can trigger a player bomb and clear a crate.
- [ ] **Step 2: Run arena and online tests**; expect failures for missing pickup and hazard behavior.
- [ ] **Step 3: Implement Random rules and visuals**. Keep round-start wall reroll. Add Mystery to the 20% drop pool only on Random; use the server RNG to choose its upgrade and burst targets. Render its icon and marked tiles.
- [ ] **Step 4: Run arena and online tests**; expect zero failures.
- [ ] **Step 5: Commit** `feat(arena): add random map mystery and bursts`.

### Task 4: Lily Pond shallow water, speed pickup, and flooding

**Files:** Modify `scripts/arena_game.gd`, `scripts/arena.gd`, `scripts/room_registry.gd`, `scripts/online_app.gd`, `tests/arena_test.gd`, `tests/online_test.gd`.

**Interfaces:** Add `var terrain: Array = []` of row arrays (`0` normal, `1` shallow water, `2` ice); `const PICKUP_SPEED = 4`; players gain `speed_bonus: float` (0.0 to 0.5); `const DEEP_WATER = 3` in `board`; `resolve_hazard` handles `kind == "flood"`. Snapshot includes `terrain` and `speed_bonus`.

- [ ] **Step 1: Write failing tests**: shallow water takes 1/0.8 times the normal travel time; one Speed pickup gives +25% base speed everywhere, two cap at +50%; dry spawn exits remain. Warned flooding causes no early death, then eliminates a duck on its ring; deep water remains blocked and is serialized online. Test the two board sizes.
- [ ] **Step 2: Run arena and online tests**; expect missing terrain/speed/flood assertions to fail.
- [ ] **Step 3: Implement Pond rules and visuals**. Define a fixed shallow-water pattern on eligible open tiles; apply the water multiplier after `speed_bonus`. Schedule outer rings at 15-second intervals, render shallow/deep water and Speed pickup, and send terrain plus upgrade in snapshots.
- [ ] **Step 4: Run arena and online tests**; expect zero failures.
- [ ] **Step 5: Commit** `feat(arena): add pond water and speed pickup`.

### Task 5: Frost Garden ice, bomb kick, and blizzard

**Files:** Modify `scripts/arena_game.gd`, `scripts/arena.gd`, `scripts/room_registry.gd`, `scripts/online_app.gd`, `tests/arena_test.gd`, `tests/online_test.gd`.

**Interfaces:** `const PICKUP_BOMB_KICK = 5`; players gain `can_kick: bool`; moving bomb dictionaries gain `kick_direction: Vector2i` and `kick_progress: float`; `try_kick_bomb(tile: Vector2i, direction: Vector2i) -> bool`; `resolve_hazard` handles `kind == "blizzard"`. Reuse Task 4's terrain values and snapshot pipeline.

- [ ] **Step 1: Write failing tests**: entering ice adds exactly one passable tile of motion; blocked extra tiles stop normally. A duck without Bomb Kick cannot move a bomb; with it, the bomb travels at four tiles per second to the last open tile before each blocker type, retaining fuse and owner. Test explosion during travel, collision with another bomb, and inability to kick a neutral danger bomb. Blizzard warns rows, doubles targeted row count per wave, and triggers bombs on struck rows.
- [ ] **Step 2: Run arena and online tests**; expect the ice, kick, and blizzard cases to fail.
- [ ] **Step 3: Implement Frost rules and visuals**. Keep discrete authoritative bomb tiles, accumulate `kick_progress` in `step`, move at quarter-second tile intervals, and resolve fuse expiry at the current tile. Send kick state in snapshots; draw ice, moving bombs, Bomb Kick icon, and blizzard warning.
- [ ] **Step 4: Run arena and online tests**; expect zero failures.
- [ ] **Step 5: Commit** `feat(arena): add frost sliding and bomb kick`.

### Task 6: Nightfall minute reshuffle and closing walls

**Files:** Modify `scripts/arena_game.gd`, `scripts/arena.gd`, `tests/arena_test.gd`, `tests/online_test.gd`.

**Interfaces:** `reshuffle_night_walls() -> void`; `resolve_hazard` handles `kind == "closing_walls"`. Use the existing board snapshot; no client-side wall generation.

- [ ] **Step 1: Write failing tests**: Nightfall produces no Classic danger bombs, reshuffles at 60 and 120 seconds but not before or after sudden death, and changes wall positions across seeded rounds. Each reshuffle protects player overlap tiles, move targets, crates, pickups, bombs, and flames while keeping non-wall cells connected. Closing walls warn five seconds, eliminate ducks on closure, and persist in board snapshots. An online eliminated viewer sees the whole board.
- [ ] **Step 2: Run arena and online tests**; expect failure for missing reshuffle/closure behavior.
- [ ] **Step 3: Implement Nightfall rules and visuals**. Remove only interior permanent walls before each normal reshuffle, then reuse the seeded connectivity check with protected cells. After 3:00, close one outer ring per wave with warning marks; render those marks over the darkness mask.
- [ ] **Step 4: Run arena and online tests**; expect zero failures.
- [ ] **Step 5: Commit** `feat(arena): reshuffle and close nightfall walls`.

### Task 7: Integration, playtest, and documentation

**Files:** Modify `README.md`, `tests/rooms_test.gd`, `tests/network_test.gd` only where integration assertions need it; correct previous-task files if a verified integration gap appears.

**Interfaces:** No new interface; verify complete snapshots and round transitions through the existing room/server/client API.

- [ ] **Step 1: Add failing end-to-end assertions** for a host selecting each map, receiving its special pickup and timed hazard in snapshots, and progressing to results only after one survivor or simultaneous final deaths. Include a disconnected player's spectator view.
- [ ] **Step 2: Run room, network, and online tests**; expect new assertions to fail before any integration fix.
- [ ] **Step 3: Fix only verified integration gaps**, update README map descriptions and checks, and inspect all five maps in local play for warnings, items, and movement readability.
- [ ] **Step 4: Run `for t in tests/*_test.gd; do /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || echo "FAIL $t"; done`**; expect every script to report zero failures. If localhost binding is blocked by the sandbox, rerun `tests/network_test.gd` with the needed permission and report the exact result.
- [ ] **Step 5: Review `git diff --check`, commit** `docs(arena): explain map effects and sudden death`, and hand off the branch for final review.
