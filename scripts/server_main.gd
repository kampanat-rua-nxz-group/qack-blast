extends SceneTree

const RoomServer = preload("res://scripts/room_server.gd")

var server = RoomServer.new()


func _initialize() -> void:
	var port := 9080
	var bind_address := "127.0.0.1"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--bind="):
			bind_address = argument.trim_prefix("--bind=")
	var error := server.listen(port, bind_address)
	if error != OK:
		push_error("Could not listen on %s:%d (%d)" % [bind_address, port, error])
		quit(1)
		return
	print("Qack Blast server listening on %s:%d" % [bind_address, port])


func _process(delta: float) -> bool:
	server.poll(delta)
	return false
