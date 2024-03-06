@tool
extends CodeEdit

const Page = preload("wiki_tab.gd").Page

var page: Page

var is_dirty: bool = false

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return "type" in data and data.type in ["files", "nodes", "tree_item"]

func _drop_data(at_position: Vector2, data: Variant) -> void:
	match data.type:
		"files":
			for f: String in data.files:
				if f.get_extension() in ["png", "jpg", "jpeg", "svg"]:
					insert_text_at_caret("[img]%s[/img]" % [f])
				else:
					insert_text_at_caret("[url]%s[/url]" % [f])
		"nodes":
			var edited_root := EditorInterface.get_edited_scene_root()
			var scene_file := edited_root.scene_file_path
			for n: NodePath in data.nodes:
				var node := get_node(n)
				if not edited_root.is_ancestor_of(node):
					continue
				var relative_path := edited_root.get_path_to(node, true)
				insert_text_at_caret("[url]%s#%s[/url]" % [scene_file, relative_path])
		"tree_item":
			var path := data.tree_item.get_metadata(0) as String
			assert(path)
			if path.get_base_dir() == page.path:
				path = ">" + path.get_file()
			elif path.get_base_dir() == page.path.get_base_dir():
				path = path.get_file()
			insert_text_at_caret("[[page:%s]]" % [path])

func _paste(caret_index: int) -> void:
	if DisplayServer.clipboard_has_image():
		assert(page)
		var err: int
		if not DirAccess.dir_exists_absolute(page.images):
			err = DirAccess.make_dir_absolute(page.images)
			if err != OK:
				printerr("Failed to create image directory: ", page.images)
				return
		var image_name: String
		var image_path: String
		var i := 1
		while i <= 512:
			image_name = "img_" + str(i) + ".webp"
			image_path = page.images.path_join(image_name)
			if not FileAccess.file_exists(image_path):
				break
			image_path = ""
			i += 1
		if not image_path:
			printerr("Failed to save pasted image (too many?): ", page.images)
			return
		var img := DisplayServer.clipboard_get_image()
		err = img.save_webp(image_path)
		if err != OK:
			printerr("Failed to save pasted image: %s (%s)" % [error_string(err), image_path])
			return
		insert_text_at_caret("[[img:%s]]" % [image_name])
	else:
		insert_text_at_caret(DisplayServer.clipboard_get())

func _on_text_changed() -> void:
	is_dirty = true

func _on_text_set() -> void:
	is_dirty = false
