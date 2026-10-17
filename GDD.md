# GDD — Cubes on the Mountain

Design document for the Game Jam Plus 2026 game. Working title. A short online co-op climb for two players.

## Pitch

Two cubes tied by an elastic rope climb a mountain. Alone, neither can reach the next hold. Together, one anchors and the other climbs. The apparent goal is the moon. Halfway up, the mountain ends. A glitch is the only way to keep climbing. Past that point the world corrupts, and the climb has no exit.

On the surface, they belong to a community of happy little cubes who decided to climb to the sky. Underneath, the mountain is a program. The moon is a drawing inside the simulation. The cubes they watch fall are themselves, later.

The game is a cooperative climbing puzzle with a World of Goo-style aesthetic. Procedural stage generation will need to support this layout.

## Fantasy

The player feels the weight of the other. Pull too early and the partner falls. Hold steady and the path opens. The fun comes from shared failure: both fall, laugh, and try again. Halfway up they feel lucky. At the end they are the ones falling.

## Pillars

1. **One bond, two bodies.** The rope is not a power-up. It is the rule of the game.
2. **The climb is the puzzle.** Each room asks for one idea: who holds, who lets go, who falls on purpose.
3. **The wall is the simulation.** The program shows itself where the mountain can no longer be climbed, and a glitch is the only way through.
4. **Online, always as a pair.** The level waits for both players. There is no equivalent solo mode.
5. **There is no way out.** The game ends when the players discover that the ending does not exist, and that the falling cubes were them.

## Level shape

One continuous mountain, read from bottom to top, in eight rooms. Each room fits on one screen. A fall sends both cubes back to the floor of the current room. The session is a short climb, not a campaign.

The unit of measure is the cube. At rest, the rope is three cubes long. It stretches under load, but the pull back grows the farther it stretches, so in play it carries a cube only a little past three cubes. A two-cube gap requires the rope. A four-cube gap is impossible without a hold in between. Platforms follow these multiples so the puzzle can be read before the jump.

The mountain has two halves. Rooms 1 through 4 are a real climb: warm, readable, stable. Room 5 is a wall the rope cannot solve. Room 6 is the glitch that opens the way. Rooms 7 and 8 are the corrupted climb, and they end in the fall the players already watched.

## Players and controls

Exactly two players. Each controls one cube.

The cubes weigh the same and share the same jump, speed, and friction. Before the glitch, color is the only difference between them. Each player learns their color in the village and keeps it through the honest half of the mountain.

Past the glitch, the cubes change color. The shift is a visual glitch: flashes, wrong fills, swapped palettes. It does not change weight, jump, or input. Control stays honest. The players keep the same bodies while the bodies stop looking stable.

Controls:

- Move: arrow keys or A and D.
- Jump: Space, W, or the up arrow. Releasing the jump in the air shortens the rise.
- Climb: hold C to climb along the rope toward the partner. Climbing is for recovery only, so a cube left hanging is never stuck. No puzzle requires it.

Moving and jumping stay simple. The complexity lives in the rope.

## The rope

- Rest length of three cubes. Nobody reels it in or lets it out.
- Connects the center of one cube to the center of the other.
- Visible at all times, as a curved line that sags under gravity when slack and straightens under tension. It does not need to be a full rope simulation, but its shape must look physically believable.
- Does not pass through walls. It catches on corners, and that slack is part of the puzzles.
- Has friction against terrain only. Where it wraps a corner or lies on the ground, it drags instead of sliding freely. The rope does not collide with the cubes.
- Is elastic, with no hard maximum length. Past three cubes it pulls the cubes back toward each other, harder the more it stretches. Players can tug each other with it. The stiffness is tuned so the stretch never covers a four-cube gap.
- Can be climbed. Holding C moves a cube along the rope toward the partner, so a cube left hanging can always get back. Climbing does not change the rope's length.
- A cube standing on a hold becomes an anchor. The other uses the length to swing, jump farther, or be pulled up.
- Both in the air, with no hold, fall together.
- The rope cannot cross the wall in room 5. The glitch in room 6 is a broken seam in that wall, not a longer rope.

## Loop

Enter the level together. Read the height gap. Decide who stays and who climbs. Use the rope to reach the next hold. Land on the floor of the next room. A fall returns both to the last safe floor. At the wall, stop. Find the glitch. Keep climbing through the broken mountain. At the top, fall, and match the cubes from the middle of the climb.

## The eight rooms

Rooms 1 through 4 teach the rope while the world still holds. Room 4 also plays the fall. Rooms 5 and 6 are the turn. Rooms 7 and 8 are the corrupted climb and the ending.

| Room | Verb | Gameplay | What the players see |
| --- | --- | --- | --- |
| 1. Village | Walk together | Flat ground. The rope stretches and pulls back. Both learn how far three cubes reach. | Vector village, sun, small cubes in the background, a hand-drawn moon poster. Each player cube has its own solid color. |
| 2. Ledge | Anchor | One stays on the ground. The other climbs a lip a solo jump cannot reach. | Still the village. The moon poster points upward. |
| 3. Gap | Swing | One holds the edge. The other gains momentum and grabs the far side. | The slope begins. The rocks are still natural. The moon is still the goal. |
| 4. Witness | Weight, then the fall | The platform rises if both leave it. One stays on it while the other crosses. On the far side, the climb pauses. | Other cubes tumble down the face. The players say: "Nossa, ainda bem que não é a gente." ("Good thing that's not us.") |
| 5. Wall | None | The next gap is wider than the rope. No anchor, swing, or pit reaches it. The honest climb stops. | The mountain simply ends. The sky above is empty. The poster promise has nowhere to go. |
| 6. Seam | Glitch | A broken corner, a hold that clips through the wall, a gap the collision forgot. Using it pulls both cubes past the wall. | The instant they cross, color slips. The scenery tears. The simulation starts. |
| 7. Fault | Scale + corner | First mix of two ideas, on ground that jitters and reappears. | Corrupted scenery, visual glitches, cut-off interface. The player cubes keep changing color. |
| 8. Edge | The fall | No new puzzle and no platform past the screen. The rope hits the border and stops. The floor fails. Both cubes fall. | The promised moon is a flat drawing. It blinks out. The fall is the same fall from room 4. |

