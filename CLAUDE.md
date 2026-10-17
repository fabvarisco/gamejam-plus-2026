# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.5 (GDScript, GL Compatibility renderer) game for Game Jam Plus 2026: "Cubes on the Mountain", an online two-player co-op climbing puzzle with a World of Goo-style look. Two cubes tied by an elastic rope climb a mountain of thirteen themed rooms (village, forest, gorge, cave, camp, snowline, summit, then the seam and the corrupted wireframe, rerun, debug and loading rooms, and the edge) that turns out to be a broken simulation.

**`GDD.md` is the spec.** When the code and the GDD disagree, the GDD wins. Read the relevant GDD section (especially "The rope", "The rooms", "Online co-op" and "Out of scope") before any gameplay change.

## Running and testing

There is no build step or linter. Open the project in the Godot 4.5 editor and run it (the main scene is the menu, `res://scenes/menu.tscn`). With a `godot` binary on PATH:

```
godot --path .                                   # run the game (menu)
godot --path . -- --local [--seed=N]             # straight into a one-keyboard session (debug)
godot --path . -- --host [--seed=N]              # create a room
godot --path . -- --join=CODE                    # join a room (code, IPv4 or "localhost")
godot --headless --path . --quit                 # import/parse check

# Playtest suite (scripted inputs against the real game scene, ~10 s):
godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd
godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd -- test_swing seed=3 trace
```

`tests/run_tests.gd` encodes the GDD's room rules. It finds lips and swing gaps by probing each room's terrain, so it follows layout changes:
- A solo jump or walk-off fails every 2-cube lip and every swing gap.
- Stacking, hauling, swinging, the anchor following across, and climbing all succeed.
- The cornices hold one cube and break under two, the loading bar can be crossed and empties, and pits reset.
- The summit cannot be crossed.
- Each room can be walked from its spawn to its puzzle, and the seam, every exit and the ending work. Run it after any change to tuning, the rope, the cube or the room layouts. A user argument filters tests by name; `seed=N` changes the mountain; `trace` prints the pair-climbing follower.

Other tooling:
- `tests/screenshots.gd` and `tests/ending_shots.gd` render PNGs of every room and of the story beats. They need a display: `xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 -s res://tests/screenshots.gd -- <out_dir>`.
- `tests/net_peer.tscn` is a two-process network check. Run it in real time (no `--fixed-fps`): start `-- host`, then `-- client` (or `host_watch` / `client_quick` to exercise leaving and rejoining).
- Test scripts run as `-s` SceneTree scripts. There the `Net` autoload is not a compile-time global, so class scripts (`class_name`) must not reference `Net`; only `main.gd`, `menu.gd` and `net.gd` do.

Local debug keys: P1 is A/D, W/Space, C; P2 is ←/→, ↑, `.` (or numpad 0). Esc returns to the menu.

## Architecture

