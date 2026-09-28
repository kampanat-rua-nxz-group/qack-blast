extends SceneTree

var elapsed := 0.0
var app


func _initialize() -> void:
	app = load("res://scenes/online.tscn").instantiate()
	root.add_child(app)
	call_deferred("try_create")


func try_create() -> void:
	app.server_field.text = "ws://127.0.0.1:19089"
	app.request({"type": "create", "name": "Duck"})


func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	var reported: bool = app.status_label.text.contains("Start the Godot room server")
	app.status_label.text = ""
	app.client.connecting = true
	app.client._process(0.0)
	reported = reported and app.status_label.text.contains("Start the Godot room server")
	print("Connection error check: %s" % ("passed" if reported else "FAILED: %s" % app.status_label.text))
	quit(0 if reported else 1)
	return false
