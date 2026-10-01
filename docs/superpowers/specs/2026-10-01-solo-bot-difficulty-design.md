# Solo play and bot difficulty

October 1, 2026 · Design and tuning proposal

## Intent and scope

Let a player play Qack Blast alone against a bot with Easy, Medium, Hard, or Extreme difficulty. Extreme is a challenge for experienced players: it wins through fast reactions, planning, and traps, while following the same rules and using the same visible information as a human.

The user agreed to the four difficulties and the expert audience for Extreme. The integration choices below are proposed defaults grounded in the current code: one configurable bot per room, exposed in the existing main lobby, with server-backed solo play. Multiple bots and offline solo play are follow-up work. This document specifies future behavior; it does not claim the bot exists or that tuning has been playtested.

## Current architecture and selected approach

The current README and rules support 2–10 players, five maps, a three-second countdown, persistent in-room Wins/Kills, and rematches. `room_registry.gd` builds the lineup, expires human input after 0.2 seconds, and advances `ArenaGame`. `room_server.gd` validates network commands. `online_app.gd` renders room/game snapshots. The original two-keyboard scene remains a separate local mode.

Use one shared bot controller with difficulty profiles, hosted by the room registry. It produces the same direction, move-press, and plant intent consumed by `ArenaGame.step()`. The controller never edits authoritative state.

Alternatives considered:

- A local-scene-only bot would avoid room changes, but would leave solo play outside the main lobby and require a second integration later.
- Four independent bot implementations would allow distinct algorithms, but multiply navigation, safety, and map maintenance.
- A shared server controller with profiles fits the existing main experience and keeps one safety/navigation implementation. This is the selected approach.

## Player flow

1. Create a room with the existing nickname flow.
2. In the waiting lobby, the host selects **ADD BOT**. It creates one bot at **Medium** difficulty.
3. The bot row shows its name, a **BOT** badge, and an **Easy / Medium / Hard / Extreme** selector. A host-only **REMOVE BOT** action removes it.
4. Select a map and start. One connected human plus the bot satisfies the two-player minimum. The existing three-second countdown applies to both.
5. Results show the bot's Wins/Kills with its BOT badge and difficulty. The host can change difficulty or remove the bot before **PLAY AGAIN**.

Only the host can add, remove, or change difficulty, and only in `lobby` or `results`. Controls are disabled during `countdown` and `playing`; the server rejects forged requests too. No automatic start, auto-fill, or automatic replacement of a disconnected human occurs. Friends may join a room containing a bot under the existing rules; a late join still spectates until the next round.

Server-backed solo play requires the existing room server. Keep the local two-keyboard mode intact. Do not advertise offline solo support.

## Difficulty profiles

Canonical identifiers are `easy`, `medium`, `hard`, and `extreme`. Display spelling is **Extreme**, not “Extream”. All values are starting tuning values, not measured difficulty guarantees.

| Profile | Decision interval, uniformly sampled | Opponent prediction | Attack behavior | Candidate bomb positions |
| --- | --- | --- | --- | ---: |
| Easy | 0.60–0.90 s | None | Break nearby crates; attack an opponent already in blast alignment | 1 |
| Medium | 0.30–0.45 s | Current position | Seek useful upgrades and a safe attack position | 4 |
| Hard | 0.15–0.25 s | Up to 0.50 s of visible movement | Pressure exits; combine a new bomb with existing visible bombs | 8 |
| Extreme | 0.08–0.15 s | Up to 1.00 s of visible movement | Contest upgrades and choose bomb positions that restrict predicted escape routes | 12 |

Prediction branches at legal intersections rather than assuming the opponent will continue forever in one direction. Extreme scores all reachable opponent exits within its prediction horizon and favors fewer safe exits; it cannot guarantee a kill against future input it cannot observe. Multi-bomb tactics mean successive legal placements coordinated with existing bombs, within the bot's actual capacity, not simultaneous commands beyond the rules.

All levels share a complete forecast of currently known bombs, including chain reactions. This deliberately replaces the earlier suggestion that Easy only notices imminent explosions: Easy should be less strategic and slower, not intentionally suicidal. On decision boundaries, priorities are:

1. Escape known danger or a warned permanent closure.
2. Preserve a safe route and avoid being trapped.
3. Pursue a useful pickup, crate-clearing position, or attack position.
4. Plant only after verifying an escape with the candidate bomb included.

There is no deliberate unsafe-command probability. Slow reactions can still cause Easy to miss an opportunity to escape. Every level respects active flames and warnings. All levels remain beatable through ordinary play; Extreme's target audience is experienced players rather than beginners.

## Components and contracts

Create focused, scene-independent `extends RefCounted` scripts:

