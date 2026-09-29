# Qack Blast

A small 2–6 player bomb battle. The main scene is now the online lobby; the original two-player keyboard scene remains available at `scenes/arena.tscn`.

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

Open `http://127.0.0.1:8765` in separate browser windows. One player enters a nickname and creates a room; the waiting lobby shows the six-character code with a copy button, and the others enter it to join. The host chooses Classic, Random, Lily Pond, Frost Garden, or Nightfall and starts the round once at least two players have joined. Nightfall rerolls its obstacles each round, limits each player to a one-tile view around their duck, and can drop sight items that extend that view by one tile each. Each window controls its own duck with **WASD** or **Arrow keys** and plants a bomb with **Space** or **Enter**. The host starts the next round from the lobby after a result.

The server owns the game state and sends snapshots to every client. Room codes and scores live only in server memory. A disconnected player's avatar stays in the arena for 30 seconds before it is eliminated; host rights pass to the longest-connected remaining player. New players joining during a round wait for the next one. This local setup uses plain `ws://`; hosting it on an HTTPS site needs a publicly reachable `wss://` server configured in the Web build or passed through `?server=`.

## Deploy online for free

The repository includes a Render Blueprint (`render.yaml`) for a Free WebSocket server and a free static game site. Render can connect to the private GitHub repository without making the source public. See [deployment costs and limits](docs/superpowers/specs/deployment-research.md). Both services share the workspace's monthly bandwidth and build-minute allowance.

1. Push the repository to GitHub. In Render, connect the GitHub repository and create a **Blueprint** from `render.yaml` on the Free/Hobby plan. It builds the Godot server behind an HTTP/WebSocket proxy from `Dockerfile` and exports the browser game with `deploy/build-web.sh`.
2. Wait for both services to deploy. The static site's address is its `https://<name>.onrender.com` URL. Its build receives the server's public hostname from the Blueprint and embeds `wss://<server-host>` automatically.
3. Open the static site in two browsers, create a room in one, and join using its six-character code in the other. Share the static site URL with players; they do not need `?server=`. The query parameter still overrides the embedded address for testing.

The free server sleeps after 15 minutes without inbound traffic. Its first connection after sleep wakes it in about a minute, so retry connecting after it is ready. A server restart clears the in-memory rooms and scores.

## Play locally

Open `scenes/arena.tscn` and press **F6**. Player 1 uses **WASD** and **Space**; player 2 uses **Arrow keys** and **Enter**. **M** cycles through the five maps for the next round, and **R** starts it. In local Nightfall, both players' visible areas are combined. If Godot's floating Game window does not receive keys, set its Interaction mode to **Input**.

The round rules support 2–6 players, Wins/Kills, chain explosions, pickups, and late-match danger bombs. Rounds with 2–3 players use a 13×11 map; rounds with 4–6 use a 15×13 map. The first neutral bomb appears at 4:55 with a flashing five-second warning, then explodes at 5:00 across its entire row and column, even through walls. Another wave follows every 15 seconds, adding one bomb per wave while multiple players survive. The blast clears, so no tiles close permanently. If the last players die together, the round is a draw.

## Checks

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/arena_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/rooms_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/network_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/online_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/connection_test.gd
```

`scripts/arena_game.gd` owns the rules; `scripts/room_registry.gd` owns room membership and scores; `scripts/room_server.gd` validates network commands; and `scripts/online_app.gd` renders the lobby and snapshots, using the widget helpers in `scripts/lobby_ui.gd`.
