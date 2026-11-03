extends RefCounted
## 音频停止是异步的；只用弱引用记录待混音线程释放的播放实例，不延长它们的生命周期。

static var _pending_playbacks: Array[WeakRef] = []


static func track_removed_player(node: Node) -> void:
	# node_removed发生在退出树的过程中：此时只记录，不能再次修改节点的process group。
	# 节点的原生PREDELETE会停止播放；等待方继续观察音频线程持有的引用。
	if _is_player(node) and node.has_stream_playback():
		_pending_playbacks.append(weakref(node.get_stream_playback()))


static func _is_player(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


static func stop_and_wait(scene_root: Node, tree: SceneTree, timeout_ms: int = 1000) -> bool:
	_stop_subtree(scene_root)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not _release_completed():
		if Time.get_ticks_msec() >= deadline:
			return false
		# 暂停/慢速游戏中也继续退出收尾；等待条件是引用消失，不是固定延迟后假定成功。
		await tree.create_timer(0.01, true, false, true).timeout
	return true


static func _stop_subtree(node: Node) -> void:
	if _is_player(node):
		track_removed_player(node)
		node.stop()
	for child: Node in node.get_children():
		_stop_subtree(child)


static func _release_completed() -> bool:
	for index: int in range(_pending_playbacks.size() - 1, -1, -1):
		if _pending_playbacks[index].get_ref() == null:
			_pending_playbacks.remove_at(index)
	return _pending_playbacks.is_empty()
