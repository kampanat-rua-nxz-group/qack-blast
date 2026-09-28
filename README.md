# Qack Blast — local gameplay prototype

Open `project.godot` in Godot 4 and press **F6** on `scenes/arena.tscn` (or **F5** to run the main scene).

If the game opens in Godot's floating Game window, set the Game bar's **Interaction mode** to **Input**. Its **2D** and **3D** modes intercept keyboard input for editor navigation.

- Player 1: Use **WASD** to move tile by tile; hold a key to keep moving. **Space** plants a bomb.
- Player 2: Use **Arrow keys** to move tile by tile; hold a key to keep moving. **Enter** plants a bomb.
- **M** selects the permanent wall layout for the next round: **Fixed** or **Random**. **R** starts that round once a different layout is selected, or rematches after a win or draw. Wins and Kills remain on the player cards until the game closes.

The round rules support 2–4 players with distinct corner spawns, connected routes, and per-player Wins/Kills. The current keyboard scene starts with two local players; players 3–4 are available in the game model for the planned online room controls. Destructible walls reroll each round in either map mode. The fixed permanent walls repeat, while the random walls change with the round seed.

At five minutes, the outer walkable ring becomes permanently dangerous. Another ring closes every 30 seconds, with a flashing five-second warning before each closure. Closing deaths award no Kill; if the last players die together, the round is a draw. The game uses simple shapes so gameplay can be evaluated before artwork. Rooms, browser export, and networking remain future milestones.

`scripts/arena_game.gd` owns the board, players, bombs, pickups, and round rules. `scripts/arena.gd` reads local controls and draws the scene; it advances the game through `game.step(delta, directions, plant_requests)`.

The `13 × 11` arena, 2.5-second fuse, 0.5-second flame, 20% pickup chance, and pickup caps are trial values from the game design. The prototype requires a desktop Godot editor to import and play; it has not yet been exported for the web.

Run the gameplay checks with `godot --headless --path . --script tests/arena_test.gd` if the Godot executable is in your PATH. On macOS with Godot installed as `/Applications/Godot.app`, use:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/arena_test.gd
```
