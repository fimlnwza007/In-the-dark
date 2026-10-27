extends Node3D

## main.gd: ควบคุมการ Spawn ผู้เล่นในโหมด Single Player และ Multiplayer

const PLAYER_SCENE: PackedScene = preload("res://Player/Player.tscn")
const DEFAULT_SPAWN_POS: Vector3 = Vector3(-291.8, 28.2, 251.5)

@onready var players_container: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	# ตั้งค่า MultiplayerSpawner
	spawner.spawn_function = _custom_spawn_player
	
	if NetworkManager and NetworkManager.is_online:
		# ถ้าเป็นโหมด Online
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		
		# เฉพาะ Server/Host เท่านั้นที่เป็นผู้สั่ง Spawn ผ่าน MultiplayerSpawner
		if multiplayer.is_server():
			for peer_id in NetworkManager.players:
				_spawn_player_for_peer(peer_id)
				
			# รอรับผู้เล่นใหม่ที่อาจเข้ามาภายหลัง
			NetworkManager.player_connected.connect(_on_player_connected)
	else:
		# โหมดเล่นคนเดียว (Offline / Single Player)
		var local_player = PLAYER_SCENE.instantiate()
		local_player.name = "1"
		local_player.position = DEFAULT_SPAWN_POS
		players_container.add_child(local_player)
		if local_player.has_method("setup_multiplayer"):
			var p_name = NetworkManager.my_name if NetworkManager else "Player"
			local_player.setup_multiplayer(1, p_name)

## ฟังก์ชันช่วยให้ Server ทำการ spawn ผู้เล่น
func _spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_data = {
		"id": peer_id,
		"name": NetworkManager.players.get(peer_id, {}).get("name", "Player %d" % peer_id)
	}
	spawner.spawn(player_data)

## Custom spawn function สำหรับ MultiplayerSpawner
func _custom_spawn_player(data: Variant) -> Node:
	var peer_id: int = data.get("id", 1)
	var p_name: String = data.get("name", "Player")
	
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	
	# สุ่มตำแหน่งเกิดเล็กน้อยเพื่อไม่ให้ผู้เล่นยืนทับกันเป๊ะๆ
	var offset_x = (randf() - 0.5) * 6.0
	var offset_z = (randf() - 0.5) * 6.0
	player.position = DEFAULT_SPAWN_POS + Vector3(offset_x, 0.0, offset_z)
	
	# ตั้งค่า authority และข้อมูลผู้เล่น
	if player.has_method("setup_multiplayer"):
		player.setup_multiplayer(peer_id, p_name)
		
	return player

func _on_player_connected(peer_id: int, _player_info: Dictionary) -> void:
	if multiplayer.is_server():
		_spawn_player_for_peer(peer_id)

func _on_player_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		var node = players_container.get_node_or_null(str(peer_id))
		if is_instance_valid(node):
			node.queue_free()
