# Local Gameplay Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a Godot 4 project with a playable local two-player slice of Qack Blast.

**Architecture:** One Node2D scene owns a grid board and renders temporary geometric art. Player movement uses continuous coordinates with four-direction input, turn buffering, and tile collisions. Bomb timers, blast propagation, destructible walls, chain reactions, pickups, and round restart run in the same deterministic local loop; online play follows later.

**Tech Stack:** Godot 4, GDScript, Compatibility renderer.

**Spec:** `../../../qack-blast-game-design.md`.

## Global Constraints

- The target game is browser-based, private rooms for 2–4 people; this first prototype is local gameplay only.
- Movement is continuous and restricted to four directions; bombs start at capacity 1 and range 2.
- Solid walls stop blasts; destructible walls are destroyed and stop the ray on their tile.
- The only pickups are bomb capacity and blast range.

## Review Focus

- Spawn exits remain open after wall generation.
- A placed bomb allows its placer to exit but then blocks re-entry.
- Blast chains assign each blast to its own bomb owner.
- A destructible wall stops the blast even when destroyed.
- Simultaneous last-player deaths end in a draw.

---

### Task 1: Local arena and movement

**Files:** Create `project.godot`, `scenes/arena.tscn`, `scripts/arena.gd`.

**Interfaces:** Board coordinates are `Vector2i`; players are dictionaries with `pos`, `tile`, `alive`, `bomb_limit`, `range`.

- [ ] Write local invariant checks for spawn exits and blocked tile movement.
- [ ] Verify checks reject the missing arena implementation.
- [ ] Build and draw the 13 × 11 board with fixed pillars, seeded destructible cells, safe corner spawns, and two smooth four-direction players.
- [ ] Verify with Godot headless and visually inspect if Godot is available; report a missing runtime honestly.

### Task 2: Bombs, pickups, and round end

**Files:** Modify `scripts/arena.gd`; create `README.md`.

**Interfaces:** Each bomb owns its tile, player index, fuse, and blast range. Explosion cells retain their owner for kill attribution.

- [ ] Write invariant checks for blast stopping, chains, pickup limits, and simultaneous deaths.
- [ ] Verify checks reject missing mechanics.
- [ ] Add timed bombs, cross-shaped blasts, wall destruction, chain reactions, two powerups, winner or draw state, and restart.
- [ ] Run available checks and package the project for Godot import.
