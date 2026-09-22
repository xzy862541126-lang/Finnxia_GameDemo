extends Node

## Procedurally synthesized pixel sound effects. No external audio assets required.

const SETTINGS_PATH: String = "user://audio_settings.cfg"
const BUS_NAME: StringName = &"GameSfx"
var enabled: bool = true
var volume_db: float = -9.0
var last_played: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _streams: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	AudioServer.add_bus(AudioServer.get_bus_count())
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, BUS_NAME)
	_sync_bus()
	for index: int in range(6):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = BUS_NAME
		voice.volume_db = 0.0
		add_child(voice)
		_voices.append(voice)
	_build_streams()

func _sync_bus() -> void:
	var bus: int = AudioServer.get_bus_index(BUS_NAME)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, -80.0 if not enabled else volume_db)
		AudioServer.set_bus_mute(bus, not enabled)

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	enabled = bool(config.get_value("audio", "enabled", true))
	volume_db = clampf(float(config.get_value("audio", "volume_db", -9.0)), -40.0, 6.0)

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "enabled", enabled)
	config.set_value("audio", "volume_db", volume_db)
	config.save(SETTINGS_PATH)

func set_enabled(value: bool) -> void:
	enabled = value
	_sync_bus()
	save_settings()

func set_volume_db(value: float) -> void:
	volume_db = clampf(value, -40.0, 6.0)
	_sync_bus()
	save_settings()

func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()
		voice.stream = null

func _exit_tree() -> void:
	stop_all()
	_streams.clear()

