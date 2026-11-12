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

## A new, empty folder beside `folder` that only the caller holds, or "".
static func make_beside(folder: String, kind: String) -> String:
	var parent := folder.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent)
	for n in range(1, 1000):
		var path := parent.path_join(".%s.%s%s" % [folder.get_file(), "" if n == 1 else "%d." % n, kind])
		var err := DirAccess.make_dir_absolute(path)
		if err == OK:
			return path
		if err != ERR_ALREADY_EXISTS:
			break
	return ""

## Moves the files in `part` into `folder`, first setting aside the files
## `folder` holds of `names`, which go back if any move fails; "" or why not.
static func move_in(part: String, folder: String, names: Array) -> String:
	var previous := make_beside(folder, "previous")
	if previous == "":
		return "a folder to work in could not be made in %s" % folder.get_base_dir()
	var made := not DirAccess.dir_exists_absolute(folder)
	DirAccess.make_dir_recursive_absolute(folder)
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
