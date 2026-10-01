extends RefCounted
## Pure Nightfall falloff. Distances are in world units; offsets are in tiles beyond the Sight value.

const CLEAR_OFFSET := 0.4
const DIM_OFFSET := 0.9
const FULL_OFFSET := 2.4
const DIM_DARKNESS := 0.8


static func darkness_at(distance: float, vision: int, cell: float) -> float:
	var clear := (vision + CLEAR_OFFSET) * cell
	var dim := (vision + DIM_OFFSET) * cell
	var full := (vision + FULL_OFFSET) * cell
	if distance <= clear:
		return 0.0
	if distance >= full:
		return 1.0
	if distance <= dim:
		return DIM_DARKNESS * smooth((distance - clear) / (dim - clear))
	return DIM_DARKNESS + (1.0 - DIM_DARKNESS) * smooth((distance - dim) / (full - dim))


static func within_audio_reach(distance: float, vision: int, cell: float) -> bool:
	return distance <= (vision + DIM_OFFSET) * cell


static func smooth(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
