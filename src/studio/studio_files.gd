class_name StudioFiles

## Removes a folder and everything in it; a link inside is removed, never followed.
static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for name in dir.get_directories():
		if dir.is_link(name):
			dir.remove(name)
		else:
			remove_tree(path.path_join(name))
	for name in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(path)
