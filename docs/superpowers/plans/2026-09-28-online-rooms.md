# Online Rooms Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-28-online-rooms-design.md`

1. Add `RoomRegistry` and lifecycle tests. Keep socket and UI concerns out of this module.
2. Add the headless WebSocket server and a loopback integration test for room commands and authoritative snapshots.
3. Add a WebSocket client and a lobby main scene. Reuse `arena.gd` as a renderer driven by snapshots; send one local player's input only.
4. Add export preset and local run instructions. Export and test in browser if templates are installed; record the exact missing prerequisite otherwise.
5. Run all tests, inspect the diff, and verify no unintended changes to local gameplay.