- **`scripts/net.gd` (autoload `Net`)**: session mode (`LOCAL`, `HOST`, `CLIENT`), ENet on port 24565, and the room code, which is the host's LAN IPv4 packed into 7 base32 characters. It switches both peers into `main.tscn` with the same `stage_seed`.
- **`scripts/main.gd` (game)**: the host (or local session) is the only simulator. Each physics tick runs in a fixed order: lift and jitter platforms, then `player.step()` for both cubes, then `rope.step()` (which writes rope forces used on the *next* tick), then `_progress()` (falls, checkpoints, story triggers), then a snapshot RPC. The client only sends input (`_rpc_input`), applies snapshots, and runs the rope locally for visuals. Story beats are events: `_emit()` applies them locally and sends them reliably to the client (`reset`, `checkpoint`, `witness`, `witness_end`, `ending` phases, `full_state` on rejoin). Snapshots carry the cubes, the lift offset and the cornice states; clock-driven holds (jitter blocks, the loading bar) follow the shared `sim_time`. The host pauses (`waiting_for_partner`) whenever the client is missing; a rejoin resets both cubes to the checkpoint room's spawns.
- **`scripts/player_cube.gd` (`PlayerCube`)**: a CharacterBody2D stepped explicitly by the game. Its collision shape is one-way, so cubes can stand on each other (needed for the room 2 lip) but pass through each other sideways. A climbing cube turns its collision layer off so the partner cannot ride it. Assists: mantle over lips under 0.3 cube, haul up a wall face when the rope drags into a wall, and swing pumping (input pushes along the arc while the rope is taut).
- **`scripts/rope.gd` (`EntangledRope`)**: a Verlet chain of 24 segments pinned to the cube centers. It collides with terrain rectangles from `stage.rope_colliders()` only; one-way bridges, seam holds and cubes are excluded. Tension is elastic past the 3-cube rest length (`k1·s + k2·s²` plus damping). The cube on the floor gets the tension reduced by `exp(-μ·wrap_angle)` (capstan friction), which is what makes it an anchor. The pull direction aims half a cube off the terrain the rope lies on, so a hauled cube is drawn up and over a lip. While a cube climbs, the span shortens and the remainder is drawn as a tail.
- **`scripts/stage_generator.gd` (`StageGenerator`, `@tool`)**: thirteen rooms stacked vertically, 30×10 cubes each with a pitch of 11. Story room indices are constants there (`ROOM_WITNESS` 4, `ROOM_WALL` 6, `ROOM_SEAM` 7, `ROOM_EDGE` 12) and `main.gd` and the tests use them. Rooms alternate direction (`room.mirrored`). Templates are written in local cube coordinates for a room entered on the left: `_rect`, `_spot` and `_ground` convert local cubes to world space. Each room's floor band is drawn as the ceiling of the room below. Over the entry (local x 0–8) the band is a **one-way goo bridge**, and the previous room's exit staircase (1-wide steps from 7 to 10 at local x 24–28) climbs up through it. Keep local x 0–5 clear at floor level, because that is where a pair arrives from the room below. The summit's ceiling is the seam room's floor, with a broken slot and glitch-drawn holds over a bump. The seam room is entered by teleport and climbs back to the left, so the mirroring restarts after it (`_mirrored()`); the edge mirrors to match the room before it. The edge's floor is a `FailFloor`. Rooms from the seam up stay invisible until the seam is crossed. Seeds vary a few crux positions and the scenery.
- **`scripts/themes.gd` (`Themes`)**: each room's name, sky gradient and stars, rock palette, and terrain style (`GOO` before the seam; `GRID`, `WIRE`, `DEBUG`, `REUSED` after it). `main.gd` blends the sky toward the camera's room.
- **Tuning lives in `scripts/tuning.gd`**, in cube units, and the room layouts depend on it. A solo jump rises 1.25 cubes and crosses well under a 2-cube gap. Walking off a ledge is clamped to air speed for the same reason. 1-wide steps keep a climbing pair within the 3-cube rope. A haul needs about 4 flat cubes past the lip, because the hauler can't hop a step with a taut rope. A swing needs open space under the near ledge, and its far hold should be a wall the follower can be hauled up. Changing jump, air speed, rope stiffness or step layouts can silently break the GDD's "needs the rope" rules, so rerun the suite.
- Moving or breaking holds: `Lift` (the camp), `Cornice` (the snowline: breaks when both cubes stand on it, restored on reset), `JitterPlatform` and `LoadingBar` (clock-driven, past the seam). The rope collides with each of them while it is solid.
- Visual-only nodes: `TerrainArt` (gooey rock in each room's palette, drips, bridges, and the corrupted styles), `GlitchArt` (the seam), `Decor` (village, posters, moon, pines, waterfall and water, crystals, camp, snow, clouds, wireframe trees, missing textures, debug boxes and gizmos, interface debris), `FallingEcho` (the camp's falling cubes) and the `FailFloor`'s breakup. There are shaders for the sky, the screen glitch and player recoloring (`cube_recolor.gdshader` tints the purple sprites to a player's color). `Music` synthesizes the soundtrack, since there are no audio assets.

Physics layers: layer 1 is `terrain` and layer 2 is `players`. Cubes mask both layers.

## Conventions

- Static typing everywhere (`:=`, typed arrays, return types). Indent with tabs. Put `class_name` on reusable scripts.
- Art lives in `Assets/` as SVG cube sprites named `cubo_<state>_dir.svg`: parado (idle), andar (walk), pulando (jump), caindo (fall), aterrissando (land), piscando (blink), dano (damage). Blink and damage appear only past the seam. Asset names and in-game text may be in Portuguese. The only spoken line is "Nossa, ainda bem que não é a gente."
- Commit `.uid` files alongside their scripts.
