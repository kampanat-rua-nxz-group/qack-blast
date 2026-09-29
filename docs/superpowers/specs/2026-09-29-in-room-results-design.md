# In-Room Results Design

## Goal

After an online round ends, all players see a dedicated results screen with the round outcome and room leaderboard. They remain in the same room while the host changes the map or starts another round. The waiting lobby shows the room code and player roster without scores.

## Screen flow

```text
Create or join → Waiting lobby → Arena → Results → Arena → Results …
                    ↑                 │
                    └── Leave room ───┘
```

- The waiting lobby shows the shareable room code, current player names and connection state, selected map, and the controls needed to start the first round. It does not show Wins or Kills.
- When the server reports `phase == "results"`, the online client hides the arena and waiting lobby and shows `scenes/results.tscn`. The results screen is a separate scene within the existing `scenes/online.tscn` flow; changing screens does not disconnect, leave the room, or reload the online scene.
- When the host starts a round, the server reports `phase == "playing"` and every client switches directly from results to the arena. The results screen can reappear after each round.
- Leaving the room or losing the server connection returns the client to the create/join screen.

## Results screen

Use the existing 960 × 704 canvas, duck-themed colors, and card styling. Show a prominent round outcome, the room code with a **Copy Code** button, selected map, and a leaderboard with columns for rank, player name, Wins, and Kills. Copy Code copies the current room code to the clipboard and confirms the action on the results screen; every player can use it. Mark the host and offline players. Include all room records, including disconnected players whose score history persists; a returning player appears as a new record under their distinct nickname.

Rank by Wins descending, then Kills descending. Preserve roster order for exact ties so every client sees a stable order. The outcome uses the authoritative game result; a draw is shown as a draw, with no invented winner. If the room phase arrives before its final game snapshot, show a neutral “Round complete” title until the result arrives.

The host sees **Change Map** and **Play Again**. Change Map cycles through the existing five map modes and updates the selected map for everyone. Play Again starts the next round with the connected players and keeps cumulative scores. Disable Play Again when fewer than two players are connected. Other players see the selected map and a waiting-for-host message, without active host controls. Everyone can leave the room.

## State and ownership

`RoomRegistry` remains authoritative for phase, roster, scores, map selection, and host rights. The existing `map` and `start` commands already permit the host to act during results, so no new network command or scoring rule is needed. `scripts/online_app.gd` chooses which screen is visible from the room phase and passes room/game snapshots to a focused results UI script. The results UI only formats and renders snapshots and emits button requests; it does not change game rules or local scores.

The waiting lobby roster should render names and host/offline markers only. A host transfer during results updates the buttons on the next room snapshot. A join during results updates the leaderboard, and the new connected player joins the next round. An error from a rejected command appears on the current screen without changing the room phase.

## Verification

- Online UI tests cover the lobby roster without scores, transition from arena to results, the room code and Copy Code action, outcome and leaderboard ordering, host-only controls, map updates, and direct replay into the arena.
- Room tests confirm that changing maps and starting a new round during results preserve scores and keep the room code and membership.
- Run every `tests/*_test.gd` script headless with Godot 4.7.2 and inspect the results screen at the project viewport size.
