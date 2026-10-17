class_name Music
extends AudioStreamPlayer

## Synthesized adventure loop (no audio assets yet). Below the wall it plays clean; the
## camp line ducks it; from the seam up it stutters, detunes, crushes and mixes with
## noise; at the final fall it cuts.

enum State { PLAY, DUCK, CORRUPT, CUT }

const MIX_RATE := 22050.0
const BPM := 104.0
const CHORDS: Array[int] = [48, 43, 45, 41]
const SCALE: Array[int] = [60, 62, 64, 67, 69, 72, 74, 76]

var state: State = State.PLAY

var _playback: AudioStreamGeneratorPlayback
var _melody: Array[int] = []
var _step: int = 0
var _step_samples: int = 0
var _sample_in_step: int = 0
var _mel_phase: float = 0.0
var _bass_phase: float = 0.0
var _mel_freq: float = 0.0
var _bass_freq: float = 0.0
var _volume: float = 0.0
var _target_volume: float = 0.22
var _detune: float = 1.0
var _crush: bool = false
var _noise: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_compose()
	if DisplayServer.get_name() == "headless":
		# Nobody hears it, and the dummy driver's mixing thread can stall shutdown.
		set_process(false)
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _compose() -> void:
	_step_samples = int(MIX_RATE * 60.0 / BPM / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_melody.clear()
	for i in 32:
		_melody.append(-1 if rng.randf() < 0.28 else SCALE[rng.randi_range(0, SCALE.size() - 1)])
	_begin_step()


func _exit_tree() -> void:
	stop()


func set_state(value: State) -> void:
	state = value
	match state:
		State.PLAY:
			_target_volume = 0.22
		State.DUCK:
			_target_volume = 0.05
		State.CORRUPT:
			_target_volume = 0.18
		State.CUT:
			_target_volume = 0.0
			_volume = 0.0


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames > 0:
		_playback.push_buffer(render(frames))


## Synthesizes the next `frames` stereo samples.
func render(frames: int) -> PackedVector2Array:
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var step_len := float(_step_samples)
	for i in frames:
		_volume = move_toward(_volume, _target_volume, 0.00002)
		var env := 1.0 - float(_sample_in_step) / step_len
		var s := 0.0
		if _mel_freq > 0.0:
			_mel_phase = fmod(_mel_phase + _mel_freq * _detune / MIX_RATE, 1.0)
			s += (1.0 if _mel_phase < 0.25 else -1.0) * 0.35 * env * env
		_bass_phase = fmod(_bass_phase + _bass_freq / MIX_RATE, 1.0)
		s += (absf(_bass_phase * 4.0 - 2.0) - 1.0) * 0.45
		if _noise > 0.0:
			s += _rng.randf_range(-1.0, 1.0) * _noise * env
		if _crush:
			s = round(s * 6.0) / 6.0
		s *= _volume
		buffer[i] = Vector2(s, s)
		_sample_in_step += 1
		if _sample_in_step >= _step_samples:
			_sample_in_step = 0
			_step = (_step + 1) % 32
			_begin_step()
	return buffer


func _begin_step() -> void:
	if state == State.CORRUPT and _rng.randf() < 0.22:
		# The program sticks and repeats the last step.
		_step = (_step + 31) % 32
	var note := _melody[_step]
	_mel_freq = 0.0 if note < 0 else 440.0 * pow(2.0, (note - 69) / 12.0)
	var root := CHORDS[(_step / 8) % CHORDS.size()]
	_bass_freq = 440.0 * pow(2.0, (root - 69) / 12.0)
	if state == State.CORRUPT:
		_detune = pow(2.0, _rng.randf_range(-1.0, 1.0) / 12.0) if _rng.randf() < 0.3 else 1.0
		_crush = _rng.randf() < 0.4
		_noise = _rng.randf_range(0.1, 0.4) if _rng.randf() < 0.2 else 0.0
	else:
		_detune = 1.0
		_crush = false
		_noise = 0.0
