extends RefCounted

# Original procedural costumes; IDs belong to people, never round slots.
const COLORS = [Color("65cfc6"), Color("f58fb1"), Color("f4c66c"), Color("a995e8"), Color("7abf70"), Color("e58a5e"), Color("82aee8"), Color("bd976d"), Color("db87cb"), Color("b5c858")]
const ACCESSORIES = ["sailor", "goggles", "chef", "sprout", "bow", "visor", "crown", "detective", "knit", "crest"]

static func appearance(avatar_id: int) -> Dictionary:
	if avatar_id < 0 or avatar_id >= COLORS.size():
		return {"avatar_id": -1, "badge": "?", "palette": {"body": Color("a8adb8"), "accent": Color("e7e8eb"), "outline": Color("403d57")}, "accessory": "none"}
	return {"avatar_id": avatar_id, "badge": str(avatar_id + 1), "palette": {"body": COLORS[avatar_id], "accent": COLORS[avatar_id].lightened(0.5), "outline": Color("403d57")}, "accessory": ACCESSORIES[avatar_id]}
