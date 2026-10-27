extends Node

## NetworkManager: ควบคุมระบบ Multiplayer ผ่าน ENet
## รองรับทั้ง Host (Server), Client (Join) และ Offline (Single Player)

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
# players: id -> { "name": String, "id": int }
var players: Dictionary = {}

var peer: ENetMultiplayerPeer = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## เริ่มต้นเป็น Host (Server)
func host_game(port: int, player_name: String, max_clients: int = MAX_PLAYERS) -> Error:
	close_connection()
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, max_clients)
	if error != OK:
		var err_msg = "สร้างห้องไม่สำเร็จ (Error code: %d)" % error
		status_message_updated.emit(err_msg, true)
		return error
	
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
	
	status_message_updated.emit("สร้างห้องสำเร็จที่พอร์ต %d" % port, false)
	player_list_updated.emit()
	return OK

## เข้าร่วมห้องในฐานะ Client
func join_game(ip: String, port: int, player_name: String) -> Error:
	close_connection()
	
	var target_ip = ip.strip_edges()
	if target_ip.is_empty():
		target_ip = DEFAULT_IP
		
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, port)
	if error != OK:
		var err_msg = "เชื่อมต่อไปยัง %s:%d ไม่สำเร็จ" % [target_ip, port]
		status_message_updated.emit(err_msg, true)
		return error
		
	multiplayer.multiplayer_peer = peer
	is_online = true
	my_name = player_name.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
		
	status_message_updated.emit("กำลังเชื่อมต่อไปยัง %s:%d..." % [target_ip, port], false)
	return OK

## เล่นคนเดียว (Single Player)
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
	# Server ส่งรายชื่อผู้เล่นล่าสุดให้กับทุกคน
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
	# ส่งชื่อเราไปลงทะเบียนที่ server
	_register_player.rpc_id(1, my_name)

func _on_connection_failed() -> void:
	close_connection()
	status_message_updated.emit("การเชื่อมต่อล้มเหลว ตรวจสอบ IP และ Port", true)
	connection_failed.emit()

func _on_server_disconnected() -> void:
	close_connection()
	status_message_updated.emit("ถูกตัดการเชื่อมต่อจากเซิร์ฟเวอร์", true)
	server_disconnected.emit()
	# หากอยู่ในหน้าเกม ให้กลับหน้า start_scene
	if get_tree().current_scene and get_tree().current_scene.name != "start_scene":
		get_tree().change_scene_to_file("res://Scenes/start_scene.tscn")
