class_name YardRig
## Reads what rig.py writes into each model (docs/yard/CONTRACT.md "Models").

## The `yard` extras (height, stride, cycle, surface, events) on the
## skeleton's node, which Godot imports as the node's "extras" metadata.
static func extras(root: Node) -> Dictionary:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("extras"):
			var data = node.get_meta("extras")
			if data is Dictionary and data.has("yard"):
				return data.yard
		stack.append_array(node.get_children())
	return {}
