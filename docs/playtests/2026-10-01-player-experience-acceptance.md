# Player experience acceptance record — 2026-10-01

This record separates automated technical evidence from human acceptance. Changes remain in the working tree. No deployment or commit was performed.

## Implemented terrain amendment

Lily Pond starts at 50% normal speed: 94 px/s on dry tiles and 75.2 px/s on slowing water. Speed pickups increase this Lily base proportionally. Frost Garden ice and Lily Pond water cover approximately twice their previous central patches. Across seeds 7, 42, 101 and 2026 at 2/6/8/10 players, observed ratios were Lily 1.82–2.44 and Frost 1.50–2.62. Safe spawn exits, crate/wall placement and generation RNG order are preserved. Movement and fairness tests cover the new speed and terrain profiles.

## Technical coverage

- Registry flow covers all five maps at 2, 6, 8 and 10 players: admission, countdown, play, results, score retention and rematch. Network checks exercise ten clients, slot-nine input and room capacity.
- Snapshot geometry is validated before storage and rendering. Tests reject malformed dimensions, matrix shapes, nonfinite values, fractional dimensions and future-round malformed authority; valid replacement snapshots recover without leaving the previous arena visible. Authoritative origins remain configurable.
- Native captures cover every map at 2/6/8/10 players at 960×704. Web evidence includes ten actual browser clients creating/joining, eleventh-player rejection, countdown, slot-nine movement, bomb/result flow and Nightfall rematch. Those full-browser captures preceded the final terrain amendment. Latest ten-player Web captures use one browser and nine headless peers for Classic and Nightfall, with the portable map-picker marker/legend verified visually. Latest hybrid Web lifecycle additionally covers all five maps at two, six and eight players, including countdown, play, results, map selection, replay and cumulative score retention. Six/eight-client runs use the final export; the two-client run includes latest terrain/speed but predates the final malformed-snapshot guard. Ten-client final-export Lily/Frost runs cover complete cycles and 960×704/1280×900 active views with all ten cards, board, YOU marker and footer visible. Guests bomb their own spawns to produce host wins; these runs do not establish responsiveness or cue comprehension. This hybrid evidence does not equal human players.
- A 600.514-second wall-clock in-memory soak ran 720 accelerated rematches and replacement joins, keeping ten connected participants. Maximum transient counts: ten room events, zero undrained game events, sixteen presentation samples and eight pending messages. The 730 historical participants are deliberate retained history. This is not a continuous ten-minute normal-speed human round.
- A presentation-only 300 ms gap test reset history to one sample, retained ten poses and placed slot nine at authority.

Raw evidence is retained locally under `/private/tmp/qack-resume/` (render captures, soak.json, measurements.json, browser-final-frames.json and test logs). These temporary artifacts are not repository attachments.

Final verification: all thirteen `tests/*_test.gd` scripts passed headless on 2026-10-01, each reporting zero failures, exit 0 and no SCRIPT ERROR. The final Web release export also exited 0 with no SCRIPT ERROR/export failure. Logs: `final-suite/` and `acceptance-final-export.log` under the evidence directory.

## Bounded performance measurements

Device: Apple M4, macOS 27, Godot 4.7.2; Web uses headless Chrome 153 at 960×704. Server harness: ten localhost WebSocket clients, four-second Classic scenarios, simulated RTT 0/100/150 ms, with 0 or ±30 ms jitter on each direction. Work measures server poll/flush, including serialization. Bandwidth counts serialized payload scheduled for peers; it excludes transport headers and is not delivered-wire bandwidth.

Normal active server p95 was 1.962–5.515 ms (maximum 9.470 ms). Stress active p95 was 6.058–10.130 ms (maximum 28.241 ms). Stress injects fifty range-six bombs with equal 2.5-second fuses; the recorded `chain_work_ms` is the frame where bombs become empty, measuring simultaneous explosion-frame work, without proving causal chains. Explosion-frame observations ranged 3.722–28.241 ms. Active-frame counts were 553–582 per scenario. That first fixture provides bounded simultaneous explosion load evidence; the follow-up below supplies preserved-wall causal chain evidence.

Scheduled normal payload was approximately 86.6–88.0 kB/s per peer, 0.866–0.880 MB/s aggregate. Stress was 201.7–218.1 kB/s per peer, 2.017–2.181 MB/s aggregate. These short synthetic scenarios are not production bandwidth forecasts.

Zero-direction command-to-snapshot marker p95 at no jitter was normal 53/163/210 ms for 0/100/150 ms RTT and stress 63/173/208 ms. Markers use timestamps and can collapse same-millisecond commands across peers; delayed snapshots can be reordered by injected jitter. This is provisional command acknowledgement evidence, not causal visible movement latency. With a single 300 ms uplink stall plus 150 ms RTT and ±30 ms jitter, the observed command application was 397 ms and marked snapshot receipt 492 ms. No visible movement metric is claimed in this initial run.

