# Qack Blast — First Version Game Design Draft

September 27, 2026 · Status: rules revised after review

## Goal

A classic competitive bomb-placing game for 2–4 friends, played online in a web browser. Players join a private room with a code and a nickname, with no account sign-up. A round targets 4–5 minutes, and players replay in the same room to accumulate results until the room closes.

## Game Loop

1. A player creates a room or enters a room code, sets a nickname, and waits for friends in the lobby.
2. Before the round, the host chooses Classic, Random, Lily Pond, or Frost Garden, then starts once 2–4 players are present. Each player spawns at a different point with an exit route from the spawn.
3. Players explore, plant bombs to destroy walls, collect items, and try to eliminate opponents.
4. Eliminated players become spectators. The last survivor wins. If the final survivors are eliminated at the same moment, the round is a draw.
5. The round result and leaderboard appear in a separate in-room results scene. The host can change the map or start the next round there, and everyone moves directly back into the arena.

## Movement and Map

- Pressing a direction key once moves one tile in one of 4 directions. Holding the key keeps moving tile by tile, and each step ends at the center of a tile.
- Releasing the key mid-move continues to the center of the current tile, then stops. Holding a new direction turns only when the player reaches a tile center.
- Before the round, the host chooses one of four maps: Classic, Random, Lily Pond, or Frost Garden. Each named map has a distinct permanent wall layout and visual theme; Random rerolls permanent walls each round. The map cannot change during a round.
- Destructible walls are randomly repositioned at the start of every round in both modes. Spawn points must suit the layout in use.
- Randomization of both permanent and destructible walls must guarantee an exit from every spawn point, routes that let players reach each other, and that no one is enclosed from the start.

## Bombs and Items

- Players start able to have 1 bomb placed at a time, with a blast range of 1 tile.
- Blasts are cross-shaped. Permanent walls stop blasts. Destructible walls are destroyed and stop the blast at that tile.
- A blast immediately detonates other bombs. A player hit by a blast is eliminated in one hit.
- Destroyed walls may drop 2 item types: more simultaneous bombs and longer blast range.
- The first version has no speed items or character-specific abilities.

## Time and Resolution

- A typical round targets roughly 4–5 minutes.
- At 4:55, a neutral danger bomb appears on a random open tile. Its entire row and column flash for five seconds. At 5:00, it explodes across those tiles, passing through permanent walls, then clears.
- Another wave explodes every 15 seconds. Each wave adds one randomly placed bomb: two in the second wave, three in the third, and so on, limited by the available open tiles. All bombs in a wave share the five-second warning and explode together. Their blasts can destroy crates and trigger player bombs; danger bombs cannot be triggered before their warnings end.
- Danger bombs continue while multiple players survive; there is no fixed round end time. If a wave eliminates the final survivors at the same time, the round is a draw.
- The last survivor earns 1 Win. If the final players are eliminated together in a draw, no one earns a Win.
- Eliminated players can keep watching the match.

## Room Scores

- Wins and Kills are tracked separately across rounds in the same room.
- When a player's bomb eliminates an opponent, the bomb owner earns 1 Kill per eliminated player.
- In a chain reaction, the Kill goes to the owner of the bomb whose blast touched the eliminated player, not to whoever started the chain. If that bomb eliminates several opponents, its owner earns 1 Kill per player.
- If blasts from several players touch a target at the same moment, the Kill goes to the owner of the bomb nearest the target, measured in tiles along the blast line from bomb to target.
- If the simultaneous bombs are equally distant from the target, that Kill is a tie and no one earns it.
- Self-elimination or elimination by a neutral danger bomb awards no Kill.
- The scoreboard sorts by Wins descending, then by Kills descending.
- Previous score history stays visible in the room when a player disconnects and rejoins, but the rejoining player starts accumulating their own score from zero. All scores end when the room closes.

## Rooms and Disconnection

- If a nickname is duplicated in a room, the system appends a number, such as `name#1`, `name#2`, to distinguish players with the same name.
- When a player disconnects mid-round, their character stays in place and can still be hit by blasts. After 30 seconds, they are considered eliminated. Rejoining the room counts as a new player, uses a nickname distinguished by the duplicate-name rule, and waits for the next round without regaining control of the old character. The original player's history and score remain visible until the room closes.
- If the host disconnects temporarily, host rights transfer immediately to the connected player who has been in the room longest. If the former host rejoins, they become a regular player.
- If the host leaves the room, host rights transfer immediately to the remaining player who has been in the room longest. The room and scores remain.
- If the host disconnects and no other players are connected, the room closes immediately without waiting 30 seconds. When no players are connected, the room closes and its scores end.

## Starting Values for Playtesting (to be tuned from playtests)

| Item | Initial trial value | What to observe |
|---|---:|---|
| Map size | 13 × 11 tiles | 2 players meet often enough, and 4 players are not cramped |
| Bomb fuse | 2.5 seconds | Enough time to dodge, yet still usable for traps |
| Flame duration | 0.5 seconds | Visuals and hit timing are easy to read |
| Bomb count cap | 5 bombs | Items do not overcrowd the map |
| Blast range cap | 6 tiles | Corridors still have safe spots |
| Item drop chance | 20% per destroyed wall | Players receive items steadily enough |

## First Version Scope

Includes private rooms, room codes, nicknames, Free-for-All play, one map size with four selectable maps, randomized destructible walls, basic bombs and items, spectating after elimination, room scores, and rejoining after a network drop. Excludes accounts, public matchmaking, character skills, and permanent progression systems.

## Points to Confirm Before Building the Systems

- Verify during playtesting that the danger bomb's 5-second warning and full-row-and-column blast are clearly visible.
