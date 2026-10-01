extends RefCounted

const PROFILES = {
	"easy": {"interval_min": 0.60, "interval_max": 0.90, "prediction_seconds": 0.0, "candidate_limit": 1},
	"medium": {"interval_min": 0.30, "interval_max": 0.45, "prediction_seconds": 0.0, "candidate_limit": 4},
	"hard": {"interval_min": 0.15, "interval_max": 0.25, "prediction_seconds": 0.50, "candidate_limit": 8},
	"extreme": {"interval_min": 0.08, "interval_max": 0.15, "prediction_seconds": 1.00, "candidate_limit": 12},
}


static func get_profile(difficulty: String) -> Dictionary:
	return PROFILES[difficulty].duplicate(true) if is_valid(difficulty) else {}


static func is_valid(difficulty: String) -> bool:
	return PROFILES.has(difficulty)