func play(name: StringName, throttle_seconds: float = 0.0) -> void:
	if not enabled:
		return
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if throttle_seconds > 0.0 and float(last_played.get(name, -1.0)) + throttle_seconds > now:
		return
	last_played[name] = now
	var voice: AudioStreamPlayer = _voices[_cursor]
	_cursor = (_cursor + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = 1.0
	voice.play()

func _build_streams() -> void:
	_streams[&"defeat"] = _synth([_tone(262, 0.12, 0.25, 0.0, 2), _tone(131, 0.24, 0.22, 0.1, 1)], 0.36, true)
	_streams[&"crush"] = _noise(0.2, 0.55, 500.0, 1.8, false)
	_streams[&"splash"] = _noise(0.44, 0.4, 1800.0, 1.4, true)
	_streams[&"cat"] = _synth([_tone(740, 0.15, 0.13, 0.0, 1), _tone(554, 0.18, 0.12, 0.1, 1)], 0.3, true)
	_streams[&"portal"] = _synth([_tone(330, 0.16, 0.19, 0.0, 1), _tone(660, 0.2, 0.17, 0.1, 1), _tone(990, 0.18, 0.15, 0.2, 1)], 0.4, true)
	_streams[&"treasure"] = _synth([_tone(659, 0.18, 0.23, 0.0, 2), _tone(988, 0.2, 0.2, 0.14, 2), _tone(1318, 0.34, 0.18, 0.3, 2)], 0.66, true)
	_streams[&"ui_hover"] = _synth([_tone(660, 0.05, 0.16, 0.0, 2)], 0.05, true)
	_streams[&"ui_click"] = _synth([_tone(520, 0.07, 0.32, 0.0, 2), _tone(780, 0.09, 0.24, 0.03, 2)], 0.12, true)
	_streams[&"ui_confirm"] = _synth([_tone(523, 0.10, 0.30, 0.0, 2), _tone(659, 0.12, 0.26, 0.06, 2), _tone(784, 0.16, 0.24, 0.13, 2)], 0.3, true)
	_streams[&"ui_back"] = _synth([_tone(392, 0.09, 0.26, 0.0, 2), _tone(294, 0.12, 0.22, 0.05, 2)], 0.18, true)
	_streams[&"walk"] = _noise(0.06, 0.20, 1200.0, 0.5, true)
	_streams[&"push"] = _noise(0.16, 0.24, 700.0, 0.35, false)
	_streams[&"bloom"] = _synth([_tone(880, 0.10, 0.22, 0.0, 2), _tone(1174, 0.16, 0.20, 0.07, 2), _tone(1568, 0.24, 0.18, 0.15, 2)], 0.42, true)
	_streams[&"bridge"] = _synth([_tone(196, 0.18, 0.24, 0.0, 1), _tone(262, 0.22, 0.20, 0.08, 1)], 0.32, false)
	_streams[&"placement"] = _synth([_tone(330, 0.10, 0.26, 0.0, 2), _tone(494, 0.14, 0.18, 0.05, 2)], 0.2, true)
	_streams[&"undo"] = _synth([_tone(494, 0.08, 0.22, 0.0, 2), _tone(370, 0.12, 0.20, 0.05, 2)], 0.18, true)
	_streams[&"win"] = _synth([_tone(523, 0.16, 0.26, 0.0, 2), _tone(659, 0.20, 0.24, 0.14, 2), _tone(784, 0.22, 0.22, 0.28, 2), _tone(1046, 0.34, 0.20, 0.44, 2)], 0.9, true)
	_streams[&"finale"] = _synth([_tone(392, 0.24, 0.24, 0.0, 2), _tone(523, 0.28, 0.22, 0.18, 2), _tone(659, 0.30, 0.20, 0.36, 2), _tone(784, 0.42, 0.20, 0.56, 2), _tone(1046, 0.60, 0.18, 0.78, 2)], 1.5, true)

func _tone(frequency: float, duration: float, amplitude: float, delay: float, harmonic: int) -> Dictionary:
	return {"frequency": frequency, "duration": duration, "amplitude": amplitude, "delay": delay, "harmonic": harmonic}

func _wave(frequency: float, sample_rate: float, index: int, harmonic: int) -> float:
	var phase: float = 2.0 * PI * frequency * float(index) / sample_rate
	match harmonic:
		1: return sin(phase) * 0.6 + sin(phase * 2.0) * 0.25
		2: return sign(sin(phase)) * 0.5 + sin(phase) * 0.25
	return sin(phase)

func _synth(tones: Array[Dictionary], total: float, fade_out: bool) -> AudioStreamWAV:
	var sample_rate: int = 44100
	var frames: PackedFloat32Array = PackedFloat32Array()
	var count: int = int(float(sample_rate) * total)
	frames.resize(count)
	for tone: Dictionary in tones:
		var start: int = int(float(sample_rate) * float(tone["delay"]))
		var length: int = int(float(sample_rate) * float(tone["duration"]))
		for offset: int in range(length):
			var index: int = start + offset
			if index >= count:
				break
			var progress: float = float(offset) / float(length)
			var envelope: float = minf(progress * 8.0, 1.0)
			if fade_out:
				envelope *= 1.0 - progress * progress
			else:
				envelope *= 1.0 - progress
			frames[index] += _wave(float(tone["frequency"]), float(sample_rate), offset, int(tone["harmonic"])) * float(tone["amplitude"]) * envelope
	return _to_wav(frames)

func _noise(total: float, amplitude: float, cutoff: float, decay: float, bright: bool) -> AudioStreamWAV:
	var sample_rate: int = 44100
	var frames: PackedFloat32Array = PackedFloat32Array()
	var count: int = int(float(sample_rate) * total)
	frames.resize(count)
	var random := RandomNumberGenerator.new()
	random.seed = 20260921
	var previous: float = 0.0
	for index: int in range(count):
		var progress: float = float(index) / float(count)
		var attack: float = minf(progress * 12.0, 1.0)
		var value: float = random.randf_range(-1.0, 1.0)
		var smoothing: float = 0.85 if not bright else 0.55
		previous = previous * smoothing + value * (1.0 - smoothing)
		frames[index] = previous * amplitude * attack * pow(1.0 - progress, decay)
	return _to_wav(frames)

func _to_wav(frames: PackedFloat32Array) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(frames.size() * 2)
	var peak: float = 0.0
	for value: float in frames:
		peak = maxf(peak, absf(value))
	if peak > 0.9:
		for index: int in range(frames.size()):
			frames[index] *= 0.9 / peak
	for index: int in range(frames.size()):
		var sample: int = clampi(int(roundf(clampf(frames[index], -1.0, 1.0) * 32767.0)), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.stereo = false
	stream.data = bytes
	return stream
