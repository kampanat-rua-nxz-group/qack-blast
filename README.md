# Qack Blast — local gameplay prototype

Open `project.godot` in Godot 4 and press **F6** on `scenes/arena.tscn` (or **F5** to run the main scene).

If the game opens in Godot's floating Game window, set the Game bar's **Interaction mode** to **Input**. Its **2D** and **3D** modes intercept keyboard input for editor navigation.

- Player 1: Use **WASD** to move tile by tile; hold a key to keep moving. **Space** plants a bomb.
- Player 2: Use **Arrow keys** to move tile by tile; hold a key to keep moving. **Enter** plants a bomb.
- After a win or draw: **R** to regenerate the arena.

This slice tests local movement, map generation, bombs, blast chains, destructible walls and the two powerups. It uses simple shapes so gameplay can be evaluated before artwork. Rooms, browser export, networking, scoring, and the five-minute closing wall are the next milestones.

The `13 × 11` arena, 2.5-second fuse, 0.5-second flame, 20% pickup chance, and pickup caps are trial values from the game design. The prototype requires a desktop Godot editor to import and play; it has not yet been exported for the web.

Run the gameplay checks with `godot --headless --path . --script tests/arena_test.gd`.
