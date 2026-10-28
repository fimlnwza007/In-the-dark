extends Node

## NetworkManager: ระบบเครือข่าย Multiplayer แบบ WebRTC + Room Code
## รองรับทั้ง Web (HTML5), Mobile, และ PC ทุกคนสามารถสร้างห้องได้โดยไม่มี Error 20!

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal player_list_updated
signal status_message_updated(message: String, is_error: bool)
signal room_created(room_code: String)
signal room_joined(room_code: String)

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 8

# สามารถเปลี่ยน Signaling URL เป็นเซิร์ฟเวอร์บน Glitch / Render ได้ตามต้องการ
# ถ้าเปิดทดสอบบนเครื่องตนเอง ให้ใช้ "ws://localhost:9080" หรือ "ws://127.0.0.1:9080"
# ตัวอย่าง Production: "wss://alone-in-the-dusk.glitch.me"
@export var signaling_server_url: String = "wss://in-the-dark-yj0r.onrender.com"

const ICE_SERVERS = [
	{ "urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }
]

var is_online: bool = false
var my_name: String = "Player"
var my_peer_id: int = 1
var current_room_code: String = ""

# players: id -> { "name": String, "id": int, "is_host": bool }
var players: Dictionary = {}

var peer: MultiplayerPeer = null
var rtc_peer: WebRTCMultiplayerPeer = null

# WebRTC & Signaling variables
var _ws: WebSocketPeer = null
var _peer_connections: Dictionary = {} # peer_id -> WebRTCPeerConnection
var _remote_desc_set: Dictionary = {}  # peer_id -> bool
var _candidate_buffers: Dictionary = {} # peer_id -> Array
var _heartbeat_timer: float = 0.0

enum PendingAction { NONE, CREATE_ROOM, JOIN_ROOM }
var _pending_action: PendingAction = PendingAction.NONE
var _pending_code: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	# 1. Poll WebSocket
	if _ws:
		_ws.poll()
		var state = _ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if _pending_action != PendingAction.NONE:
				_execute_pending_action()
			
			# Heartbeat ส่ง ping ทุก 20 วินาที ป้องกัน Render ตัดการเชื่อมต่อ
			_heartbeat_timer += delta
			if _heartbeat_timer >= 20.0:
				_heartbeat_timer = 0.0
				_send_signaling({ "action": "ping" })
			
			while _ws.get_available_packet_count() > 0:
				var pkt = _ws.get_packet()
				var text = pkt.get_string_from_utf8()
				var json = JSON.parse_string(text)
				if json and json is Dictionary:
					_handle_signaling_message(json)
		elif state == WebSocketPeer.STATE_CLOSED:
			if is_online and not rtc_peer:
				status_message_updated.emit("ขาดการเชื่อมต่อกับ Signaling Server", true)
				connection_failed.emit()
	
	# 2. สำคัญมาก: Poll ทุก WebRTCPeerConnection เพื่อแลกเปลี่ยน ICE Candidate และประมวลผลเน็ตเวิร์ก
	for pid in _peer_connections:
		var conn: WebRTCPeerConnection = _peer_connections[pid]
		if conn:
			conn.poll()

func _execute_pending_action() -> void:
	if _pending_action == PendingAction.CREATE_ROOM:
		_send_signaling({
			"action": "create_room",
			"name": my_name
		})
	elif _pending_action == PendingAction.JOIN_ROOM:
		_send_signaling({
			"action": "join_room",
			"room_code": _pending_code,
			"name": my_name
		})
	_pending_action = PendingAction.NONE

# --- Online Room Code System (WebRTC) ---

## ใครก็สามารถสร้างห้องได้ (ได้รหัสห้อง 4 หลักแชร์ให้เพื่อน)
func create_room_online(player_name: String) -> void:
	close_connection()
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Host"
	my_peer_id = 1
	
	status_message_updated.emit("กำลังเชื่อมต่อเซิร์ฟเวอร์จับคู่ห้อง...", false)
	_pending_action = PendingAction.CREATE_ROOM
	_connect_to_signaling()

## เข้าร่วมห้องด้วยรหัสห้อง (Room Code)
func join_room_online(room_code: String, player_name: String) -> void:
	close_connection()
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
	
	_pending_code = room_code.strip_edges().to_upper()
	if _pending_code.is_empty():
		status_message_updated.emit("กรุณากรอกรหัสห้อง", true)
		return
	
	status_message_updated.emit("กำลังค้นหาห้องรหัส %s..." % _pending_code, false)
	_pending_action = PendingAction.JOIN_ROOM
	_connect_to_signaling()

func _connect_to_signaling() -> void:
	if _ws:
		_ws.close()
	_ws = WebSocketPeer.new()
	var err = _ws.connect_to_url(signaling_server_url)
	if err != OK:
		status_message_updated.emit("ไม่สามารถเชื่อมต่อไปยัง Signaling Server (%s)" % signaling_server_url, true)
		connection_failed.emit()

func _send_signaling(data: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(data))

# --- Signaling Protocol Handler ---

func _handle_signaling_message(data: Dictionary) -> void:
	var action = data.get("action", "")
	
	match action:
		"pong":
			return
		"game_started":
			print("[NetworkManager] Received game_started from Signaling Server!")
			start_game()
		"room_created":
			current_room_code = data.get("room_code", "")
			my_peer_id = 1
			is_online = true
			
			rtc_peer = WebRTCMultiplayerPeer.new()
			var err = rtc_peer.create_server()
			if err != OK:
				status_message_updated.emit("เกิดข้อผิดพลาดในการเริ่ม WebRTC Server", true)
				return
			
			multiplayer.multiplayer_peer = rtc_peer
			peer = rtc_peer
			
			players.clear()
			players[1] = {
				"name": my_name,
				"id": 1,
				"is_host": true
			}
			
			status_message_updated.emit("สร้างห้องสำเร็จ! รหัสห้อง: %s" % current_room_code, false)
			room_created.emit(current_room_code)
			player_list_updated.emit()

		"joined_room":
			current_room_code = data.get("room_code", "")
			my_peer_id = data.get("peer_id", 2)
			is_online = true
			
			rtc_peer = WebRTCMultiplayerPeer.new()
			var err = rtc_peer.create_client(my_peer_id)
			if err != OK:
				status_message_updated.emit("เกิดข้อผิดพลาดในการเริ่ม WebRTC Client", true)
				return
			
			multiplayer.multiplayer_peer = rtc_peer
			peer = rtc_peer
			
			players.clear()
			players[my_peer_id] = {
				"name": my_name,
				"id": my_peer_id,
				"is_host": false
			}
			
			status_message_updated.emit("เข้าร่วมห้อง %s สำเร็จ! กำลังเชื่อมต่อกับ Host..." % current_room_code, false)
			room_joined.emit(current_room_code)
			player_list_updated.emit()

		"join_failed":
			var err_msg = data.get("error", "ไม่สามารถเข้าร่วมห้องได้")
			status_message_updated.emit(err_msg, true)
			connection_failed.emit()

		"peer_joined":
			var joiner_id: int = data.get("peer_id", 2)
			var joiner_name: String = data.get("name", "Player")
			print("[NetworkManager] Peer joined room: ", joiner_id, " (", joiner_name, ")")
			if multiplayer.is_server():
				_create_peer_connection(joiner_id, true)

		"offer":
			var sender_id: int = data.get("sender", 1)
			var sdp: String = data.get("sdp", "")
			_handle_remote_offer(sender_id, sdp)

		"answer":
			var sender_id: int = data.get("sender", 1)
			var sdp: String = data.get("sdp", "")
			_handle_remote_answer(sender_id, sdp)

		"candidate":
			var sender_id: int = data.get("sender", 1)
			var media: String = data.get("media", "")
			var index: int = data.get("index", 0)
			var c_name: String = data.get("name", "")
			_handle_remote_candidate(sender_id, media, index, c_name)

		"player_list":
			var p_list: Array = data.get("players", [])
			players.clear()
			for item in p_list:
				var pid: int = item.get("id", 1)
				players[pid] = {
					"name": item.get("name", "Player"),
					"id": pid,
					"is_host": item.get("is_host", false)
				}
			player_list_updated.emit()

		"peer_left":
			var left_id: int = data.get("peer_id", 0)
			_remove_peer_connection(left_id)

		"host_disconnected":
			var msg: String = data.get("message", "Host ได้ปิดห้องแล้ว")
			close_connection()
			status_message_updated.emit(msg, true)
			server_disconnected.emit()

# --- WebRTC Handshake & Peer Management ---

func _create_peer_connection(target_peer_id: int, is_offerer: bool) -> WebRTCPeerConnection:
	if _peer_connections.has(target_peer_id):
		return _peer_connections[target_peer_id]
	
	var conn = WebRTCPeerConnection.new()
	conn.initialize({ "iceServers": ICE_SERVERS })
	
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		_send_signaling({
			"action": type,
			"target": target_peer_id,
			"sdp": sdp
		})
	)
	
	conn.ice_candidate_created.connect(func(media: String, index: int, c_name: String):
		_send_signaling({
			"action": "candidate",
			"target": target_peer_id,
			"media": media,
			"index": index,
			"name": c_name
		})
	)
	
	if rtc_peer:
		rtc_peer.add_peer(conn, target_peer_id)
		
	_peer_connections[target_peer_id] = conn
	_remote_desc_set[target_peer_id] = false
	_candidate_buffers[target_peer_id] = []
	
	if is_offerer:
		conn.create_offer()
		
	return conn

