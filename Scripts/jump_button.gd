extends Button
## JumpButton: ปุ่มกระโดดสำหรับมือถือ
## เมื่อกดจะตั้งค่า _touch_jump_requested = true บนตัวละครของผู้เล่น local

func _ready() -> void:
	button_down.connect(_on_button_down)

func _on_button_down() -> void:
	# 1. ค้นหา player จาก parent hierarchy โดยตรง (เนื่องจาก mobile ui อยู่ใต้ Player)
	var n: Node = self
	while n != null:
		if n is CharacterBody3D and "_touch_jump_requested" in n:
			if n.has_method("is_multiplayer_authority") and n.is_multiplayer_authority():
				n._touch_jump_requested = true
				return
		n = n.get_parent()

	# 2. fallback: หาจาก group "player"
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
			if "_touch_jump_requested" in p:
				p._touch_jump_requested = true
			return
	
	# fallback: หา CharacterBody3D ที่ใกล้ที่สุดใน tree
	var root = get_tree().current_scene
	if root == null:
		return
	_find_and_jump(root)

func _find_and_jump(node: Node) -> bool:
	if node is CharacterBody3D and "_touch_jump_requested" in node:
		if node.has_method("is_multiplayer_authority") and node.is_multiplayer_authority():
			node._touch_jump_requested = true
			return true
	for child in node.get_children():
		if _find_and_jump(child):
			return true
	return false
