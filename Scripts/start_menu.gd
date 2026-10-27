extends Control

## StartMenu: จัดการ UI สำหรับหน้าเริ่มเกมและโหมด Multiplayer / Single Player

@onready var main_menu_panel: Control = _get_node_safe("MainMenuPanel")
@onready var host_panel: Control = _get_node_safe("HostPanel")
@onready var join_panel: Control = _get_node_safe("JoinPanel")
@onready var lobby_panel: Control = _get_node_safe("LobbyPanel")

@onready var status_label: Label = _get_node_safe("StatusLabel")

# Host inputs
@onready var host_name_input: LineEdit = _get_node_safe("HostNameInput")
@onready var host_port_input: LineEdit = _get_node_safe("HostPortInput")

# Join inputs
@onready var join_name_input: LineEdit = _get_node_safe("JoinNameInput")
@onready var join_ip_input: LineEdit = _get_node_safe("JoinIPInput")
@onready var join_port_input: LineEdit = _get_node_safe("JoinPortInput")

# Lobby items
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
	
	# ปรับ mouse mode ให้เห็น cursor และใช้งานคลิกได้ปกติ
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# สุ่มชื่อเริ่มต้นให้ผู้เล่น
	var random_name = "Player_%03d" % (randi() % 1000)
	if host_name_input:
		host_name_input.text = random_name
	if join_name_input:
		join_name_input.text = random_name
	if host_port_input:
		host_port_input.text = str(NetworkManager.DEFAULT_PORT)
	if join_port_input:
		join_port_input.text = str(NetworkManager.DEFAULT_PORT)
	if join_ip_input:
		join_ip_input.text = NetworkManager.DEFAULT_IP
	
	# ผูกปุ่มกดทั้งหมดอย่างปลอดภัย
	_connect_buttons()
	
	# เชื่อมต่อ Signals จาก NetworkManager
	if not NetworkManager.status_message_updated.is_connected(_on_status_updated):
		NetworkManager.status_message_updated.connect(_on_status_updated)
	if not NetworkManager.player_list_updated.is_connected(_update_lobby_player_list):
		NetworkManager.player_list_updated.connect(_update_lobby_player_list)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.connect(_on_server_disconnected)
	if not NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	
	show_panel(main_menu_panel)
	
	if OS.has_feature("web"):
		set_status("โหมดเว็บ (HTML5): แนะนำเล่น 'คนเดียว' หรือ 'เข้าร่วมห้อง' ที่เปิดบน PC", false)
	else:
		set_status("", false)
	print("[StartMenu] _ready finished")

## เชื่อมต่อสัญญาณ pressed ของปุ่มทั้งหมด รองรับทั้ง Mouse คลิก และ Touch บนหน้าจอ
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
		else:
			push_warning("[StartMenu] Button not found: " + btn_name)

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
	print("[StartMenu] Single Player button clicked!")
	if _is_transitioning:
		return
	_is_transitioning = true
	
	set_status("กำลังเข้าสู่เกม...", false)
	var p_name = host_name_input.text if (host_name_input and not host_name_input.text.is_empty()) else "Player"
	NetworkManager.start_singleplayer(p_name)

func _on_host_game_btn_pressed() -> void:
	print("[StartMenu] Host Game button clicked!")
	if OS.has_feature("web"):
		set_status("⚠️ บนเว็บบราวเซอร์ไม่สามารถเป็น Host ได้ ให้สร้างห้องบน PC แล้วใช้มือถือเข้าร่วม (Join) ครับ", true)
		return
	
	set_status("")
	show_panel(host_panel)

func _on_join_game_btn_pressed() -> void:
	print("[StartMenu] Join Game button clicked!")
	set_status("")
	show_panel(join_panel)

func _on_quit_btn_pressed() -> void:
	print("[StartMenu] Quit button clicked!")
	get_tree().quit()

func _on_back_to_menu_pressed() -> void:
	print("[StartMenu] Back to menu button clicked!")
	NetworkManager.close_connection()
	set_status("")
	show_panel(main_menu_panel)

func _on_start_host_btn_pressed() -> void:
	print("[StartMenu] Start Host button clicked!")
	var name_text = host_name_input.text.strip_edges() if host_name_input else "Host"
	var port_text = host_port_input.text.strip_edges() if host_port_input else "7777"
	var port = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	
	var err = NetworkManager.host_game(port, name_text)
	if err == OK:
		show_panel(lobby_panel)
		if start_game_button:
			start_game_button.visible = true
		if lobby_status_label:
			lobby_status_label.text = "คุณเป็น Host (พอร์ต %d) - กำลังรอผู้เล่น..." % port
		_update_lobby_player_list()

func _on_connect_btn_pressed() -> void:
	print("[StartMenu] Connect button clicked!")
	var name_text = join_name_input.text.strip_edges() if join_name_input else "Player"
	var ip_text = join_ip_input.text.strip_edges() if join_ip_input else "127.0.0.1"
	var port_text = join_port_input.text.strip_edges() if join_port_input else "7777"
	var port = port_text.to_int() if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	
	set_status("กำลังเชื่อมต่อ...", false)
	var err = NetworkManager.join_game(ip_text, port, name_text)
	if err == OK:
		show_panel(lobby_panel)
		if start_game_button:
			start_game_button.visible = false
		if lobby_status_label:
			lobby_status_label.text = "กำลังเชื่อมต่อไปยัง %s:%d..." % [ip_text, port]

func _on_start_game_btn_pressed() -> void:
	print("[StartMenu] Start Game (Host) button clicked!")
	if multiplayer.is_server():
		NetworkManager.request_start_game()

func _on_leave_lobby_btn_pressed() -> void:
	print("[StartMenu] Leave Lobby button clicked!")
	NetworkManager.close_connection()
	show_panel(main_menu_panel)
	set_status("ออกจากห้องแล้ว", false)

# --- Network Callbacks ---

func _on_status_updated(message: String, is_error: bool) -> void:
	set_status(message, is_error)

func _on_connection_succeeded() -> void:
	print("[StartMenu] Connected to server successfully!")
	if lobby_status_label:
		lobby_status_label.text = "เชื่อมต่อสำเร็จแล้ว! รอ Host เริ่มเกม..."
	_update_lobby_player_list()

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
