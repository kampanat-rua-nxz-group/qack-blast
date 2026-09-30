extends SceneTree

# Regenerates every file in assets/audio/ from plain math (sine, triangle, seeded noise).
# Run: Godot --headless --path . --script tools/generate_sounds.gd
# Output is deterministic; no recordings or third-party samples are used.

const RATE := 22050
const OUT_DIR := "res://assets/audio/"


func _initialize() -> void:
	write("place", place())
	write("explode", explode())
	write("pickup", pickup())
	write("eliminate", eliminate())
	write("countdown", tone(880.0, 0.12, 0.45, 18.0))
	write("win", arpeggio([523.25, 659.25, 783.99, 1046.5], 0.13, 0.32))
	write("loss", arpeggio([392.0, 329.63, 261.63], 0.2, 0.34))
	write("draw", arpeggio([440.0, 440.0], 0.22, 0.3))
	quit()


func write(name: String, samples: PackedFloat32Array) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var header := PackedByteArray()
	header.append_array("RIFF".to_ascii_buffer())
	header.resize(8)
	header.encode_u32(4, 36 + data.size())
	header.append_array("WAVEfmt ".to_ascii_buffer())
	header.resize(20)
	header.encode_u32(16, 16)
	header.resize(36)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, RATE)
	header.encode_u32(28, RATE * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.append_array("data".to_ascii_buffer())
	header.resize(44)
	header.encode_u32(40, data.size())
	var file := FileAccess.open(OUT_DIR + name + ".wav", FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + name)
		return
	file.store_buffer(header)
	file.store_buffer(data)
	file.close()


func blank(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


func tone(freq: float, seconds: float, gain: float, decay: float) -> PackedFloat32Array:
	var samples := blank(seconds)
	for i in range(samples.size()):
		var t := float(i) / RATE
		samples[i] = sin(TAU * freq * t) * exp(-decay * t) * gain * minf(1.0, t * 800.0) * minf(1.0, (seconds - t) * 150.0)
	return samples


func place() -> PackedFloat32Array:
	var samples := blank(0.14)
	var phase := 0.0
	for i in range(samples.size()):
		var t := float(i) / RATE
		phase += TAU * lerpf(220.0, 80.0, minf(1.0, t / 0.1)) / RATE
		samples[i] = sin(phase) * exp(-24.0 * t) * 0.55 * minf(1.0, t * 1000.0)
	return samples


func explode() -> PackedFloat32Array:
	var samples := blank(0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var low := 0.0
	for i in range(samples.size()):
		var t := float(i) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * lerpf(0.5, 0.06, minf(1.0, t / 0.4))
		var thump := sin(TAU * 62.0 * t) * exp(-9.0 * t)
		samples[i] = (low * 1.6 * exp(-6.5 * t) + thump * 0.6) * 0.5 * minf(1.0, t * 1500.0)
	return samples


func pickup() -> PackedFloat32Array:
	var first := tone(660.0, 0.09, 0.4, 10.0)
	var second := tone(990.0, 0.16, 0.4, 12.0)
	first.append_array(second)
	return first


func eliminate() -> PackedFloat32Array:
	var samples := blank(0.45)
	var phase := 0.0
	for i in range(samples.size()):
		var t := float(i) / RATE
		phase += TAU * lerpf(520.0, 110.0, minf(1.0, t / 0.4)) / RATE
		var triangle := asin(sin(phase)) * 2.0 / PI
		samples[i] = triangle * exp(-3.5 * t) * 0.45 * minf(1.0, t * 600.0)
	return samples


func arpeggio(freqs: Array, step: float, gain: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for freq in freqs:
		samples.append_array(tone(freq, step, gain, 7.0))
	var tail := tone(freqs.back(), 0.3, gain, 8.0)
	samples.append_array(tail)
	return samples
