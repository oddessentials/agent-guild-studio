class_name LocalServer
extends RefCounted
## A web server on this computer for tests: answers each path in `serving`
## with its bytes, anything else with 404, and never answers a path in
## `holding`. poll() once a frame.

var port := 0
var serving := {}
var holding := []
var pausing := {}
var requested := []
var _server := TCPServer.new()
var _peers := []

## Starts listening; false when no port was free.
func start() -> bool:
	for candidate in range(47810, 47840):
		if _server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			return true
	return false

func stop() -> void:
	_peers.clear()
	_server.stop()

func poll() -> void:
	while _server.is_connection_available():
		_peers.append([_server.take_connection(), "", PackedByteArray(), 0])
	for entry in _peers.duplicate():
		var peer: StreamPeerTCP = entry[0]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(entry)
			continue
		var waiting := peer.get_available_bytes()
		if waiting > 0:
			entry[1] += peer.get_partial_data(waiting)[1].get_string_from_utf8()
		if not String(entry[1]).contains("\r\n\r\n"):
			continue
		var path := String(entry[1]).get_slice(" ", 1)
		if not path in requested:
			requested.append(path)
		if path in holding:
			continue
		if entry[2].is_empty():
			var body: PackedByteArray = serving.get(path, PackedByteArray())
			var head := "HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % ["200 OK" if serving.has(path) else "404 Not Found", body.size()]
			entry[2] = head.to_utf8_buffer() + body
		var limit: int = pausing.get(path, entry[2].size())
		if entry[3] >= limit:
			continue
		var sent := peer.put_partial_data(entry[2].slice(entry[3], limit))
		entry[3] += sent[1]
		if sent[0] != OK or entry[3] == entry[2].size():
			peer.disconnect_from_host()
			_peers.erase(entry)

## `size` bytes and the art lock's entry for them, as `asset`.
static func pack(asset: String, size: int) -> Array:
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = i % 251
	var sum := HashingContext.new()
	sum.start(HashingContext.HASH_SHA256)
	sum.update(bytes)
	return [bytes, { "asset": asset, "size": size, "sha256": sum.finish().hex_encode() }]
