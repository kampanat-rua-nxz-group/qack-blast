# Solo bot acceptance record — 2026-10-01

This record separates automated technical evidence from human acceptance. It does not claim that the difficulty profiles have been playtested.

## Scope

One human can add one server-controlled bot to a room. The host can choose Easy, Medium, Hard, or Extreme, then play and replay through the existing lobby/results flow. Bots use normal game slots, rules, maps, score attribution, and the same authoritative snapshots as human players. Offline solo play and multiple bots are out of scope.

## Automated technical evidence

The seeded smoke test completed 80 fixtures: seeds 7, 42, 101, and 2026; all five maps; all four difficulties; and 2- and 10-player layouts. Each fixture waited through countdown and advanced up to ten simulated seconds at 1/60-second ticks. It checked pre-GO idleness, cardinal commands, geometry/map consistency, candidate/search bounds, and natural round progression.

Coverage also includes visibility-limited Nightfall observations, timed escape proofs, room cleanup when the last human leaves, bot seat admission, WebSocket command validation, and lobby/results controls. The relevant plain SceneTree scripts are `tests/bot_test.gd`, `tests/rooms_test.gd`, `tests/network_test.gd`, `tests/online_test.gd`, `tests/results_test.gd`, `tests/ten_player_test.gd`, and `tests/ten_network_test.gd`.

The final complete suite ran all 14 `tests/*_test.gd` scripts with a failure-propagating wrapper and exited 0. Every script reported zero failures; the saved run had no `FAIL` or `SCRIPT ERROR` lines. Godot emitted one platform TCP no-delay warning in the connection test.

The localhost loopback test exercised a host adding Medium, selecting Lily Pond, starting a two-player countdown/game, reaching results, changing the bot to Extreme, replaying, and removing the bot after replay. This is protocol-level automation with headless clients. Registry tests separately cover last-human cleanup and bot identity/score lifecycle. Nightfall visibility/fairness is covered by automated observation and controller tests.

## Benchmark

Measured on the current Godot 4.7.2 workspace build. Each cell reports p50/p95/max milliseconds over 20 decisions. Candidate and expanded columns are totals across those decisions. The expanded count is work across multiple bounded routes, not a single route's expansion limit.

| Map | Difficulty | 2-player candidates / expanded | 2-player p50 / p95 / max ms | 10-player candidates / expanded | 10-player p50 / p95 / max ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Classic | Easy | 20 / 808 | 1.112 / 1.966 / 2.240 | 20 / 1,954 | 2.574 / 5.222 / 5.640 |
| Classic | Medium | 80 / 808 | 1.212 / 2.029 / 2.063 | 80 / 1,954 | 2.661 / 4.753 / 5.032 |
| Classic | Hard | 160 / 808 | 2.385 / 3.135 / 3.206 | 160 / 1,954 | 4.956 / 7.009 / 7.073 |
| Classic | Extreme | 240 / 808 | 2.870 / 3.663 / 3.694 | 240 / 180 | 4.008 / 4.107 / 4.132 |
| Random | Easy | 20 / 857 | 1.115 / 2.015 / 2.043 | 20 / 2,017 | 2.849 / 5.020 / 5.056 |
| Random | Medium | 80 / 857 | 1.166 / 2.052 / 2.082 | 80 / 2,017 | 3.026 / 5.184 / 5.712 |
| Random | Hard | 160 / 857 | 2.554 / 3.376 / 3.701 | 160 / 2,017 | 5.342 / 7.377 / 7.479 |
| Random | Extreme | 240 / 857 | 2.920 / 3.790 / 3.928 | 240 / 200 | 3.867 / 3.929 / 3.979 |
| Lily Pond | Easy | 20 / 816 | 1.358 / 1.434 / 1.437 | 20 / 1,498 | 2.495 / 2.749 / 2.776 |
| Lily Pond | Medium | 80 / 816 | 1.479 / 1.922 / 1.983 | 80 / 1,498 | 2.653 / 2.768 / 2.991 |
| Lily Pond | Hard | 160 / 816 | 2.501 / 2.694 / 2.708 | 160 / 1,498 | 4.345 / 4.475 / 4.539 |
| Lily Pond | Extreme | 240 / 816 | 2.985 / 3.157 / 3.345 | 240 / 200 | 3.277 / 3.446 / 3.468 |
| Frost Garden | Easy | 20 / 1,024 | 1.842 / 2.616 / 2.628 | 20 / 2,361 | 3.706 / 7.501 / 7.583 |
| Frost Garden | Medium | 80 / 1,024 | 1.926 / 2.708 / 2.762 | 80 / 2,361 | 3.962 / 7.147 / 7.170 |
| Frost Garden | Hard | 160 / 1,024 | 2.931 / 3.765 / 3.811 | 160 / 2,361 | 6.776 / 9.026 / 9.200 |
| Frost Garden | Extreme | 240 / 1,024 | 3.435 / 4.230 / 4.238 | 240 / 200 | 3.318 / 3.381 / 3.408 |
| Nightfall | Easy | 20 / 140 | 0.387 / 0.394 / 0.398 | 20 / 140 | 0.674 / 0.699 / 0.701 |
| Nightfall | Medium | 80 / 140 | 0.484 / 0.495 / 0.573 | 80 / 140 | 0.865 / 0.884 / 0.908 |
| Nightfall | Hard | 160 / 140 | 2.320 / 2.481 / 2.528 | 160 / 140 | 5.039 / 5.311 / 5.423 |
| Nightfall | Extreme | 240 / 140 | 3.242 / 3.488 / 3.516 | 240 / 140 | 7.066 / 7.817 / 9.784 |

The repeated 20-decision run's worst p95 was 9.026 ms (10-player Frost Garden Hard); the worst maximum was 9.784 ms (10-player Nightfall Extreme). A previous run produced one isolated 20.913 ms maximum for Random Extreme at 2 players; the repeated run measured 3.928 ms maximum for that group. Timings are device-specific. The optimized figures are below one 16.7 ms server tick in the repeated run, but this synthetic observation benchmark is not a production latency guarantee.

Proposed starting tuning remains unchanged: intervals 0.60–0.90 / 0.30–0.45 / 0.15–0.25 / 0.08–0.15 seconds and candidate limits 1 / 4 / 8 / 12 for Easy through Extreme. The benchmark did not measure human difficulty.

## Manual and human checks

- [ ] Human desktop flow: create room → add bot → change difficulty/map → countdown → play → results → change difficulty → replay → remove bot.
- [ ] Leaving as the last human deletes the room and does not leave a bot-only room.
- [ ] Nightfall does not target opponents outside the bot's visibility.
- [ ] Human-only multiplayer continues to work.
- [ ] Experienced player assesses Extreme; beginner/casual players assess Easy and Medium.
- [ ] Browser export and responsiveness are checked where matching Web export templates are available.

Do not describe Extreme as validated until experienced players have assessed it. Automated simulations verify rule use, determinism, and bounded search; they do not replace human difficulty assessment.
