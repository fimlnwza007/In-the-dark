extends Control

## StartMenu: จัดการ UI หน้าเริ่มเกม รองรับทั้งเล่นคนเดียวและระบบ Room Code (ทุกคนสร้างห้องได้)

@onready var main_menu_panel: Control = _get_node_safe("MainMenuPanel")
@onready var host_panel: Control = _get_node_safe("HostPanel")
@onready var join_panel: Control = _get_node_safe("JoinPanel")
@onready var lobby_panel: Control = _get_node_safe("LobbyPanel")

@onready var status_label: Label = _get_node_safe("StatusLabel")

# Host inputs
@onready var host_name_input: LineEdit = _get_node_safe("HostNameInput")
@onready var signaling_input: LineEdit = _get_node_safe("SignalingInput")

# Join inputs
@onready var join_name_input: LineEdit = _get_node_safe("JoinNameInput")
@onready var join_code_input: LineEdit = _get_node_safe("JoinCodeInput")

# Lobby items
@onready var room_code_label: Label = _get_node_safe("RoomCodeLabel")
@onready var lobby_status_label: Label = _get_node_safe("LobbyStatusLabel")
@onready var player_list: ItemList = _get_node_safe("PlayerList")
@onready var start_game_button: Button = _get_node_safe("StartGameBtn")

var _is_transitioning: bool = false

func _get_node_safe(node_name: String) -> Node:
	var n = get_node_or_null("%" + node_name)
	if n:
		return n
	return find_child(node_name, true, false)

func _ready() -> void:
	print("[StartMenu] _ready started")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# สุ่มชื่อเริ่มต้นให้ผู้เล่น
	var random_name = "Player_%03d" % (randi() % 1000)
	if host_name_input:
		host_name_input.text = random_name
	if join_name_input:
		join_name_input.text = random_name
	if signaling_input:
		signaling_input.text = NetworkManager.signaling_server_url
		
	# ผูกปุ่มกดทั้งหมดอย่างปลอดภัย
	_connect_buttons()
	
	# รองรับมือถือ: เชื่อม LineEdit ทุกช่องให้เปิด virtual keyboard เมื่อกด
	_setup_mobile_inputs()
	
	# เชื่อมต่อ Signals จาก NetworkManager
	if not NetworkManager.room_created.is_connected(_on_room_created):
		NetworkManager.room_created.connect(_on_room_created)
	if not NetworkManager.room_joined.is_connected(_on_room_joined):
		NetworkManager.room_joined.connect(_on_room_joined)
	if not NetworkManager.player_list_updated.is_connected(_update_lobby_player_list):
		NetworkManager.player_list_updated.connect(_update_lobby_player_list)
	if not NetworkManager.status_message_updated.is_connected(_on_status_updated):
		NetworkManager.status_message_updated.connect(_on_status_updated)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	show_panel(main_menu_panel)
	set_status("", false)
	print("[StartMenu] _ready finished")

func _connect_buttons() -> void:
	var button_bindings = [
		["SinglePlayerBtn", Callable(self, "_on_single_player_btn_pressed")],
		["HostGameBtn", Callable(self, "_on_host_game_btn_pressed")],
		["JoinGameBtn", Callable(self, "_on_join_game_btn_pressed")],
		["QuitBtn", Callable(self, "_on_quit_btn_pressed")],
		["StartHostBtn", Callable(self, "_on_start_host_btn_pressed")],
		["BackFromHostBtn", Callable(self, "_on_back_to_menu_pressed")],
		["ConnectBtn", Callable(self, "_on_connect_btn_pressed")],
		["BackFromJoinBtn", Callable(self, "_on_back_to_menu_pressed")],
		["StartGameBtn", Callable(self, "_on_start_game_btn_pressed")],
		["LeaveLobbyBtn", Callable(self, "_on_leave_lobby_btn_pressed")]
	]
	
	for binding in button_bindings:
		var btn_name: String = binding[0]
		var cb: Callable = binding[1]
		var btn = _get_node_safe(btn_name) as Button
		if btn:
			if not btn.pressed.is_connected(cb):
				btn.pressed.connect(cb)
			print("[StartMenu] Button bound: ", btn_name)

## รองรับมือถือ: ให้ LineEdit ทุกช่องเปิด virtual keyboard เมื่อกด
func _setup_mobile_inputs() -> void:
	var inputs: Array[LineEdit] = []
	if host_name_input:
		inputs.append(host_name_input)
	if signaling_input:
		inputs.append(signaling_input)
	if join_name_input:
		inputs.append(join_name_input)
	if join_code_input:
		inputs.append(join_code_input)
	
	for le in inputs:
		# เปิด virtual keyboard type ให้เหมาะสม
		le.virtual_keyboard_enabled = true
		# เมื่อกด LineEdit บนมือถือ ให้ grab_focus และ show keyboard
		if not le.gui_input.is_connected(_on_line_edit_gui_input.bind(le)):
			le.gui_input.connect(_on_line_edit_gui_input.bind(le))

