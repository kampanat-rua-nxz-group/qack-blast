# Qack Blast

A small 2–10 player bomb battle. The main scene is now the online lobby; the original two-player keyboard scene remains available at `scenes/arena.tscn`.

## Play online on one computer

Use Godot 4.7.2. Start the authoritative room server in one terminal:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script scripts/server_main.gd
```

It listens on `127.0.0.1:9080` by default. To change this, add `-- --port=9080 --bind=127.0.0.1`. Clients connect to `ws://127.0.0.1:9080` unless given another URL: add `-- --server=<url>` to a desktop run, or `?server=<url>` to the browser address. Open the project in Godot and press **F5** to run a desktop client. For browser clients, install the matching Godot Web export templates, then export and serve the build:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8765` in separate browser windows. One player enters a nickname and creates a room; the waiting lobby shows the six-character code with a copy button, and the others enter it to join. Use **Explore Maps** to read each map's terrain, pickups and hazards. The host chooses Classic, Random, Lily Pond, Frost Garden, or Nightfall and starts the round once at least two players have joined. Every client sees a shared three-second countdown before GO; movement and bombs stay disabled until GO. The YOU marker identifies your duck. Each window controls its own duck with **WASD** or **Arrow keys** and plants a bomb with **Space** or **Enter**. After a round, everyone sees a results screen with the leaderboard and a copyable room code. The host can change the map or select **Play Again** there; all players stay in the same room.

Sound cues mark bomb placement, explosions, pickups, elimination and round results. Use **Mute** to switch sound off or on; the choice is saved on that device. Browser sound becomes available after interacting with the game.

### Play solo against a bot

Solo play uses the same authoritative room server and lobby as online multiplayer; it is not available in the local two-keyboard scene. Create a room, choose **ADD BOT · MEDIUM**, select a map, and start. The bot occupies the second player seat and follows the normal countdown, rules, scores, and rematch flow. The host can change its difficulty or remove it between rounds. One bot is supported per room; friends can still join and play under the usual ten-seat limit.

**Easy** is for new players, **Medium** for casual solo play, **Hard** for practice, and **Extreme** for experienced players seeking a challenge. These are starting difficulty profiles; Extreme has not received human playtest validation yet.

Connecting shows progress and offers **Cancel**. Temporary failures use bounded retries, then offer **Retry**. After losing a room connection, **Rejoin** keeps the code but creates a new participant; your old duck and score are not recovered.

Each map has its own effect and crate pickup. Classic keeps the bomb-capacity and blast-range upgrades. Random rerolls permanent walls each round and can drop a Mystery item that grants one of those upgrades. Lily Pond starts ducks at half normal speed (94 px/s); its broad shallow-water patches apply a further 20% slowdown (75.2 px/s). Speed items add 25% of the Lily base speed each, capped at a 50% bonus, on dry ground and water. Frost Garden has broad ice patches that slide ducks one extra tile and a Bomb Kick item: walk into a bomb to send it toward the next wall, crate, bomb, or arena edge. Nightfall has a soft spotlight around each duck and a Sight item that widens it. Its permanent walls reshuffle at one and two minutes, avoiding ducks, bombs, and pickups.

The server owns the game state and sends snapshots to every client. Room codes and scores live only in server memory. A disconnected player's avatar stays in the arena for 30 seconds before it is eliminated; host rights pass to the longest-connected remaining player. Rooms admit up to ten connected participants, including spectators; offline history does not consume a slot. New players joining during a round wait for the next one. This local setup uses plain `ws://`; hosting it on an HTTPS site needs a publicly reachable `wss://` server configured in the Web build or passed through `?server=`.

## Deploy online for free

The repository includes a Render Blueprint (`render.yaml`) for a Free WebSocket server and a free static game site. Render can connect to the private GitHub repository without making the source public. See [deployment costs and limits](docs/superpowers/specs/deployment-research.md). Both services share the workspace's monthly bandwidth and build-minute allowance.

1. Push the repository to GitHub. In Render, connect the GitHub repository and create a **Blueprint** from `render.yaml` on the Free/Hobby plan. It builds the Godot server behind an HTTP/WebSocket proxy from `Dockerfile` and exports the browser game with `deploy/build-web.sh`.
2. Wait for both services to deploy. The static site's address is its `https://<name>.onrender.com` URL. Its build receives the server's public hostname from the Blueprint and embeds `wss://<server-host>` automatically.
3. Open the static site in two browsers, create a room in one, and join using its six-character code in the other. Share the static site URL with players; they do not need `?server=`. The query parameter still overrides the embedded address for testing.

The free server sleeps after 15 minutes without inbound traffic. Its first connection after sleep wakes it in about a minute, so retry connecting after it is ready. A server restart clears the in-memory rooms and scores.

## Play locally

Open `scenes/arena.tscn` and press **F6**. Player 1 uses **WASD** and **Space**; player 2 uses **Arrow keys** and **Enter**. **M** cycles through the five maps for the next round, and **R** starts it. In local Nightfall, both players' visible areas are combined. If Godot's floating Game window does not receive keys, set its Interaction mode to **Input**.

The round rules support 2–10 players, Wins/Kills, chain explosions, and pickups. Rounds with 2–3 players use a 13×11 map; rounds with 4–6 use a 15×13 map. Rounds with 7–8 use a 17×15 map; rounds with 9–10 use a 19×17 map. Sudden death begins with a warning at 3:00, then strikes at 3:05 and every 15 seconds while multiple ducks survive. Classic fires escalating row-and-column danger bombs; Random bursts increasingly many marked tiles; Lily Pond floods inward; Frost Garden strikes rows with blizzards; Nightfall closes inward with permanent walls. The round continues until one duck survives. If the last ducks die together, it ends in a draw.

## Checks

```sh
test_exit_status=0
for t in tests/*_test.gd; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script "$t" || test_exit_status=1
done
exit "$test_exit_status"
```

The test scripts are `arena`, `bot`, `character`, `connection`, `feedback`, `input`, `map_picker`, `network`, `online`, `presentation`, `results`, `rooms`, `ten_network`, and `ten_player` (`tests/*_test.gd`).

`scripts/arena_game.gd` owns the rules; `scripts/bot_profiles.gd`, `bot_observation.gd`, `bot_navigation.gd`, and `bot_controller.gd` provide the visibility-limited bot policy; `scripts/room_registry.gd` owns room membership, bot ticking, and scores; `scripts/room_server.gd` validates network commands; and `scripts/online_app.gd` renders the lobby and snapshots, using the widget helpers in `scripts/lobby_ui.gd`.

The [player experience acceptance record](docs/playtests/2026-10-01-player-experience-acceptance.md) records technical validation and outstanding human/performance checks.
The [solo bot acceptance record](docs/playtests/2026-10-01-solo-bot-acceptance.md) records bot test, benchmark, and playtest status.
