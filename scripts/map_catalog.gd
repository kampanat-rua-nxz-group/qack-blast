extends RefCounted

const ENTRIES = {
	"fixed": {
		"name": "Classic",
		"terrain_text": "Fixed walls and clear paths. Break crates to open routes.",
		"pickup_text": "Bomb Capacity and Blast Range upgrades.",
		"hazard_text": "Sudden death: escalating danger bombs strike entire rows and columns.",
	},
	"random": {
		"name": "Random",
		"terrain_text": "Permanent walls reroll each round. Find new routes around them.",
		"pickup_text": "Mystery grants Bomb Capacity or Blast Range; both also drop normally.",
		"hazard_text": "Sudden death: increasingly many marked tiles burst into flames.",
	},
	"pond": {
		"name": "Lily Pond",
		"terrain_text": "Move at half normal speed. Shallow water slows you a further 20%.",
		"pickup_text": "Speed boosts movement everywhere; Bomb Capacity and Blast Range also drop.",
		"hazard_text": "Sudden death: deep water floods inward from the edges and eliminates ducks.",
	},
	"frost": {
		"name": "Frost Garden",
		"terrain_text": "Broad ice patches slide ducks one extra tile, unless a wall, crate or bomb blocks the path.",
		"pickup_text": "Bomb Kick: walk into a bomb to send it toward the next blocker. Capacity and Range also drop.",
		"hazard_text": "Sudden death: increasingly many marked rows are struck by blizzards.",
	},
	"night": {
		"name": "Nightfall",
		"terrain_text": "A small spotlight follows your duck. Walls reshuffle at 1:00 and 2:00, avoiding ducks and items.",
		"pickup_text": "Sight widens your spotlight; Bomb Capacity and Blast Range also drop.",
		"hazard_text": "Sudden death: permanent walls close inward from the edges.",
	},
}


static func describe(mode: String) -> Dictionary:
	var entry: Dictionary = ENTRIES.get(mode, ENTRIES.fixed).duplicate(true)
	# A hand-authored illustration, independent of ArenaGame and its RNG.
	entry.preview = ["#######", "#..c..#", "#.#.#.#", "#c...c#", "#.#.#.#", "#..c..#", "#######"] if mode != "random" else ["#######", "#..#c.#", "#c....#", "#..#.c#", "#.#...#", "#...#.#", "#######"]
	entry.preview_text = "Layout example — rerolls each round" if mode == "random" else "Representative layout — not the round board"
	return entry
