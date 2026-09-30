# object_pool.gd
# Autoload (ObjectPool): generic node pool keyed by scene resource path.
#
# Idle instances are kept OUT of the scene tree, so they cannot process, move,
# or receive physics signals while pooled. Pooled nodes are responsible for
# resetting their own state when they are reused (typically in initialize()
# or start()).
extends Node

# Maximum idle instances kept per scene; extras are freed on release.
const MAX_IDLE_PER_SCENE: int = 128

var _pools: Dictionary = {}  # scene path (String) -> Array[Node]

# Get an idle instance of `scene` (or instantiate one) and add it under `parent`.
func acquire(scene: PackedScene, parent: Node) -> Node:
	if scene == null:
		return null

	var node: Node = null
	var pool: Array = _pools.get(scene.resource_path, [])
	while not pool.is_empty():
		var candidate = pool.pop_back()
		if is_instance_valid(candidate):
			node = candidate
			break

	if node == null:
		node = scene.instantiate()
	else:
		# Undo what release() switched off
		node.remove_meta("_object_pool_released")
		node.set_process(true)
		node.set_physics_process(true)
		if node is CanvasItem:
			node.show()
		if node is Area2D:
			node.set_deferred("monitoring", true)
			node.set_deferred("monitorable", true)

	if parent:
		parent.add_child(node)
	return node

# Return a node to the pool. Safe to call from physics callbacks: the node is
# hidden and stopped immediately, and detached from the tree deferred.
func release(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta("_object_pool_released"):
		return
	node.set_meta("_object_pool_released", true)

	if node is CanvasItem:
		node.hide()
	node.set_process(false)
	node.set_physics_process(false)
	if node is Area2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)

	_store.call_deferred(node)

# Untyped: a deferred call may deliver a node freed in the meantime, which a
# typed parameter would reject with an error before the validity check.
func _store(node) -> void:
	if not is_instance_valid(node):
		return

	var key: String = node.scene_file_path
	if key.is_empty():
		node.queue_free()
		return

	if not _pools.has(key):
		_pools[key] = []
	var pool: Array = _pools[key]
	if pool.size() >= MAX_IDLE_PER_SCENE:
		node.queue_free()
		return

	var parent = node.get_parent()
	if parent:
		parent.remove_child(node)
	pool.append(node)

func _exit_tree() -> void:
	# Idle nodes are orphans (not in the tree); free them explicitly.
	for pool in _pools.values():
		for node in pool:
			if is_instance_valid(node):
				node.free()
	_pools.clear()
