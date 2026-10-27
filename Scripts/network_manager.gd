extends Node

## NetworkManager: ควบคุมระบบ Multiplayer
## รองรับทั้ง WebSocket (สำหรับ Web/Mobile/PC cross-play) และ ENet (สำหรับ Desktop/Mobile LAN)

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal player_list_updated
signal status_message_updated(message: String, is_error: bool)

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 8

var is_online: bool = false
var my_name: String = "Player"
var my_peer_id: int = 1
# players: id -> { "name": String, "id": int, "is_host": bool }
var players: Dictionary = {}

var peer: MultiplayerPeer = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## เริ่มต้นเป็น Host (Server)
func host_game(port: int, player_name: String, max_clients: int = MAX_PLAYERS) -> Error:
	close_connection()
	
	# Web browser ไม่สามารถเปิดพอร์ตเพื่อเป็น Server ได้ (ข้อจำกัดด้านความปลอดภัยของ Web)
	if OS.has_feature("web"):
		var err_msg = "⚠️ เบราว์เซอร์ไม่สามารถเป็น Host สร้างห้องได้เนื่องจากข้อจำกัดความปลอดภัยของ Web\nกรุณาสร้างห้องจากเกมบนคอมพิวเตอร์ (PC) แล้วใช้ Web เข้าเล่นผ่าน 'เข้าร่วมห้อง (Join)' ครับ"
		status_message_updated.emit(err_msg, true)
		return ERR_UNAVAILABLE
	
	# บน Desktop/PC: ใช้ WebSocketServer เพื่อให้ทั้ง Web (มือถือ/คอม) และตัวเกมปกติเล่นร่วมกันได้
	var ws_peer = WebSocketMultiplayerPeer.new()
	var error = ws_peer.create_server(port)
	if error == OK:
		peer = ws_peer
	else:
		# ถ้า WebSocket ไม่ผ่าน ลองใช้ ENet สำรอง
		var enet_peer = ENetMultiplayerPeer.new()
		error = enet_peer.create_server(port, max_clients)
		if error != OK:
			var err_msg = "สร้างห้องไม่สำเร็จ (Error code: %d)\nพอร์ต %d อาจถูกใช้งานอยู่ กรุณาลองเปลี่ยนพอร์ตอื่น" % [error, port]
			status_message_updated.emit(err_msg, true)
			return error
		peer = enet_peer
	
	multiplayer.multiplayer_peer = peer
	is_online = true
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Host"
	my_peer_id = 1
	
	players.clear()
	players[1] = {
		"name": my_name,
		"id": 1,
		"is_host": true
	}
	
	status_message_updated.emit("สร้างห้องสำเร็จที่พอร์ต %d (รอผู้เล่นอื่นเข้าร่วม...)" % port, false)
	player_list_updated.emit()
	return OK

## เข้าร่วมห้องในฐานะ Client
func join_game(ip: String, port: int, player_name: String) -> Error:
	close_connection()
	
	var target_ip = ip.strip_edges()
	if target_ip.is_empty():
		target_ip = DEFAULT_IP
	
	var url = target_ip
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + target_ip + ":" + str(port)
		
	# บน Web ต้องเชื่อมต่อผ่าน WebSocket เท่านั้น (Web ไม่รองรับ UDP/ENet)
	if OS.has_feature("web"):
		var ws_peer = WebSocketMultiplayerPeer.new()
		var error = ws_peer.create_client(url)
		if error != OK:
			var err_msg = "ไม่สามารถเชื่อมต่อ WebSocket ไปที่ %s ได้ (Error: %d)" % [url, error]
			status_message_updated.emit(err_msg, true)
			return error
		peer = ws_peer
	else:
		# บน Desktop/Mobile Native ลองเชื่อมต่อ WebSocket ก่อน
		var ws_peer = WebSocketMultiplayerPeer.new()
		var error = ws_peer.create_client(url)
		if error == OK:
			peer = ws_peer
		else:
			# ถ้าไม่ได้ ให้ลอง ENet สำรอง
			var enet_peer = ENetMultiplayerPeer.new()
			error = enet_peer.create_client(target_ip, port)
			if error != OK:
				var err_msg = "เชื่อมต่อไปยัง %s:%d ไม่สำเร็จ (Error code: %d)" % [target_ip, port, error]
				status_message_updated.emit(err_msg, true)
				return error
			peer = enet_peer
		
	multiplayer.multiplayer_peer = peer
	is_online = true
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
		
	status_message_updated.emit("กำลังเชื่อมต่อไปยัง %s..." % url, false)
	return OK

## เล่นคนเดียว (Single Player - ออฟไลน์สมบูรณ์)
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

## ปิดการเชื่อมต่อและคืนค่าเริ่มต้น
func close_connection() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_online = false
	players.clear()

## Host กดสั่งเริ่มเกม
func request_start_game() -> void:
	if not multiplayer.is_server():
		return
	start_game.rpc()

## RPC สั่งโหลดแมพและเริ่มเล่นเกมพร้อมกันทุกคน
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	status_message_updated.emit("กำลังโหลดฉากเกม...", false)
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

## ลงทะเบียนผู้เล่นใหม่ไปยัง Server
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

## อัปเดตรายชื่อผู้เล่นจาก Server มายัง Client
@rpc("authority", "reliable")
func _sync_player_list(all_players: Dictionary) -> void:
	players = all_players
	player_list_updated.emit()

# --- Signal Callbacks ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		status_message_updated.emit("ผู้เล่น ID: %d เชื่อมต่อเข้ามา" % id, false)

func _on_peer_disconnected(id: int) -> void:
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
	status_message_updated.emit("การเชื่อมต่อล้มเหลว ตรวจสอบ IP และ Port (หรือเครื่อง Host ยังไม่ได้เปิด)", true)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	close_connection()
	status_message_updated.emit("ถูกตัดการเชื่อมต่อจากเซิร์ฟเวอร์", true)
	server_disconnected.emit()
	if get_tree().current_scene and get_tree().current_scene.name != "start_scene":
		get_tree().change_scene_to_file("res://Scenes/start_scene.tscn")
