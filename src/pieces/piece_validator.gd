class_name PieceValidator
extends Node

const DIR := "user://pieces/checks/"

var timeout := PieceCheck.TIMEOUT
var source_timeout := PieceCheck.SOURCE_TIMEOUT
var pid := -1
var _count := 0
var _out := ""

func check(path: String, kind: String, clips: Dictionary, stage := "", fault := "") -> Dictionary:
	var args := ["--check-piece=" + ProjectSettings.globalize_path(path), "--check-kind=" + kind,
		"--check-clips=" + PieceCheck.clips_arg(clips)]
	if stage != "":
		args.append("--check-stage=" + stage)
	return await _run(args, timeout, fault)

func check_source(path: String, dir: String, fault := "") -> Dictionary:
	var verdict := await _run(["--check-source=" + path, "--check-dir=" + dir], source_timeout, fault)
	if not verdict.get("files", []) is Array:
		return { "reason": "it crashed the checker" }
	return verdict

func _run(what: Array, wait: float, fault: String) -> Dictionary:
	while pid != -1:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_count += 1
	var out := ProjectSettings.globalize_path(DIR + "%d-%d.json" % [OS.get_process_id(), _count])
	_out = out
	DirAccess.remove_absolute(out)
	var args := ["--headless", "--log-file", ProjectSettings.globalize_path(DIR + "check.log")]
	if OS.has_feature("editor"):
		args += ["--path", ProjectSettings.globalize_path("res://")]
	args += ["--"] + what + ["--check-out=" + out, "--check-timeout=%s" % wait]
	if fault != "":
		args.append("--check-fault=" + fault)
	pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		pid = -1
		return { "reason": "the checker could not start" }
	var deadline := Time.get_ticks_msec() + int(wait * 1000)
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			pid = -1
			DirAccess.remove_absolute(out)
			return { "reason": "it took too long to check" }
		await get_tree().process_frame
	var code := OS.get_process_exit_code(pid)
	pid = -1
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	var verdict = JSON.parse_string(text) if text != "" else null
	if code != 0 or not verdict is Dictionary or not verdict.get("reason") is String:
		return { "reason": "it crashed the checker" }
	return verdict

func _exit_tree() -> void:
	if pid != -1 and OS.is_process_running(pid):
		OS.kill(pid)
	if pid != -1:
		DirAccess.remove_absolute(_out)
	pid = -1
