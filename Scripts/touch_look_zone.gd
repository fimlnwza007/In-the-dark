class_name TouchLookZone
extends Control
## โซนสัมผัสหน้าจอฝั่งขวาสำหรับหมุนกล้อง
## รองรับ Multi-touch อิสระ ไม่ตีกับ Joystick หรือปุ่มอื่น

signal look_dragged(relative: Vector2)

@export var target_player: CharacterBody3D = null
@export_range(0.01, 2.0, 0.01) var sensitivity: float = 0.2
@export var invert_x: bool = false
@export var invert_y: bool = false

## เก็บ ID ของนิ้วที่กำลังแตะควบคุมโซนนี้ (-1 คือไม่มีนิ้วแตะ)
var _active_touch_index: int = -1
var _last_touch_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# ถ้าไม่ได้ระบุ target_player ให้ลองหาจาก parent hierarchy หรือใน scene
	if target_player == null:
		var node: Node = get_parent()
		while node != null:
			if node is CharacterBody3D and node.has_method("rotate_look"):
				target_player = node
				break
			node = node.get_parent()

	if target_player == null:
		var player_in_tree = get_tree().get_first_node_in_group("player")
		if player_in_tree is CharacterBody3D:
			target_player = player_in_tree

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# แตะลงมา: ตรวจสอบว่ายังไม่มีนิ้วในโซนนี้ และตำแหน่งแตะอยู่ในโซนฝั่งขวา
		if _active_touch_index == -1 and get_global_rect().has_point(event.position):
			_active_touch_index = event.index
			_last_touch_pos = event.position
			get_viewport().set_input_as_handled()
	else:
		# ปล่อยนิ้ว: เฉพาะนิ้วที่ควบคุมโซนนี้เท่านั้น
		if event.index == _active_touch_index:
			_active_touch_index = -1
			get_viewport().set_input_as_handled()

func _handle_drag(event: InputEventScreenDrag) -> void:
	# ป้องกัน Multi-touch: ดักรับเฉพาะนิ้วที่เริ่มต้นแตะจากโซนนี้เท่านั้น
	if event.index == _active_touch_index:
		# คำนวณ delta เองจากตำแหน่งนิ้วนี้โดยเฉพาะ ป้องกันบั๊ก multi-touch jump / spike ใน Godot
		var delta_pos := event.position - _last_touch_pos
		_last_touch_pos = event.position

		# Spike Filter: ป้องกันกรณีค่าพิกัดกระโดดข้ามจอผิดปกติใน 1 เฟรม
		if delta_pos.length_squared() > 40000.0: # เกิน 200px ใน 1 เฟรม
			return

		var rel := delta_pos
		if invert_x:
			rel.x = -rel.x
		if invert_y:
			rel.y = -rel.y

		look_dragged.emit(rel)

		if target_player and target_player.has_method("rotate_look"):
			target_player.rotate_look(rel, sensitivity)
		elif target_player:
			target_player.rotate_y(-deg_to_rad(rel.x * sensitivity))
			var head = target_player.get_node_or_null("Head")
			if head:
				head.rotation.x = clampf(
					head.rotation.x - deg_to_rad(rel.y * sensitivity),
					-deg_to_rad(85.0), deg_to_rad(85.0)
				)

		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# หากแอพหลุด focus หรือพับหน้าจอ รีเซ็ต touch index เพื่อป้องกันนิ้วค้าง
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_active_touch_index = -1