- `bot_profiles.gd`: canonical profile values and validation. `get_profile(difficulty: String) -> Dictionary` returns a copy or `{}` for an invalid ID; `is_valid(difficulty: String) -> bool` validates.
- `bot_observation.gd`: the only adapter allowed to read `ArenaGame` for AI. `capture(game, slot: int, memory: Dictionary) -> Dictionary` returns a detached, permitted observation and updates only caller-owned memory.
- `bot_navigation.gd`: forecasts known danger and searches routes in time. `forecast(observation: Dictionary, candidate: Dictionary = {}) -> Dictionary`; `find_route(observation: Dictionary, forecast: Dictionary, goal_tiles: Array, max_nodes: int = 8192) -> Dictionary`. Route output contains `found`, `tiles`, `arrival_times`, and `expanded_nodes`.
- `bot_controller.gd`: owns RNG, reaction clock, observation history, and selected route. `configure(slot: int, difficulty: String, seed_value: int) -> bool`; `reset() -> void`; `advance(delta: float, observation: Dictionary) -> Dictionary`. Output is exactly `{"direction": Vector2, "move_press": Vector2, "plant": bool}`. Directions are neutral or cardinal; plant and move-press are single-use intents.

Controller code receives observations, never a live game, registry, human input buffers, or game RNG. `ArenaGame` remains the owner of movement, blast geometry, damage, pickups, and scores. Extract only narrowly reusable pure rule helpers if needed, with parity tests, rather than making the bot a second rules engine.

## Fair observation

On normal maps, observe the rendered board, terrain, living ducks, public upgrades, bombs, flames, pickups, and announced hazard tiles/timers. Never expose crate contents, RNG state, future random walls/hazard selections, network input, or opponents' pending movement targets. Infer movement from consecutive visible positions. Own position, own upgrades, own in-progress move/slide, and own bomb-egress state are available for accurate control.

On Nightfall, use `NightVisibility.darkness_at()` and the bot's own position and Sight upgrade. A tile or dynamic entity is observable only while its center has darkness less than 1.0. Announced hazard markers remain globally observable, matching their rendering above darkness. Unknown board/terrain cells use `-1` and are treated as blocked until seen; a known safe route may lead to the frontier so the bot can explore.

Remember previously seen static tiles, but invalidate unseen interior wall knowledge at the public 1:00 and 2:00 reshuffle boundaries. Keep boundary-wall knowledge and never learn a hidden changed tile from authoritative state. Forget an opponent as an attack target when it leaves visibility. A previously seen bomb may be projected from its last known state until its expected detonation, but unseen kicks, chain triggers, or removals cannot update that memory. Deduplicate remembered and visible bombs. Sound does not grant exact hidden positions in this release.

Identical permitted observation/history and bot RNG seed must yield identical commands, even when hidden authoritative state or queued human input differs. This fairness property applies to Extreme too.

## Navigation and escape safety

Plain breadth-first search is insufficient for travel time, water, timed explosions, and forced ice movement. Use a bounded time-expanded shortest-path search with cardinal moves and waiting. Quantize arrival time upward to 0.05 seconds; never round travel duration down. Begin with any remaining committed tile move and compulsory ice slide before exploring a new direction. Respect the bot's collision radius and the tile occupied at every segment, not only the final destination.

Forecast danger intervals through the latest known bomb/hazard resolution plus flame lifetime and a 0.20-second safety margin, capped at 6.0 seconds. An event beyond this cap invalidates an escape proof that depends on it; do not declare that route safe. Flood and closing-wall tiles remain blocked after their strike. Unknown future random events are not forecast. Unknown cells block both navigation and outgoing blast rays conservatively.

Required rule parity:

- Normal bombs use stored blast range, stop at walls and the first crate, and trigger chains. Crates present at the start of the same explosion batch block every blast in that batch.
- Classic neutral danger bombs strike the whole row and column, regardless of ordinary wall/range limits; they cannot be kicked.
- Predict moving bombs at four tiles/second using kick direction/progress and continuing fuse. Recompute chains at their predicted positions. A known hazard may trigger a player bomb early.
- Apply Lily's 94 px/s base, 0.8 water multiplier, and the duck's speed bonus. Account for a water boundary crossed within a tile move.
- Apply Frost's compulsory single extra tile on ice. In this release, avoid initiating a kick as a planned action; an unavoidable already-started motion still follows the actual rules.
- Own newly planted bombs permit egress while the duck overlaps them; after leaving, they block re-entry like other bombs.

Require a hypothetical-placement route that remains outside every known blast for its active interval, including the new bomb's chain-adjusted time and resulting flame lifetime. Check safety after movement, at the position where `ArenaGame.step_slice()` would plant; avoid issuing plant during a committed move/slide in this release. Attack plans must be revalidated against a fresh observation when actually placing, not only when selecting a remote attack tile.

