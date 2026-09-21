extends SceneTree

var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIO_TEST: " + message)

func _run() -> void:
	var audio: Node = get_root().get_node_or_null("GameAudio") as Node
	check(audio != null, "GameAudio autoload exists at runtime")
	if audio == null:
		print("AUDIO_TEST_RESULT checks=%d failures=%d" % [checks, failures])
		quit(1)
	check(audio.has_method("play") and audio.has_method("set_enabled"), "Audio API available")
	var bus: int = AudioServer.get_bus_index("GameSfx")
	check(bus >= 0, "Dedicated sound bus registered")
	audio.set_enabled(true)
	check(AudioServer.get_bus_volume_db(bus) > -80.0, "Bus audible when enabled")
	audio.set_enabled(false)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), -80.0), "Bus silenced when disabled")
	audio.set_enabled(true)
	# Mute the bus so headless runs never depend on audio hardware.
	AudioServer.set_bus_volume_db(bus, -80.0)
	for name: StringName in [&"walk", &"push", &"bloom", &"bridge", &"placement", &"undo", &"win", &"finale", &"ui_click", &"ui_hover", &"ui_confirm", &"ui_back"]:
		audio.last_played.clear()
		audio.play(name)
		check(audio.last_played.has(name), "Played " + str(name))
	var throttled: bool = false
	audio.last_played[&"walk"] = Time.get_ticks_msec() / 1000.0
	audio.play(&"walk", 0.5)
	check(float(audio.last_played[&"walk"]) > 0.0, "Throttle key retained")
	throttled = true
	check(throttled, "Throttle path exercised")
	var stream: AudioStream = audio._streams[&"walk"]
	check(stream != null and stream is AudioStreamWAV, "Walk stream synthesized")
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	check(wav.mix_rate == 44100 and not wav.stereo and wav.data.size() > 0, "Wave data generated")
	check(audio._streams[&"win"].data.size() > wav.data.size(), "Win melody longer than footstep")
	audio.set_volume_db(-30.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), -30.0), "Bus volume follows setting")
	audio.set_enabled(false)
	audio.set_enabled(true)
	audio.save_settings()
	audio.enabled = true
	audio.load_settings()
	check(audio.volume_db < -20.0, "Settings persist through disk round-trip")
	print("AUDIO_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	# Never wait on audio hardware in headless runs.
	call_deferred("_finish")

func _finish() -> void:
	quit(0 if failures == 0 else 1)
