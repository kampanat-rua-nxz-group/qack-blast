# Map identities and sudden death

September 29, 2026 · Design for review

## Goal

Give each of the five maps a distinct gameplay effect and map-specific pickup. Keep rounds moving toward a result without ending while multiple ducks survive. The only draw is when the final surviving ducks are eliminated together. All rules run in `ArenaGame` on the authoritative server; local play uses the same rules.

## Shared rules

- The existing bomb-capacity and blast-range pickups remain available. Crates retain their 20% item drop chance; each map adds its own special pickup to that drop pool, except Classic, whose two existing pickups are its items.
- The host selects a map before the round. The server sends board, terrain, player upgrades, moving bombs, warnings, and hazard state in snapshots; clients only render them and send movement/bomb commands.
- At 3:00, if at least two ducks remain, the map starts sudden death with a five-second warning. Strikes repeat every 15 seconds and grow more dangerous. There is no timer that declares a draw while multiple ducks survive.
- A sole survivor wins immediately. If the final ducks die during the same update, the round is a draw and no Win is awarded. Existing Kill attribution remains in force; neutral map hazards award no Kill.
- Warning marks must remain legible over Nightfall's darkness. Spectators see the entire board.

## Classic

- Keep its fixed wall layout and existing row-and-column danger bombs.
- Its map items are the existing +1 bomb capacity and +1 blast range pickups, with their current caps.
- Move the first danger warning from 4:55 to 3:00 and the first blast from 5:00 to 3:05. Each later wave warns five seconds before its blast. Increase the number of danger bombs each wave (1, 2, 4, 8, ...) up to the available open tiles so pressure accelerates.

## Random

- Keep the current permanent-wall reroll at the start of each round.
- Add a Mystery pickup. On collection, the server randomly grants either +1 bomb capacity or +1 blast range, respecting the existing caps. If one upgrade is capped, grant the other; if both are capped, consume the pickup with no upgrade.
- Sudden death marks randomly selected open tiles for a burst five seconds later. The selected count doubles each wave (1, 2, 4, 8, ...) up to every open tile. A burst damages ducks, clears crates and pickups, and can trigger bombs; it does not leave a permanent wall.

## Lily Pond

- Add a fixed pattern of clearly marked shallow-water tiles on otherwise open cells. Shallow water slows ducks to 80% of normal movement speed while crossing it. It does not affect bombs or block blasts. Keep spawn cells and their first exit dry.
- Add a Speed pickup. Each pickup increases that duck's movement speed everywhere by 25% of base speed, capped at 150% of base speed. The water multiplier still applies after the boost.
- Sudden death turns outer rings of the playable board into deep water, one ring per wave, moving inward. Mark the next ring during the five-second warning. Deep water eliminates ducks on those tiles and remains impassable afterward. Bombs and pickups on flooded tiles are removed. The remaining dry cells stay connected until the last ring.

## Frost Garden

- Add a fixed pattern of clearly marked ice tiles on otherwise open cells. Entering ice slides a duck one additional tile in its current direction when that tile is passable. The extra slide does not repeat automatically. Bombs, crates, walls, and the arena edge still block movement.
- Add a Bomb Kick pickup. After collecting it, walking into a player bomb kicks that bomb in the attempted direction. It moves at four tiles per second until the next tile is a wall, crate, another bomb, or the arena edge; it stops on the last open tile. It may pass through duck-occupied tiles. Its fuse continues during motion and it can explode en route. Ownership and Kill attribution remain with the original planter. Neutral danger bombs cannot be kicked. The upgrade lasts for the round.
- Sudden death marks rows for a blizzard strike. The selected count doubles each wave (1, 2, 4, 8, ...) up to every row. Struck rows damage ducks and trigger bombs, then clear.

## Nightfall

- Keep the circular, soft-edge spotlight centered on each living duck. A Sight pickup expands that duck's radius; local play combines spotlights, online play shows the viewer's spotlight, and spectators see the board. The vision calculation and drawn mask use the same circular boundary.
- Reshuffle interior permanent walls at each whole minute before sudden death begins (1:00 and 2:00 with the proposed timing). Leave crates, pickups, bombs, flames, ducks, and current movement paths safe; do not put a new wall on their occupied or destination tiles. Keep the non-wall cells structurally connected. The outer boundary stays fixed.
- Do not spawn Classic danger bombs or their row-and-column warnings on Nightfall.
- During sudden death, warned permanent walls additionally close one outer ring of remaining space per wave. A closing wall eliminates a duck on its tile, clears bombs and pickups there, and remains in place. This wall closure is Nightfall's finishing pressure, separate from its ordinary minute-by-minute reshuffle. Stop normal reshuffles once sudden death begins.

## Rendering and feedback

- Give shallow water, ice, deep water, blizzard rows, Random bursts, and Nightfall closing walls distinct markings. All lethal events display their target tiles during the five-second warning.
- Display map-specific upgrades on player cards and the 3:00 sudden-death state near the round clock. Keep critical warnings above the Nightfall darkness mask.
- Keep map logic in `scripts/arena_game.gd`; scene code only draws snapshots and local input. Add terrain and moving-bomb fields to snapshots where needed.

## Validation

- Add rule tests for each map effect, pickup, cap, hazard warning, strike, and end condition; test both two-player and larger boards where geometry differs.
- Test Nightfall reshuffles against ducks in motion, bombs, crates, pickups, and connectivity. Test a kicked bomb hitting each blocker and exploding while moving.
- Test snapshot round trips for new terrain, upgrades, bomb motion, and warnings. Run every `tests/*_test.gd` script headless, then inspect the five maps visually in local play.

## Playtest values

The 3:00 sudden-death start, 15-second wave interval, water 80% speed, Speed pickup +25% (150% cap), and bomb movement rate of four tiles per second are tuning values. Keep them as named constants in the rules engine so playtesting can adjust them without changing the behavior contracts above.
