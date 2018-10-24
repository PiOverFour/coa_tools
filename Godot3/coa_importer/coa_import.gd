tool
extends EditorImportPlugin


func get_importer_name():
	return "import.coa"

func get_visible_name():
	return "Cutout Animation Tools"

func get_recognized_extensions():
	return ["json"]

func get_save_extension():
	return "scn"

func get_resource_type():
	return "PackedScene"

func get_preset_count():
	return 0

func get_preset_name(preset):
	return "Unknown"

# Have to return at least one option?!
func get_import_options(preset):
	return [
			{
				"name": "option",
				"default_value": true
			},
	]

func get_option_visibility(option, options):
	return false


func import(source_file, save_path, options, r_platform_variants, r_gen_files):

	var json = File.new()
	var json_data

	if json.file_exists(source_file):

		json.open(source_file, File.READ)
		json_data = JSON.parse(json.get_as_text()).result
		json.close()

	var dir = Directory.new()
	dir.open("res://")

	var scene = Node2D.new()
	scene.set_name(json_data["name"])

	create_nodes(source_file, json_data["nodes"], scene, scene, false)

	### import animations and log
	if "animations" in json_data:
		import_animations(json_data["animations"], scene)

	var packed_scene = PackedScene.new()
	packed_scene.pack(scene)
	return ResourceSaver.save("%s.%s" % [save_path, get_save_extension()], packed_scene)


### recursive function that looks up if a node has BONE nodes as children
func has_bone_child(node):
	if "children" in node:
		for item in node["children"]:
			if item["type"] == "BONE":
				return true
			if "children" in item:
				has_bone_child(item)
	return false

### function to import animations -> this will create an AnimationPlayer Node and generate all animations with its tracks and values
func import_animations(animations, root):
	var anim_player = AnimationPlayer.new()
	root.add_child(anim_player)
	anim_player.set_owner(root)
	anim_player.set_name("AnimationPlayer")

	for anim in animations:
		anim_player.clear_caches()
		var anim_data = Animation.new()
		anim_data.set_loop(true)
		anim_data.set_length(anim["length"])
		for key in anim["keyframes"]:
			var track = anim["keyframes"][key]

			# Convert to Godot 3
			var channel = key.split(":")[-1]
			match channel:
				"transform/pos":
					key = key.left(key.length() - channel.length()) + "position"
				"transform/rot":
					key = key.left(key.length() - channel.length()) + "rotation_degrees"
				"transform/scale":
					key = key.left(key.length() - channel.length()) + "scale"

				"z/z":
					key = key.left(key.length() - channel.length()) + "z_index"

			var idx = anim_data.add_track(Animation.TYPE_VALUE)
			anim_data.track_set_path(idx,key)
			for time in track:
				var value = track[time]["value"]
				if typeof(value) == TYPE_ARRAY:
					if key.find("pos") != -1:
						anim_data.track_insert_key(idx,float(time),Vector2(value[0],value[1]))
					elif key.find("scale") != -1:
						anim_data.track_insert_key(idx,float(time),Vector2(value[0],value[1]))
					elif key.find("modulate") != -1:
						anim_data.track_insert_key(idx,float(time),Color(value[0],value[1],value[2],1.0))
				elif typeof(value) == TYPE_REAL:
					if key.find("rot") != -1:
						anim_data.track_insert_key(idx,float(time),-rad2deg(value))
					else:
						anim_data.track_insert_key(idx,float(time),value)

				if key.find(":frame") != -1 or key.find(":z/z") != -1:
					anim_data.track_set_interpolation_type(idx, Animation.INTERPOLATION_NEAREST)
				else:
					anim_data.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
		anim_player.add_animation(anim["name"],anim_data)
		anim_player.set_meta(anim["name"],true)
		anim_player.clear_caches()

### this function generates the complete node structure that is stored in a json file. Generates SPRITE and BONE nodes.
func create_nodes(source_file, nodes, root, parent, copy_images=true,i=0):
	for node in nodes:
		var new_node
		var offset = Vector2(0,0)
		if "offset" in node:
			offset = Vector2(node["offset"][0],node["offset"][1])
		if node["type"] == "BONE":
			new_node = Node2D.new()
			new_node.set_meta("imported_from_blender",true)
			new_node.set_name(node["name"])
			new_node.set_position(Vector2(node["position"][0],node["position"][1]))
			new_node.set_rotation(node["rotation"])
			new_node.set_scale(Vector2(node["scale"][0],node["scale"][1]))
			new_node.z_index = node["z"]
			parent.add_child(new_node)
			new_node.set_owner(root)

			### handle bone drawing
			if new_node.get_parent() != null and node["bone_connected"]:
				new_node.set_meta("_edit_bone_",true)
			if !(has_bone_child(node)) or node["draw_bone"]:
				var draw_bone = Node2D.new()
				draw_bone.set_meta("_edit_bone_",true)
				draw_bone.set_name(str(node["name"],"_tail"))
				draw_bone.set_position(Vector2(node["position_tip"][0],-node["position_tip"][1]))
				draw_bone.hide()

				new_node.add_child(draw_bone)
				draw_bone.set_owner(root)

		if node["type"] == "SPRITE":
			new_node = Sprite.new()
			var sprite_path = source_file.get_base_dir().plus_file(node["resource_path"])

			### set sprite texture
			new_node.set_texture(load(sprite_path))

			new_node.set_meta("imported_from_blender",true)
			new_node.set_name(node["name"])
			new_node.set_hframes(node["tiles_x"])
			new_node.set_vframes(node["tiles_y"])
			new_node.set_frame(node["frame_index"])
			new_node.set_centered(false)
			new_node.set_offset(Vector2(node["pivot_offset"][0],node["pivot_offset"][1]))
			new_node.set_position(Vector2(node["position"][0]+offset[0],node["position"][1]+offset[0]))
			new_node.set_rotation(node["rotation"])
			new_node.set_scale(Vector2(node["scale"][0],node["scale"][1]))
			new_node.z_index = node["z"]

			parent.add_child(new_node)
			new_node.set_owner(root)

		if "children" in node and node["children"].size() > 0:
			i+=1
			create_nodes(source_file, node["children"], root, new_node, copy_images,i)
