extends RefCounted

const AudioShutdown := preload("res://scripts/runtime/audio_shutdown.gd")
const AMBIENCE := preload("res://assets/audio/sfx/cabin/ambience.mp3")
const CLICK := preload("res://assets/audio/sfx/cabin/main_click_1.wav")


func run(t: Variant, tree: SceneTree) -> void:
	var host := Node.new()
	t.add_child(host)
	var music := AudioStreamPlayer.new()
	music.stream = AMBIENCE
	host.add_child(music)
	var spatial := AudioStreamPlayer3D.new()
	spatial.stream = CLICK
	host.add_child(spatial)
	var flat := AudioStreamPlayer2D.new()
	flat.stream = CLICK
	host.add_child(flat)
	music.play()
	spatial.play()
	flat.play()
	await tree.process_frame
	var music_ref: WeakRef = weakref(music.get_stream_playback())
	var spatial_ref: WeakRef = weakref(spatial.get_stream_playback())
	var flat_ref: WeakRef = weakref(flat.get_stream_playback())
	# 故意保留一个强引用：即使stop成功，也不能把尚未销毁误报为清理完成。
	var held_playback: AudioStreamPlayback = music.get_stream_playback()
	t.assert_true("音频退出 / 反例确实持有播放实例", held_playback != null)
	var timed_out := not await AudioShutdown.stop_and_wait(host, tree, 0)
	t.assert_true("音频退出 / 持有播放实例时报告超时", timed_out)
	t.assert_false("音频退出 / 已停止MP3播放", music.playing)
	t.assert_true("音频退出 / 超时仍保留真实弱引用", music_ref.get_ref() != null)
	held_playback = null
	var released := await AudioShutdown.stop_and_wait(host, tree)
	t.assert_true("音频退出 / 放开引用后清理成功", released)
	t.assert_true("音频退出 / MP3播放实例实际销毁", music_ref.get_ref() == null)
	t.assert_true("音频退出 / 3D WAV播放实例实际销毁", spatial_ref.get_ref() == null)
	t.assert_true("音频退出 / 2D WAV播放实例实际销毁", flat_ref.get_ref() == null)
	t.assert_true("音频退出 / 无播放时可重复清理", await AudioShutdown.stop_and_wait(host, tree))
	# 复现测试夹具先被移出场景的情况；node_removed收尾必须保留待释放实例的弱引用。
	music.play()
	var removed_ref: WeakRef = weakref(music.get_stream_playback())
	host.remove_child(music)
	music.free()
	t.assert_true("音频退出 / 已移除播放器仍完成清理", await AudioShutdown.stop_and_wait(host, tree))
	t.assert_true("音频退出 / 已移除播放器实例实际销毁", removed_ref.get_ref() == null)
	host.queue_free()
	await tree.process_frame
