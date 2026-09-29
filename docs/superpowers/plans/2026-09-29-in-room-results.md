# In-Room Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a separate results scene with a copyable room code and cumulative leaderboard, then let the host change maps or replay in the same room.

**Architecture:** Keep the existing authoritative `results` phase and `map`/`start` commands. A new results scene renders room and game snapshots and emits UI requests; `online_app.gd` owns screen transitions and sends commands. Remove score text from the waiting lobby.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility renderer, plain `SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-29-in-room-results-design.md`

## Global Constraints

- The server owns room phase, map choice, player scores, and round outcomes; clients only send commands and render snapshots.
- Reuse the current room and the existing `map`, `start`, and `leave` commands. Do not reload `scenes/online.tscn` between rounds.
- Show no Wins or Kills in the waiting lobby; show the room code, roster, map, and controls needed to start the first round.
- The results screen uses the existing 960 × 704 duck-themed layout and includes the room code, Copy Code, outcome, leaderboard, selected map, host controls, and Leave Room.
- Sort all room records by Wins descending, Kills descending, then original roster order; include offline records.
- Run every `tests/*_test.gd` script headless before completion.

## Review Focus

- A room snapshot can arrive before the final game snapshot: the results title stays neutral until `round_over` and `result` arrive (Task 2 test).
- A host can leave during results: the new host gains controls and the old host cannot use them (Task 2 test).
- A new player can join during results: the leaderboard gains their zero-score row without losing historical offline rows (Task 2 test).
- Only one connected player can remain: Play Again stays disabled until a second player joins (Task 2 test).
- A rejected map/start command must show an error on the results screen without changing its phase (Task 3 test).

---

### Task 1: Score-free waiting lobby

**Files:**
- Modify: `scripts/online_app.gd`
- Test: `tests/online_test.gd`

**Interfaces:**
- Consumes: existing `RoomClient.room_changed(room: Dictionary)` event.
- Produces: lobby `roster_label` containing names and host/offline markers only.

- [ ] **Step 1: Add a failing assertion** to `tests/online_test.gd`: give two roster members nonzero Wins/Kills, deliver a lobby room view, and check that `roster_label.text` contains their names but neither `Wins` nor `Kills`.
- [ ] **Step 2: Run** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/online_test.gd`; confirm the new assertion fails.
- [ ] **Step 3: Change `_room_changed(room: Dictionary) -> void`** in `scripts/online_app.gd` to format the waiting roster using names and host/offline markers only.
- [ ] **Step 4: Rerun** `tests/online_test.gd`; confirm it passes.
- [ ] **Step 5: Commit** with `feat(lobby): remove scores from waiting roster`.

### Task 2: Dedicated results scene

**Files:**
- Create: `scenes/results.tscn`
- Create: `scripts/results_ui.gd` and `scripts/results_ui.gd.uid`
- Test: `tests/results_test.gd`

**Interfaces:**
- Produces: a `Control` scene with `signal change_map_requested`, `signal play_again_requested`, and `signal leave_requested`.
- Produces: `present(room: Dictionary, game: Dictionary, person_id: int) -> void` and `show_error(message: String) -> void`.
- `present` reads `room.code`, `room.host`, `room.wall_mode`, `room.people`, and the game's `round_over`/`result`; it never mutates those dictionaries or sends network commands.

- [ ] **Step 1: Create failing `tests/results_test.gd` cases** for scene load, code and Copy Code button, clipboard feedback, draw/win/neutral outcome, score ordering with stable ties, offline rows, selected map, and host/guest button state. Include host transfer, a new zero-score join, and the one-connected-player case from Review Focus. Use the repository's `SceneTree` `check`/`quit(1)` pattern.
- [ ] **Step 2: Run** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/results_test.gd`; confirm the scene/API checks fail.
- [ ] **Step 3: Build `scenes/results.tscn`** as a full-size `Control` using `scripts/results_ui.gd`. Reuse `LobbyArt` and `Ui` card/button styles. Give the room code, outcome, map, status, leaderboard grid, and buttons stable node names for UI tests. Display rank/name/Wins/Kills headers and put all roster records in a scrollable area, since disconnected history can make the roster longer than six.
- [ ] **Step 4: Implement `present` and `show_error`** in `scripts/results_ui.gd`. Sort a copy of roster records by Wins, Kills, and roster index; show host/offline labels. Use `ArenaGame.MAP_NAMES` for the selected map. Copy Code uses `DisplayServer.clipboard_set(room.code)` and shows confirmation. Emit signals from host/leave buttons; disable host controls for guests and Play Again when connected count is under two. Show “Round complete” until the authoritative result arrives.
- [ ] **Step 5: Rerun** `tests/results_test.gd`; confirm it passes. Inspect the scene at 960 × 704 so six visible leaderboard rows, scrolling, and all controls fit without overlap.
- [ ] **Step 6: Commit** with `feat(results): add in-room leaderboard scene`.

### Task 3: Wire phase transitions and replay

**Files:**
- Modify: `scripts/online_app.gd`
- Modify: `tests/online_test.gd`
- Modify: `tests/rooms_test.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `res://scenes/results.tscn` and its `present`/`show_error` methods and request signals from Task 2.
- Produces: room-phase visibility: `lobby` → waiting lobby, `playing` → arena, `results` → results scene. Existing commands are sent by `RoomClient.send`.

- [ ] **Step 1: Add failing UI assertions** to `tests/online_test.gd`: results hides lobby and arena; final game snapshot updates the result; the results buttons are connected to the app's command handlers; a new playing room view returns directly to arena; Leave Room and transport loss return to entry; a rejected command displays its error on results. Check guest controls and map changes after subsequent room views.
- [ ] **Step 2: Add room regression assertions** to `tests/rooms_test.gd`: during `results`, host map choice and start succeed, guest attempts fail, room code and connected membership persist, and accumulated Wins/Kills carry into the next round.
- [ ] **Step 3: Run** the two affected test scripts and confirm the new UI assertions fail; the room regression assertions may already pass because the server commands exist.
- [ ] **Step 4: Instantiate the results scene once** in `online_app.gd`, connect its signals to `_change_map`, `client.send({"type": "start"})`, and `client.send({"type": "leave"})`. In `_room_changed`, select exactly one visible screen by phase and call `results.present`. In `_game_changed`, refresh results when the room is in `results`; in `_show_error`, display the error on the visible screen. On leave/disconnect, hide results and reset to entry.
- [ ] **Step 5: Update `README.md`** to describe the results screen, Copy Code, map choice, and replay without returning to the waiting lobby.
- [ ] **Step 6: Run all checks:** `for t in tests/*_test.gd; do /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || echo "FAIL $t"; done`. Confirm no `FAIL` output and each script reports zero failures. Inspect the online results screen at 960 × 704.
- [ ] **Step 7: Commit** with `feat(online): keep players in room for results and replay`.
