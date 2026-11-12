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

## Moves the files in `part` into `folder`, first setting aside the files
## `folder` holds of `names`, which go back if any move fails; "" or why not.
static func move_in(part: String, folder: String, names: Array) -> String:
	var previous := folder.get_base_dir().path_join(".%s.previous" % folder.get_file())
	var made := not DirAccess.dir_exists_absolute(folder)
	remove_tree(previous)
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.make_dir_recursive_absolute(previous)
	var aside := []
	var placed := []
	var reason := ""
	for name in names:
		if FileAccess.file_exists(folder.path_join(name)):
			if DirAccess.rename_absolute(folder.path_join(name), previous.path_join(name)) != OK:
				reason = "%s could not be set aside" % folder.path_join(name)
				break
			aside.append(name)
	if reason == "":
		for name in DirAccess.get_files_at(part):
			if DirAccess.rename_absolute(part.path_join(name), folder.path_join(name)) != OK:
				reason = "it could not be moved into %s" % folder
				break
			placed.append(name)
	if reason == "":
		remove_tree(previous)
		return ""
	for name in placed:
		DirAccess.remove_absolute(folder.path_join(name))
	var kept := true
	for name in aside:
		kept = DirAccess.rename_absolute(previous.path_join(name), folder.path_join(name)) == OK and kept
	if kept:
		remove_tree(previous)
	if made:
		DirAccess.remove_absolute(folder)
	return reason if kept else "%s; the files it held are in %s" % [reason, previous]
