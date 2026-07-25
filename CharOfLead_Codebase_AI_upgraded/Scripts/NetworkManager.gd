extends Node
## NetworkManager — autoload for online 2-player P2P via WebSocket (HTML5 Chrome & Desktop compatible).
## Host picks their role (Red=1 / Blue=2 / Random=0).
## Client always gets the complementary role, assigned by host RPC.

signal connected
signal connection_failed
signal peer_disconnected

const DEFAULT_PORT := 7777
const DEFAULT_CLOUD_SERVER := "wss://sam3.onrender.com"

var is_online:      bool = false
var is_host:        bool = false
var is_game_started:bool = false
var local_pid:      int  = 1    ## 1=Red Soldier, 2=Blue Assassin
var remote_peer_id: int  = 0


var current_room_code: String = ""


func generate_random_room_code() -> String:
	current_room_code = "%06d" % randi_range(100000, 999999)
	return current_room_code


## Start as host. chosen_role: 0=random, 1=Red, 2=Blue.
## Returns an error string on failure, "" on success.
func start_host(chosen_role: int = 0, port: int = DEFAULT_PORT) -> String:
	stop()
	generate_random_room_code()
	local_pid = randi_range(1, 2) if chosen_role == 0 else chosen_role
	var peer := WebSocketMultiplayerPeer.new()
	var err  := peer.create_server(port)
	if err != OK:
		# Fallback to alternate ports if 7777 is occupied by a background process
		for alt_port in range(7778, 7788):
			err = peer.create_server(alt_port)
			if err == OK:
				break
		if err != OK:
			return "Port occupied by another process. Please close previous instances."

	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_online = true
	is_host   = true
	return ""


static func save_last_code(code: String) -> void:
	var f := FileAccess.open("user://last_room_code.txt", FileAccess.WRITE)
	if f:
		f.store_string(code)
		f.close()


static func load_last_code() -> String:
	if FileAccess.file_exists("user://last_room_code.txt"):
		var f := FileAccess.open("user://last_room_code.txt", FileAccess.READ)
		if f:
			var c := f.get_as_text().strip_edges()
			f.close()
			return c
	return ""


## Connect to a host using a Room Code, direct IP, domain, or Cloud Relay Server.
## Works in HTML5 / Chrome & Desktop.
func start_join(code_or_ip: String, port: int = DEFAULT_PORT) -> String:
	stop()
	save_last_code(code_or_ip)
	var raw := code_or_ip.strip_edges()
	var url := ""

	if raw.begins_with("ws://") or raw.begins_with("wss://"):
		url = raw
	elif raw.contains("onrender.com") or raw.contains("playit.gg") or raw.contains("ngrok.io"):
		url = "wss://%s" % raw.trim_prefix("https://").trim_prefix("http://")
	elif raw.to_lower() in ["local", "localhost", "127.0.0.1", "0", "me"]:
		url = "ws://127.0.0.1:%d" % port
	elif raw.contains("."):
		url = "ws://%s:%d" % [raw, port]
	else:
		# 6-Digit Room Code: Route over Cloud Server wss://sam3.onrender.com
		url = "%s?room=%s" % [DEFAULT_CLOUD_SERVER, raw]

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return "Cannot connect to %s" % url
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	is_online      = true
	is_host        = false
	remote_peer_id = 1
	return ""


func stop() -> void:
	is_online       = false
	is_host         = false
	is_game_started = false
	if multiplayer:
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_connected_to_server)
		if multiplayer.connection_failed.is_connected(_on_connection_failed):
			multiplayer.connection_failed.disconnect(_on_connection_failed)
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null


## Returns a best-guess LAN/VPN IP for sharing with the joiner (filtering out APIPA 169.254.x.x).
func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("169.254.") or addr.begins_with("127."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"


## Returns the Room Code for the current host.
func get_room_code() -> String:
	if current_room_code != "":
		return current_room_code
	return generate_random_room_code()


# ── Room Code Encoding / Decoding ──────────────────────────────────────────────

static func ip_to_code(ip: String) -> String:
	var parts := ip.split(".")
	if parts.size() == 4:
		var b0 := parts[0].to_int()
		var b1 := parts[1].to_int()
		var b2 := parts[2].to_int()
		var b3 := parts[3].to_int()
		if b0 == 192 and b1 == 168:
			return "%d%03d" % [b2, b3]
		var val: int = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
		return _int_to_base36(val)
	return ip


static func code_to_ip(code: String) -> String:
	var clean := code.strip_edges().to_upper()
	if clean in ["", "LOCAL", "LOCALHOST", "127.0.0.1", "0", "ME"]:
		return "127.0.0.1"
	if clean.contains("."):
		return clean
	if clean.is_valid_int() and clean.length() <= 6:
		var val := clean.to_int()
		var b2 := val / 1000
		var b3 := val % 1000
		var prefix := "192.168."
		for addr in IP.get_local_addresses():
			if addr.begins_with("169.254.") or addr.begins_with("127."):
				continue
			if addr.begins_with("192.168."):
				break
			elif addr.contains("."):
				var p := addr.split(".")
				prefix = "%s.%s." % [p[0], p[1]]
				break
		return "%s%d.%d" % [prefix, b2, b3]

	var int_val := _base36_to_int(clean)
	if int_val > 0:
		var b0 := (int_val >> 24) & 0xFF
		var b1 := (int_val >> 16) & 0xFF
		var b2 := (int_val >> 8) & 0xFF
		var b3 := int_val & 0xFF
		return "%d.%d.%d.%d" % [b0, b1, b2, b3]

	return "127.0.0.1"


static func _int_to_base36(val: int) -> String:
	const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	if val <= 0: return "0"
	var res := ""
	while val > 0:
		res = CHARS[val % 36] + res
		val /= 36
	return res


static func _base36_to_int(code: String) -> int:
	const CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var val := 0
	for i in code.length():
		var ch = code[i]
		var idx := CHARS.find(ch)
		if idx == -1: return 0
		val = val * 36 + idx
	return val


# ── Internal Signals ──────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	remote_peer_id = id
	rpc_id(id, "_rpc_assign_role", 3 - local_pid)
	connected.emit()


func _on_connected_to_server() -> void:
	pass


func _on_connection_failed() -> void:
	is_online = false
	connection_failed.emit()


func _on_peer_disconnected(_id: int) -> void:
	peer_disconnected.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_assign_role(pid: int) -> void:
	local_pid = pid
	connected.emit()


signal client_ready_for_sync(peer_id: int)


## Called by Main.gd on both peers after _start_game() completes building scenes.
func notify_client_ready() -> void:
	if not is_online: return
	if is_host:
		# Host is ready, waiting for client ready notification
		pass
	else:
		# Client is ready, inform Host
		rpc_id(1, "_rpc_client_ready")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_ready() -> void:
	if is_host:
		is_game_started = true
		client_ready_for_sync.emit(remote_peer_id)
		if remote_peer_id != 0:
			rpc_id(remote_peer_id, "_rpc_start_match")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_match() -> void:
	is_game_started = true
