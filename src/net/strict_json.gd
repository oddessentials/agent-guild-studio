class_name StrictJson
extends RefCounted
## JSON that strict readers accept. JSON.stringify leaves most control
## characters raw and writes a vertical tab as \v: the manager (Node's
## JSON.parse) refuses both, and Godot's own parser can't read the \v back.
## Here they become \u escapes. Outside strings JSON.stringify writes no
## backslash, and raw only the newlines an indent adds, which it escapes
## inside strings, so a match is always inside a string.

static var _found := RegEx.create_from_string("[\\x01-\\x07\\x0e-\\x1f]|\\\\.")

static func stringify(value, indent := "") -> String:
	var text := JSON.stringify(value, indent)
	var parts := PackedStringArray()
	var at := 0
	for m in _found.search_all(text):
		var found := m.get_string()
		if found.length() == 2 and found != "\\v":
			continue
		parts.append(text.substr(at, m.get_start() - at))
		parts.append("\\u000b" if found == "\\v" else "\\u%04x" % found.unicode_at(0))
		at = m.get_end()
	if parts.is_empty():
		return text
	parts.append(text.substr(at))
	return "".join(parts)