Room 2 is the first moment the rope stops being a limit and becomes the way up. It is the first room to block out in production. Room 6 is the second: the seam has to be readable as a glitch, not as a hidden normal hold.

## The fall in the middle

Room 4 is the middle of the mountain. After the weight puzzle, both players reach a ledge and the game plays a short animation. Cubes fall past them, down the face they just climbed. The two player cubes say one line:

> Nossa, ainda bem que não é a gente.

They believe they are watching strangers fail. They feel spared. The climb continues toward the moon.

Those cubes are the players, later. The line is the whole plot twist, spoken too early to understand. The game does not explain it here.

## The turn

The simulation is not a slow stain on the village. It is a place the rope cannot enter.

Room 5 is a fair stop. The gap is wider than the rope can stretch. Players who try the verbs they know will fail, and the checkpoint puts them back on the last floor. The wall is the end of the mountain they were promised.

Room 6 is the way through. The seam is wrong on purpose: overlapping collision, a corner the rope can clip, a platform that draws in the wrong place. Climbing it is the glitch. Both cubes have to commit. When they cross, the game changes.

From that crossing on:

- The scenery corrupts and shows broken computer pieces: grid, window, bar, cut-off text, repeated geometry.
- Visual glitches hit the screen: tears, missed pixels, frames that stick.
- The player cubes change color. Fills swap, flash, and refuse to stay on the village palette.
- The moon stops behaving like a destination and starts behaving like an image.

Input does not invert, delay, or drop. The glitch is in the world, not in the hands.

## Story

The cube community dreams of reaching the moon and sends two of its own on the journey. That exists in room 1, as an audience and as a poster.

The only spoken line in the climb is the one in room 4. Nobody explains the simulation in dialogue. The players learn it by hitting the wall, glitching past it, and falling.

Scenery arc:

- **Rooms 1 through 4.** Warm background, flat shapes, sun, a happy community. The dream of the moon is whole. The falling cubes read as other climbers.
- **Room 5.** The path stops. The world is still mostly intact, and that is why the stop feels wrong.
- **Rooms 6 through 8.** The mountain peels into a broken program. Color leaves the scenery. The player cubes lose their stable colors. The fall at the edge is the animation from room 4, seen from the other side.

## Ending

Past the seam, the summit copies the village poster: a large white circle at the top of the screen. Up close, the circle is a flat drawing with no depth, stuck to the back wall. It is not a place. It is the same moon from room 1, enlarged.

Around it, the scenery is broken. There is a grid, a window with no outside, a close button that does not respond, and cut-off text. The rope stretches, hits the edge of the screen, and stops. Jumping into the border does not pass through.

There is no higher hold. The floor under them fails. Both cubes fall down the mountain they climbed. The camera shows the ledge from room 4 go by, with two small cubes standing on it, watching. The falling bodies are the ones who said they were glad it was not them.

The level does not announce victory or explain an escape. There is no moon. There is no way out. The climb ends by becoming the fall it already showed.

## Online co-op

One player creates the room. The other joins with a code. Both see the same mountain, each on their own cube.

The session requires both players. If one leaves, the level pauses. The checkpoint is the room floor, shared: the rope makes no sense with one player at the start and the other at the top. If the connection drops in the middle of a gap, both return to the last safe floor.

The room 4 animation and the room 8 fall play for both players at once. The line is shared. The glitch crossing only counts when both cubes are through the seam.

The technical risk is syncing two physics bodies and a joint. Short rooms and frequent checkpoints limit the damage of a network error.

## Art and sound direction

Vector look, flat shapes, little detail. Holds, gaps, and the rope must read immediately.

Before the seam, the palette is warm and naive. Each player cube has one solid color. After the seam, the world drops toward broken interface gray, and the player cubes no longer hold a single color. Visual glitches stay graphic: offset shapes, stuck frames, clipped sprites, grid lines. They should read as the program failing, not as a second art style.

Sprites already planned for each cube's movement: idle, walk, jump, fall, and land. Blink and damage belong to the corrupted half. The room 4 fall uses the same fall sprite as the player cubes, so the echo is visible before it is explained.

Sound follows the two halves. Below the wall, adventure music. The fall in room 4 ducks the music for the line. From the seam up, the same music fails, repeats, and mixes with system noise. When the players fall at the edge, the music cuts.

## Out of scope

- A rope that reels in or changes its rest length, including a longer rope or extra stretch that bypasses the wall.
- A cube with different weight, jump, or ability.
- Corrupted control, delayed input, or inverted input.
- Corruption that starts in the village. The break begins at the seam.
- More regions, a campaign, or a solo mode.
- More than two players.
- Combat, inventory, and customization.
- A puzzle that needs a tool beyond walking, jumping, the rope, and the one seam. Climbing the rope is a recovery tool, never a puzzle solution.
- An ending in which the cubes escape, reach the moon, or shut down the simulation.
- A narration that identifies the falling cubes before room 8.

## Done criteria

The jam build is done when two players, online, climb the eight rooms in one session, use the rope for the honest ideas (anchor, swing, weight), say the line while other cubes fall, hit a wall the rope cannot cross, glitch past it, watch the scenery and their own colors corrupt, and finish by falling as the cubes from the middle of the mountain. There is no moon and no way out.