Latest one-browser/nine-headless active Web rAF intervals (299 samples each): Classic median 16.7 ms, p95 33.4 ms; Nightfall median 33.3 ms, p95 33.4 ms. These are frame scheduling intervals, not render CPU times. Nightfall misses the proposed 60 fps goal; Classic's typical frame meets it but p95 does not. Isolated native board draw p95 was Classic 7.317 ms, Frost 7.066 ms and Nightfall 11.485 ms; this does not supersede Web results.

## Causal motion and preserved-wall chain follow-up

A clean follow-up (`causal-measure.log`, `causal-measurements.json`) completed twelve four-second ten-client scenarios, with the same RTT/jitter matrix, and 36 successful nonzero-command motion trials. Each motion trial starts a fresh unstressed round, clears artificial delay queues, drains client packets, resets presentation, sends one slot-nine command, and observes matching-round `ArenaPresentation.sample()` position displacement greater than one pixel. Commands have unique IDs keyed with peer identity. The motion arrays nested under stress scenarios are also unstressed trials, not responsiveness while bombs explode. This measures a presented pose in the headless client, not browser input-to-photon latency.

Six observed motion samples per RTT/jitter setting (three after each normal/stress scenario) gave these ranges; no population p95 claim is made from six samples:

| RTT | Per-direction jitter | Presented pose latency range |
| --- | --- | --- |
| 0 ms | 0 | 42–69 ms |
| 0 ms | ±30 ms | 57–103 ms |
| 100 ms | 0 | 159–174 ms |
| 100 ms | ±30 ms | 120–190 ms |
| 150 ms | 0 | 199–234 ms |
| 150 ms | ±30 ms | 176–247 ms |

The chain fixture preserves Classic permanent walls and clears central crates. Fifty connected range-six bombs use one 0.4-second fuse and forty-nine five-second fuses. All six stress configurations removed fifty bombs on one frame while the later fuses still had approximately 4.6 seconds remaining. Cascade-frame work ranged 5.379–23.585 ms. Active server p95 was normal 3.079–5.554 ms and chain stress 4.007–6.834 ms; respective maximum work was 9.107 and 27.303 ms. The follow-up therefore does not establish a worst-frame 16.7 ms guarantee. Maximum serialized payload was 42,462 bytes; scheduled aggregate payload was normal approximately 0.877–0.892 MB/s and chain stress 1.642–1.754 MB/s. One browser lifecycle run shared the device during part of collection; there was no browser frame profiling or soak concurrently. This is a bounded valid-wall technical fixture, not exhaustive map stress.

The independent `chain-proof.json` confirms fifty `bomb_exploded` events in a 0.41-second rules update, before the forty-nine later five-second fuses expire. That proof uses the all-open synthetic fixture and establishes causality, while its transport capacity limitation is recorded below.

## Known transport stress boundary

A synthetic fifty-bomb range-six cascade with Classic permanent walls removed queued large flame snapshots and logged WebSocket outbound-buffer ERR_OUT_OF_MEMORY failures. Fifty bombs matches the nominal ten-duck maximum capacity (five each), but the all-open board was artificial. This failed fixture is retained as a transport capacity boundary; success on a preserved-wall fixture does not prove arbitrary dense-open-map capacity. Artifacts: `causal-measure-errors.log` / `causal-measure-errors.json`, plus the exact fifty-explosion `chain-proof.json`. The exact all-open rules fixture serializes a 54,667-byte game snapshot against a 65,535-byte default outbound buffer; multiple queued messages can exceed this bound. The earlier log concatenates stdout before stderr, so printed scenario order does not locate the failure in time.

## Known presentation limitation

The Lily card SPEED percentage displays the upgrade multiplier relative to the Lily base (100% before upgrades), while actual starting movement is 50% of normal. The base is not labeled on that card; README and picker describe the half speed. This minor clarity issue remains open.

## Human acceptance still required

The only supplied human evidence is two players and “that good.” Build, round count and feature-specific observations are unknown. It cannot establish the planned acceptance criteria.

- [ ] Three human rounds each at 2, 6 and 10 players, recording build, map, rounds and device.
- [ ] Controls/missed inputs, joining/retry and duck identity recognition.
- [ ] Frost ice recognition and glide cues; Lily speed/density and safe exits.
- [ ] Nightfall clear center and outer fade, including crowded play.
- [ ] Elimination cause clarity, map identification and spawn fairness observations.
- [ ] Human audio audibility, browser unlock and mute quality.
- [ ] Browser input-to-photon movement latency and active Web performance goal. The headless presented-pose and preserved-wall causal chain fixtures are covered above; arbitrary dense-open transport capacity remains unresolved.

Technical checks and documentation can be complete while these acceptance items remain outstanding. No release-readiness claim is made.
