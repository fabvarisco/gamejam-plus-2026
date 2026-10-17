# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.5 (GDScript, GL Compatibility renderer) game for Game Jam Plus 2026: "Cubes on the Mountain", an online two-player co-op climbing puzzle with a World of Goo-style aesthetic. Two cubes tied by a fixed-length rope climb a mountain of eight rooms that turns out to be a broken simulation.

**`GDD.md` is the spec; the code is behind it.** When the code and the GDD disagree, the GDD wins. Do not treat existing behavior as intended design, and do not document or preserve it as such. Read the relevant GDD section (especially "The rope", "The eight rooms", "Online co-op" and "Out of scope") before any gameplay change.

## Running

There is no build step, linter or test suite. Open the project in the Godot 4.5 editor and run the main scene (`res://scenes/main.tscn`). If a `godot` binary is on PATH:

```
godot --path .                     # run the game
godot --path . --editor            # open the editor
godot --headless --path . --quit   # import/parse check (catches script errors)
```

Prototype debug keys (in `scripts/main.gd`): `R` rerolls the stage seed, `G` toggles the connectivity-graph overlay.

## Target design (from GDD.md)

Key rules that the code must converge on:

- **Units:** everything is measured in cubes (collision box is 32px). The rope is 3 cubes long. A 2-cube gap needs the rope; a 4-cube gap is impossible without a hold in between. Platforms are laid out on these multiples.
- **Rope:**
  - Connects the two cube centers. Its rest length is 3 cubes and never changes: no reeling in or out.
  - It is elastic, with no hard maximum length. Past the rest length it pulls the cubes back together, harder the more it stretches. Tune the stiffness so the stretch never covers a 4-cube gap; room 5 depends on this.
  - It is drawn as a curve that sags under gravity when slack and straightens under tension. It should look physically plausible.
  - It collides with terrain only, catching on corners, which creates slack that the puzzles use. It has friction against terrain. It does not collide with the cubes.
  - A grounded cube acts as an anchor; the other cube swings, jumps farther or gets pulled up. If both cubes are airborne, they fall together.
- **Controls:** move with A/D or arrows. Jump with Space/W/Up, where releasing early shortens the jump. Hold **C** to climb along the rope toward the partner. Climbing is only for recovering when stuck, so no puzzle may require it, and it never changes the rope's length. Online, each player drives their own cube with either key set; there is no split-keyboard scheme. Cubes are physically identical. Only color differs, and after the seam the colors glitch while input stays untouched.
- **Level:** one continuous mountain of eight single-screen rooms, from bottom to top (Village, Ledge, Gap, Witness, Wall, Seam, Fault, Edge). A fall resets both cubes to the current room's floor, a checkpoint the two players share. Room 5 is deliberately unsolvable with the rope. Room 6's seam is the only way through and must read as a glitch. Corruption (scenery, palette swaps, screen glitches) starts only after the seam. The ending is a forced fall with no victory.
- **Stage generation:** procedural generation remains, but it must produce this room layout and the cube-multiple spacing rather than free-form islands.
- **Online:** one player hosts and the other joins with a code. The level pauses if either player leaves. The room 4 cutscene, the room 8 fall and the seam crossing are all synchronized and require both players.

## Current code (prototype, outdated)

A local, split-keyboard, single-scene prototype:

- **`scenes/main.tscn` + `scripts/main.gd`** wire the `StageGenerator`, `Players/Player1` and `Player2` (instances of `player_cube.tscn`), `Rope`, a midpoint-following `Camera2D` and a HUD label. `main.gd` places the players when `StageGenerator.generated` fires and copies `stage.rope_length` into `rope.max_length`.
- **`scripts/player_cube.gd` (`PlayerCube`)**: a CharacterBody2D that reads physical keys directly, branching on `player_index` (P1 uses A/D + W/Space, P2 uses arrows). `project.godot` has no InputMap actions, no variable jump height and no climb.
- **`scripts/rope.gd` (`EntangledRope`)**: a hard distance constraint, not a joint. It runs after the players move (`process_physics_priority = 10`) and corrects position and velocity, weighted 0.18/0.82 toward the airborne cube. The rope is a rigid cap drawn as a straight `Line2D`. It has no elasticity, no sag, and no terrain collision or friction. Its length is 220px, not 3 cubes (96px).
- **`scripts/stage_generator.gd` (`StageGenerator`, `@tool`)**: builds a seeded, free-form island graph, not the eight rooms. `generate()` runs these steps:
  1. `_build_islands` creates islands in vertical bands.
  2. `_connect_and_repair` links reachable islands, nudges them to fit the rope, and runs a BFS over *pairs* of player positions (`_validate_rope_path`) to guarantee a path to the top within rope length.
  3. `_build_scenery` turns metaballs into a polygon (marching squares, then RDP simplification) and spawns a `StaticBody2D` with a `CollisionPolygon2D`. These drippy blobs are already close to the World of Goo look.
  4. `_build_goal` places a pipe goal.

  Output goes under the `Islands`, `Decor` and `Goal` child roots, which are cleared on each regenerate. In the editor, `_own_if_editor` sets the edited scene as owner so generated nodes persist. `generation_seed == 0` means a random seed.
- No networking, rooms, checkpoints, cutscenes, glitch effects or audio exist yet.

Physics layers: layer 1 is `terrain` and layer 2 is `players`. Players collide with terrain only, not with each other.

## Conventions

- Static typing everywhere (`:=`, typed arrays, return types). Indent with tabs. Put `class_name` on reusable scripts.
- Art lives in `Assets/` as SVG cube sprites named `cubo_<state>_dir.svg`: parado (idle), andar (walk), pulando (jump), caindo (fall), aterrissando (land), piscando (blink), dano (damage). Asset names and in-game text may be in Portuguese. The only spoken line is "Nossa, ainda bem que não é a gente."
- Commit `.uid` files alongside their scripts.