func _on_line_edit_gui_input(event: InputEvent, le: LineEdit) -> void:
	if event is InputEventScreenTouch and event.pressed:
		le.grab_focus()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		le.grab_focus()

func show_panel(target: Control) -> void:
	if main_menu_panel:
		main_menu_panel.visible = (target == main_menu_panel)
	if host_panel:
		host_panel.visible = (target == host_panel)
	if join_panel:
		join_panel.visible = (target == join_panel)
	if lobby_panel:
		lobby_panel.visible = (target == lobby_panel)

func set_status(text: String, is_error: bool = false) -> void:
	if not status_label:
		return
	status_label.text = text
	status_label.modulate = Color(1.0, 0.4, 0.4) if is_error else Color(0.65, 0.9, 0.65)

# --- Button Handlers ---

func _on_single_player_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	//if _is_transitioning:
		//return
	//_is_transitioning = true
	//set_status("กำลังเข้าสู่เกม...", false)
	//var p_name = host_name_input.text if (host_name_input and not host_name_input.text.is_empty()) else "Player"
	//NetworkManager.start_singleplayer(p_name)

func _on_host_game_btn_pressed() -> void:
	set_status("")
	show_panel(host_panel)

func _on_join_game_btn_pressed() -> void:
	set_status("")
	show_panel(join_panel)

func _on_quit_btn_pressed() -> void:
	get_tree().quit()

func _on_back_to_menu_pressed() -> void:
	NetworkManager.close_connection()
	set_status("")
	show_panel(main_menu_panel)

func _on_start_host_btn_pressed() -> void:
	print("[StartMenu] Create Room (Host) clicked")
	var name_text = host_name_input.text.strip_edges() if host_name_input else "Host"
	if signaling_input and not signaling_input.text.strip_edges().is_empty():
		NetworkManager.signaling_server_url = signaling_input.text.strip_edges()
	
	set_status("กำลังขอสร้างห้อง...", false)
	NetworkManager.create_room_online(name_text)

func _on_connect_btn_pressed() -> void:
	print("[StartMenu] Join Room clicked")
	var name_text = join_name_input.text.strip_edges() if join_name_input else "Player"
	var code_text = join_code_input.text.strip_edges().to_upper() if join_code_input else ""
	
	if code_text.is_empty():
		set_status("กรุณากรอกรหัสห้อง (Room Code)", true)
		return
		
	set_status("กำลังเข้าร่วมห้อง...", false)
	NetworkManager.join_room_online(code_text, name_text)

func _on_start_game_btn_pressed() -> void:
	print("[StartMenu] Start Game (Host) clicked")
	if multiplayer.is_server():
		NetworkManager.request_start_game()

func _on_leave_lobby_btn_pressed() -> void:
	print("[StartMenu] Leave Lobby clicked")
	NetworkManager.close_connection()
	show_panel(main_menu_panel)
	set_status("ออกจากห้องแล้ว", false)

# --- Network Callbacks ---

func _on_room_created(code: String) -> void:
	print("[StartMenu] Room Created successfully: ", code)
	show_panel(lobby_panel)
	if room_code_label:
		room_code_label.text = code
	if start_game_button:
		start_game_button.visible = true
	if lobby_status_label:
		lobby_status_label.text = "คุณเป็น Host ของห้อง %s - รอเพื่อนเข้าร่วม..." % code
	_update_lobby_player_list()

func _on_room_joined(code: String) -> void:
	print("[StartMenu] Joined Room successfully: ", code)
	show_panel(lobby_panel)
	if room_code_label:
		room_code_label.text = code
	if start_game_button:
		start_game_button.visible = false # เฉพาะ Host เท่านั้นที่เห็นปุ่มเริ่มเกม
	if lobby_status_label:
		lobby_status_label.text = "เข้าร่วมห้อง %s แล้ว! รอ Host เริ่มเกม..." % code
	_update_lobby_player_list()

func _on_status_updated(message: String, is_error: bool) -> void:
	set_status(message, is_error)

func _on_connection_failed() -> void:
	print("[StartMenu] Connection failed!")
	show_panel(join_panel)

func _on_server_disconnected() -> void:
	print("[StartMenu] Server disconnected!")
	show_panel(main_menu_panel)

func _update_lobby_player_list() -> void:
	if not is_instance_valid(player_list):
		return
	player_list.clear()
	for id in NetworkManager.players:
		var p_data = NetworkManager.players[id]
		var p_name = p_data.get("name", "Player")
		var suffix = ""
		if id == 1:
			suffix = " [Host]"
		if id == NetworkManager.my_peer_id:
			suffix += " (คุณ)"
		player_list.add_item("%s (ID: %d)%s" % [p_name, id, suffix])
