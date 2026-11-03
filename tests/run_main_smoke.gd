extends SceneTree

var _held_playback: AudioStreamPlayback
## 读取project.godot的真实入口，运行初始化后发出根窗口关闭请求，不强制截断音频线程。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var packed := load(entry) as PackedScene
	if packed == null:
		_fail("无法加载配置入口：" + entry)
		return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	for frame: int in 120:
		await process_frame
	var connector := main.get_node_or_null("运行层连接器")
	if connector == null or auto_accept_quit or not root.close_requested.is_connected(Callable(connector, &"request_quit")):
		_fail("正式入口未接入正常退出收尾。")
		return
	var ambience := main.find_child("舱内环境音", true, false) as AudioStreamPlayer
	if ambience == null or not ambience.has_stream_playback():
		_fail("循环MP3没有播放，不能验证播放中退出。")
		return
	# 反例用于确认超时会返回非零退出码；只存在于测试宿主，不进入正式游戏。
	if "--retain-audio-playback" in OS.get_cmdline_user_args():
		_held_playback = ambience.get_stream_playback()
	print("MAIN SMOKE READY | entry=", entry, " | ambience_playing=true")
	# 正常窗口关闭路径与重复请求均走正式代码；清理超时由运行层返回失败。
	root.close_requested.emit()
	root.close_requested.emit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
