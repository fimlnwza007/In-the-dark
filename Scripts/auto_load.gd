extends Node

func _ready() -> void:
	if OS.get_name() in ["Android", "iOS"]:
		_apply_mobile_settings()

func _apply_mobile_settings() -> void:
	# ลด shadow distance
	RenderingServer.directional_shadow_atlas_set_size(1024, true)
	
	# ปิด glow
	var env = get_viewport().find_world_3d().environment
	if env:
		env.glow_enabled = false
		env.volumetric_fog_enabled = false
		env.directional_shadow_max_distance = 60.0
	
	# ปรับ terrain view distance
	var terrain = get_node_or_null("/root/main/ChunkTerrain")
	if terrain and terrain.has_method("set"):
		terrain.view_distance = 100.0
	
	print("[MobileQuality] Applied mobile optimizations")
