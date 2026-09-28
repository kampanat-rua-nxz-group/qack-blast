# AGENTS.md

Qack Blast: a 2–4 player bomb battle in Godot 4.7.2 (GDScript, GL Compatibility renderer). `README.md` holds run, export, and play instructions plus the module ownership map — read it first.

## Layout

- `scripts/arena_game.gd` — pure rules engine, runs without a scene. Put gameplay rules here.
- `scripts/arena.gd` — local two-player scene (`scenes/arena.tscn`) on top of the rules.
- `scripts/room_registry.gd`, `room_server.gd`, `server_main.gd` — authoritative server: rooms/scores, command validation, headless entry point.
- `scripts/room_client.gd`, `online_app.gd`, `lobby_art.gd` — client lobby and snapshot rendering (`scenes/online.tscn`, the main scene).
- `docs/superpowers/specs/` and `plans/` — design specs and implementation plans; check the relevant spec before changing behaviour.

## Conventions

- The server owns game state; clients send commands and render snapshots. Keep rule logic out of client code.
- Tests are plain `extends SceneTree` scripts with a local `check(condition, message)` helper and `quit(1)` on failure — no test framework. Add new cases as `test_*` functions in the matching file under `tests/`.
- Keep each `*.gd.uid` file alongside its script; move or rename them together.
- `.godot/` and `build/` are generated and git-ignored.
- Commits follow Conventional Commits with a scope, e.g. `feat(arena): ...`, `test(arena): ...`.

## Checks

Run every test script headless before calling work done (full list in `README.md` → Checks):

```sh
for t in tests/*_test.gd; do /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || echo "FAIL $t"; done
```
