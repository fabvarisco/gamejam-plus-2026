class_name Themes
extends RefCounted

## The scenery of each room: its name, sky and rock. Below the seam the mountain climbs
## through warm, readable places that get higher, colder and closer to the moon. Past the
## seam the same places come back as a broken program.

enum Style { GOO, GRID, WIRE, DEBUG, REUSED }

const NAMES: Array[String] = [
	"Village", "Forest", "Gorge", "Cave", "Camp", "Snowline", "Summit",
	"Seam", "Wireframe", "Rerun", "Debug", "Loading", "Edge",
]

## Sky gradient (top, bottom) and how much of a starfield shows.
const SKIES: Array = [
	[Color(0.98, 0.62, 0.38), Color(1.0, 0.86, 0.6), 0.0],
	[Color(0.52, 0.78, 0.7), Color(0.96, 0.92, 0.68), 0.0],
	[Color(0.42, 0.7, 0.9), Color(0.86, 0.95, 0.93), 0.0],
	[Color(0.07, 0.05, 0.12), Color(0.17, 0.11, 0.24), 0.15],
	[Color(0.93, 0.48, 0.33), Color(1.0, 0.78, 0.5), 0.0],
	[Color(0.58, 0.72, 0.92), Color(0.93, 0.95, 1.0), 0.0],
	[Color(0.06, 0.08, 0.22), Color(0.34, 0.28, 0.52), 1.0],
	[Color(0.16, 0.17, 0.2), Color(0.28, 0.29, 0.33), 0.0],
	[Color(0.03, 0.05, 0.1), Color(0.07, 0.12, 0.2), 0.0],
	[Color(0.3, 0.55, 0.6), Color(0.62, 0.86, 0.75), 0.0],
	[Color(0.2, 0.21, 0.24), Color(0.3, 0.31, 0.35), 0.0],
	[Color(0.02, 0.02, 0.03), Color(0.07, 0.07, 0.09), 0.0],
	[Color(0.16, 0.17, 0.2), Color(0.28, 0.29, 0.33), 0.0],
]

## Rock colors for the goo style: outline, body, inner body, top.
const ROCK: Array = [
	[Color(0.12, 0.06, 0.05), Color(0.33, 0.19, 0.11), Color(0.4, 0.25, 0.14), Color(0.58, 0.4, 0.2)],
	[Color(0.07, 0.08, 0.04), Color(0.27, 0.2, 0.11), Color(0.33, 0.25, 0.14), Color(0.4, 0.62, 0.24)],
	[Color(0.06, 0.08, 0.11), Color(0.3, 0.33, 0.38), Color(0.36, 0.4, 0.45), Color(0.5, 0.68, 0.48)],
	[Color(0.03, 0.02, 0.06), Color(0.2, 0.15, 0.28), Color(0.26, 0.2, 0.36), Color(0.62, 0.48, 0.9)],
	[Color(0.13, 0.06, 0.04), Color(0.4, 0.21, 0.12), Color(0.47, 0.27, 0.15), Color(0.74, 0.47, 0.22)],
	[Color(0.09, 0.11, 0.17), Color(0.4, 0.44, 0.53), Color(0.48, 0.53, 0.62), Color(0.97, 0.98, 1.0)],
	[Color(0.05, 0.05, 0.1), Color(0.29, 0.26, 0.38), Color(0.35, 0.31, 0.45), Color(0.84, 0.87, 0.98)],
]

const STYLES: Array[Style] = [
	Style.GOO, Style.GOO, Style.GOO, Style.GOO, Style.GOO, Style.GOO, Style.GOO,
	Style.GRID, Style.WIRE, Style.REUSED, Style.DEBUG, Style.GRID, Style.GRID,
]


static func rock(index: int) -> Array:
	# Past the seam the reused village takes the village rock with its colors swapped.
	if index < ROCK.size():
		return ROCK[index]
	return [ROCK[0][0], Color(0.2, 0.3, 0.45), Color(0.25, 0.38, 0.55), Color(0.95, 0.3, 0.7)]
