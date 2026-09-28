# Online Rooms Design

## Goal

Two to four friends open the web build, enter nicknames, create or join a private room by code, play repeated rounds, and retain Wins/Kills until the room empties. The first runnable target is one headless Godot server on localhost and multiple browser windows.

## Architecture

- A native headless Godot process hosts a WebSocket server and owns all rooms and `ArenaGame` instances. Browser exports connect as WebSocket clients. A public deployment later supplies HTTPS and a `wss://` endpoint.
- `RoomRegistry` contains room membership, unique nicknames, host election, round lineup, disconnect deadlines, inputs, and scores. Its methods are independent of sockets so lifecycle rules can be tested directly.
- The server accepts small JSON commands (`create`, `join`, `leave`, `map`, `start`, `input`) and sends lobby events plus authoritative snapshots at 20 Hz. A peer can affect only its own slot; only the current host can select a map or start a round.
- A new main scene shows nickname, room code, server URL, roster, map choice, error state, and Start/Leave controls. During a round it displays the existing arena renderer with the server snapshot. Each browser controls only its own duck with WASD/Space (arrows/Enter may be aliases).

## Round lifecycle

- A room starts with 2–4 connected participants. New joins during play watch until the next round. A room may have at most four connected participants; historical disconnected records remain for scoring.
- Duplicate nicknames receive `#1`, `#2`, etc. A returning connection is a new participant and never resumes the old slot or score.
- On disconnect or explicit leave, host rights transfer immediately to the longest-connected remaining participant. If no connected participants remain, delete the room and its scores.
- During play, a disconnected avatar remains stationary and vulnerable for 30 seconds, then is eliminated without awarding a Kill. The server resolves the round using existing `ArenaGame` rules. After a round, the host can select a map and start again with current connected participants.
- Snapshots include roster and scores, board, players, bombs, flames, pickups, timer, hazard rings, and round result. Browser input never directly changes authoritative state.

## Verification

- Unit tests cover room codes, nickname suffixes, capacity, host transfer, spectator joins, score persistence, disconnect expiry, and empty-room deletion.
- A loopback integration test connects two Godot WebSocket clients to the headless server and verifies create/join/start/snapshot.
- Export a single-threaded Web build, serve it locally, and verify create/join/start from separate browser windows when export templates are available.