Search limits are 8192 expanded states per route and the profile's candidate count per decision. Reuse the base forecast within a decision. If the budget is exhausted or safety cannot be proved, do not plant; select the best proven survival route or hold neutral when none exists. These are logical bounds, not measured latency guarantees; benchmark before tuning upward.

## Reaction and command scheduling

Sample the next interval only at a decision boundary using bot-owned RNG. The first decision is due immediately after GO; the next interval is sampled then. No decisions or reaction-clock advancement occur during countdown, results, or elimination.

Between decisions, continue the last chosen movement command without examining newly observed danger. This makes the interval a real reaction delay. A new decision sees the latest allowed observation. Never bypass the delay through an emergency replanning branch. Already committed movement still completes under normal rules even if the held direction changes.

Emit a plant or move-press only in the tick that chooses it. Preserve direction until the next decision. On a large `delta`, make at most one decision using current information and discard overdue decisions; do not retroactively plant multiple bombs or perform catch-up actions. A new round resets clocks, routes, memory, and controllers while retaining participant identity and scores.

## Room lifecycle and protocol

Each person gains `kind: "human" | "bot"`; missing `kind` is treated as human for compatibility. Bots have `peer: 0` and a validated `difficulty`. Never infer that a bot is an offline human from `peer == 0`.

Add host-only registry methods `add_bot(peer_id: int, difficulty: String = "medium") -> Dictionary`, `remove_bot(peer_id: int, person_id: int) -> Dictionary`, and `set_bot_difficulty(peer_id: int, person_id: int, difficulty: String) -> Dictionary`. They return `{ok: bool, error?: String}`. A room has at most one active bot. Use the existing monotonic person ID, unique naming rules (base name `Bot`), unused avatar selection, and persistent score dictionary.

Admission counts connected humans, including spectators, plus the active bot against the existing ten-seat limit. Offline human history consumes no admission seat. Round lineups include connected humans and the active bot, requiring at least one human and 2–10 total competitors. Removing the bot deletes its participant record and scores; adding again gives a new identity and fresh scores. Difficulty changes preserve its existing identity, avatar, and scores and affect the next round only.

Host selection and empty-room cleanup consider connected humans only. Bots never become host, acquire disconnect grace, receive socket packets, or keep a room alive after the last human leaves. Preserve human disconnect, late-join, and countdown-cancellation behavior. Clearing/cancelling a lineup also clears bot controllers and pending commands.

Before each active game step, expire human input as today, then write bot commands into its lineup slot. Bot held direction must not pass through the 0.2-second human input expiry. Never map a network peer to the bot slot. Use neutral bot input after elimination or round end.

Network messages:

- `{"type":"bot_add","difficulty":"medium"}`
- `{"type":"bot_remove","person_id":123}`
- `{"type":"bot_difficulty","person_id":123,"difficulty":"extreme"}`

Require valid string difficulty and positive integer person ID; reject malformed types, unknown IDs, non-bot targets, a second bot, insufficient capacity, non-host callers, and active-round mutations without changing state. A rejected request uses the existing error channel.

Room snapshots add `kind`, `difficulty` (empty for humans), and `ready_player_count`. `connected` retains its transport meaning: false for a bot. Lobby start and results replay gates use `ready_player_count`, not a count of connected sockets. Old snapshots fall back to the existing connected-human count. Bot labels take precedence over offline labels. Bots use ordinary game slots, snapshots, feedback, score attribution, and avatar rendering.

## Validation and acceptance

- Plain SceneTree tests cover profile values, seeded scheduling, hidden-information independence, route safety, observation memory, every map's navigation/danger behavior, command legality, and no authoritative mutation by the AI.
- Room tests cover one-human start, capacity with spectators/offline history, ten-player geometry, host restrictions, cancelled countdown, human-only host transfer/cleanup, bot score persistence, and removal/re-add identity.
- Loopback network and UI tests cover bot messages, metadata, disabled controls, solo start, results/replay, and rejection of forged commands. Human-only rooms remain compatible.
- Run every `tests/*_test.gd` headless before implementation is complete. The implementation plan identifies focused tests per task.
- Run seeded bot smoke rounds on all five maps and 2- and 10-player layouts. Record decision counts, expanded states, and decision-time percentiles; do not infer human difficulty from bot-vs-bot results.
- Human playtests must confirm Easy is approachable, Medium supports casual solo play, Hard provides practice, and Extreme challenges experienced players through decisions. Check Nightfall fairness, visible warnings, UI layout, and browser responsiveness.

## Non-goals

No learning model, external AI service, extra bot speed/damage/capacity, reading future input, multiple-bot management, automatic disconnected-player takeover, offline transport, ranked matchmaking, or win-rate guarantee. Do not rewrite unrelated room or rendering code.