func _handle_remote_offer(sender_id: int, sdp: String) -> void:
	var conn = _create_peer_connection(sender_id, false)
	conn.set_remote_description("offer", sdp)
	_remote_desc_set[sender_id] = true
	_flush_candidate_buffer(sender_id)
	conn.create_answer()

func _handle_remote_answer(sender_id: int, sdp: String) -> void:
	if _peer_connections.has(sender_id):
		var conn: WebRTCPeerConnection = _peer_connections[sender_id]
		conn.set_remote_description("answer", sdp)
		_remote_desc_set[sender_id] = true
		_flush_candidate_buffer(sender_id)

func _handle_remote_candidate(sender_id: int, media: String, index: int, c_name: String) -> void:
	if _peer_connections.has(sender_id):
		var conn: WebRTCPeerConnection = _peer_connections[sender_id]
		if _remote_desc_set.get(sender_id, false):
			conn.add_ice_candidate(media, index, c_name)
		else:
			if not _candidate_buffers.has(sender_id):
				_candidate_buffers[sender_id] = []
			_candidate_buffers[sender_id].append({ "media": media, "index": index, "name": c_name })

func _flush_candidate_buffer(sender_id: int) -> void:
	if _peer_connections.has(sender_id) and _candidate_buffers.has(sender_id):
		var conn: WebRTCPeerConnection = _peer_connections[sender_id]
		for c in _candidate_buffers[sender_id]:
			conn.add_ice_candidate(c["media"], c["index"], c["name"])
		_candidate_buffers[sender_id].clear()

func _remove_peer_connection(peer_id: int) -> void:
	if _peer_connections.has(peer_id):
		var conn: WebRTCPeerConnection = _peer_connections[peer_id]
		conn.close()
		_peer_connections.erase(peer_id)
	_remote_desc_set.erase(peer_id)
	_candidate_buffers.erase(peer_id)
	if rtc_peer and rtc_peer.has_peer(peer_id):
		rtc_peer.remove_peer(peer_id)

# --- Single Player & Classic Offline Fallback ---

func start_singleplayer(player_name: String = "Player") -> void:
	close_connection()
	is_online = false
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
	my_peer_id = 1
	players.clear()
	players[1] = {
		"name": my_name,
		"id": 1,
		"is_host": true
	}
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

func close_connection() -> void:
	if _ws:
		_ws.close()
		_ws = null
	
	for pid in _peer_connections:
		var conn: WebRTCPeerConnection = _peer_connections[pid]
		conn.close()
	_peer_connections.clear()
	_remote_desc_set.clear()
	_candidate_buffers.clear()
	
	if rtc_peer:
		rtc_peer.close()
		rtc_peer = null
	if peer:
		peer.close()
		peer = null
		
	multiplayer.multiplayer_peer = null
	is_online = false
	current_room_code = ""
	players.clear()
	_pending_action = PendingAction.NONE

func request_start_game() -> void:
	if not multiplayer.is_server():
		return
	# ส่งสัญญาณเริ่มเกมผ่านทั้ง Signaling Server และ Multiplayer RPC เพื่อความแน่นอน 100%
	_send_signaling({ "action": "start_game" })
	start_game.rpc()

@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	if get_tree().current_scene and get_tree().current_scene.scene_file_path == "res://Scenes/main.tscn":
		return
	status_message_updated.emit("กำลังโหลดฉากเกม...", false)
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

@rpc("any_peer", "reliable")
func _register_player(new_player_name: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = {
		"name": new_player_name,
		"id": sender_id,
		"is_host": false
	}
	_sync_player_list.rpc(players)
	player_connected.emit(sender_id, players[sender_id])
	player_list_updated.emit()

@rpc("authority", "reliable")
func _sync_player_list(all_players: Dictionary) -> void:
	players = all_players
	player_list_updated.emit()

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected in Godot Multiplayer: ", id)
	status_message_updated.emit("ผู้เล่น ID: %d เชื่อมต่อเข้ามาแล้ว!" % id, false)
	if not multiplayer.is_server():
		_register_player.rpc_id(1, my_name)

func _on_peer_disconnected(id: int) -> void:
	_remove_peer_connection(id)
	if players.has(id):
		var p_name = players[id]["name"]
		players.erase(id)
		player_disconnected.emit(id)
		player_list_updated.emit()
		status_message_updated.emit("ผู้เล่น %s ออกจากเกม" % p_name, false)
		if multiplayer.is_server():
			_sync_player_list.rpc(players)

func _on_connected_to_server() -> void:
	my_peer_id = multiplayer.get_unique_id()
	status_message_updated.emit("เชื่อมต่อกับเซิร์ฟเวอร์สำเร็จ!", false)
	connection_succeeded.emit()
	_register_player.rpc_id(1, my_name)

func _on_connection_failed() -> void:
	close_connection()
	status_message_updated.emit("การเชื่อมต่อล้มเหลว", true)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	close_connection()
	status_message_updated.emit("ถูกตัดการเชื่อมต่อจากห้อง", true)
	server_disconnected.emit()
	if get_tree().current_scene and get_tree().current_scene.name != "start_scene":
		get_tree().change_scene_to_file("res://Scenes/start_scene.tscn")
