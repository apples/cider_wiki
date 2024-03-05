@tool
extends Control

const DATA_DIR = "res://cider_wiki_pages"
const PAGE_FILE_EXT = ".txt"

var current_page: Page = null

var page_collection := {} # { [page_path: String]: Page }

var _preloaded_images: Array[ImageTexture]

var _pending_open_page_path: String

@onready var file_tree: Tree = %FileTree
@onready var create_page_dialog: ConfirmationDialog = %CreatePageDialog
@onready var delete_page_dialog: ConfirmationDialog = %DeletePageDialog
@onready var confirm_unsaved_changes_dialog: ConfirmationDialog = %ConfirmUnsavedChangesDialog
@onready var document_rich_text_label: RichTextLabel = %DocumentRichTextLabel
@onready var document_code_edit: CodeEdit = %DocumentCodeEdit
@onready var rendered_view: Control = %RenderedView
@onready var edit_view: Control = %EditView
@onready var help_overlay: CenterContainer = %HelpOverlay
@onready var close_help_button: Button = %CloseHelpButton
@onready var search: Control = %Search
@onready var meta_label_container: PanelContainer = %MetaLabelContainer
@onready var meta_label: Label = %MetaLabelContainer/MetaLabel

func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == self:
		return
	search.wiki_tab = self
	rendered_view.add_theme_stylebox_override("panel", document_rich_text_label.get_theme_stylebox("normal"))
	meta_label_container.add_theme_stylebox_override("panel", get_theme_stylebox("PanelForeground", "EditorStyles"))
	var root := Page.new()
	root.path = "/"
	page_collection["/"] = root
	rescan_page_files()

func open_page(page_path: String) -> void:
	if document_code_edit.is_dirty:
		_pending_open_page_path = page_path
		confirm_unsaved_changes_dialog.show()
		return
	
	assert(page_path.begins_with("/"))
	
	if page_path == "/":
		reset_views()
		return
	
	var page: Page = page_collection[page_path]
	
	var raw_page_text := FileAccess.get_file_as_string(page.file)
	if FileAccess.get_open_error() != OK:
		printerr("Error reading page document: %s (%s)" % [error_string(FileAccess.get_open_error()), page.file])
		return
	
	current_page = page
	
	document_rich_text_label.text = ""
	_preloaded_images = []
	_preloaded_images = preload_all_images(page.images) # needed for the RichTextLabel to find the images
	var rich_page_text := enhance_bbcode(page, raw_page_text)
	document_rich_text_label.text = rich_page_text
	document_code_edit.text = raw_page_text
	document_code_edit.page = page
	document_code_edit.is_dirty = false
	page.tree_item.select(0)
	show_render_view()

func enhance_bbcode(page: Page, page_text: String) -> String:
	var compiled := "[b][font_size=20]%s[/font_size][/b]\n\n" % [page.name]
	
	var i: int = 0
	while i < page_text.length():
		var j := page_text.find("[[", i)
		if j == -1:
			compiled += page_text.substr(i)
			break
		
		var k := page_text.find("]]", j + 2)
		if k == -1:
			compiled += page_text.substr(i)
			break
		
		compiled += page_text.substr(i, j - i)
		
		var tag_text := page_text.substr(j + 2, k - (j + 2))
		if tag_text.begins_with("img:"):
			tag_text = tag_text.trim_prefix("img:")
			compiled += "[img]%s[/img]" % [str(page.images).path_join(tag_text)]
		elif tag_text.begins_with("page:"):
			tag_text = tag_text.trim_prefix("page:")
			compiled += "[url=cider:%s]%s[/url]" % [tag_text, tag_text.get_file().trim_prefix(">")]
		else:
			compiled += "[url=cider:%s]%s[/url]" % [tag_text, tag_text.get_file().trim_prefix(">")]
		
		i = k + 2
	
	return compiled


#region Page path operations

func get_page_dir(page_path: String) -> String:
	assert(page_path.begins_with("/"))
	return DATA_DIR.path_join(page_path).path_join("")

func get_page_filepath(page_path: String) -> String:
	assert(page_path.begins_with("/"))
	return get_page_dir(page_path).path_join(page_path.get_file() + PAGE_FILE_EXT)

func get_page_image_dir(page_path: String) -> String:
	assert(page_path.begins_with("/"))
	return get_page_dir(page_path).path_join("_images")

func make_absolute(relative_page_path: String) -> String:
	if not relative_page_path.begins_with("/"):
		assert(current_page != null)
		var base_dir := current_page.path if relative_page_path.begins_with(">") else current_page.path.get_base_dir()
		relative_page_path = base_dir.path_join(relative_page_path.trim_prefix(">")).simplify_path()
	assert(relative_page_path.begins_with("/"))
	return relative_page_path

#endregion


#region View operations

func show_render_view() -> void:
	rendered_view.show()
	edit_view.hide()
	help_overlay.hide()

func show_edit_view() -> void:
	rendered_view.hide()
	edit_view.show()
	help_overlay.hide()

func reset_views() -> void:
	_preloaded_images = []
	current_page = page_collection["/"]
	document_rich_text_label.text = ""
	document_code_edit.text = ""
	document_code_edit.is_dirty = false
	rendered_view.hide()
	edit_view.hide()
	help_overlay.show()
	close_help_button.hide()
	meta_label_container.hide()

#endregion


#region Filesystem operations

func ensure_page_dir_exists(page_path: String) -> void:
	if not DirAccess.dir_exists_absolute(DATA_DIR):
		DirAccess.make_dir_recursive_absolute(DATA_DIR)
		var gdignore := FileAccess.open(DATA_DIR.path_join(".gdignore"), FileAccess.WRITE)
		if not gdignore:
			printerr("Failed to create %s: %s" % [DATA_DIR.path_join(".gdignore"), error_string(FileAccess.get_open_error())])
		else:
			gdignore.close()
	
	DirAccess.make_dir_recursive_absolute(get_page_dir(page_path))

func get_subpages(page_path: String) -> PackedStringArray:
	var dir_path := DATA_DIR.path_join(page_path)
	return PackedStringArray(Array(DirAccess.get_directories_at(dir_path)).filter(func (page_name: String):
		if page_name.begins_with("."):
			return false
		if page_name == "_images":
			return false
		if not FileAccess.file_exists(dir_path.path_join(page_name).path_join(page_name + PAGE_FILE_EXT)):
			printerr("Page directory missing document: ", dir_path.path_join(page_name))
			return false
		return true
	))

func rescan_page_files() -> void:
	file_tree.clear()
	page_collection = {}
	
	var root := Page.new()
	root.path = "/"
	root.tree_item = file_tree.create_item()
	root.tree_item.set_metadata(0, "/")
	page_collection["/"] = root
	
	if not DirAccess.dir_exists_absolute(DATA_DIR):
		reset_views()
		return
	
	var scan_queue := [root]
	while not scan_queue.is_empty():
		var parent_page: Page = scan_queue.pop_front()
		var dir_path := DATA_DIR.path_join(parent_page.path)
		parent_page.subpages = get_subpages(parent_page.path)
		for page_name: String in parent_page.subpages:
			var page_path := (parent_page.path as String).path_join(page_name)
			var tree_item := file_tree.create_item(parent_page.tree_item)
			tree_item.set_text(0, page_name)
			tree_item.set_metadata(0, page_path)
			var page = Page.new()
			page.path = page_path
			page.name = page_name
			page.file = get_page_filepath(page_path)
			page.images = get_page_image_dir(page_path)
			page.tree_item = tree_item
			page_collection[page_path] = page
			scan_queue.append(page)
	
	if current_page and current_page.path in page_collection:
		open_page(current_page.path)
	else:
		reset_views()

func preload_all_images(image_dir: String) -> Array[ImageTexture]:
	if not DirAccess.dir_exists_absolute(image_dir):
		return []
	var textures: Array[ImageTexture] = []
	for image_file: String in DirAccess.get_files_at(image_dir):
		var img_path := image_dir.path_join(image_file)
		var img := Image.load_from_file(img_path)
		if not img:
			printerr("Bad image: ", img_path)
			continue
		var texture := ImageTexture.create_from_image(img)
		texture.take_over_path(img_path)
		textures.append(texture)
	return textures

#endregion


#region Tree panel signal handlers

func _on_create_page_button_pressed() -> void:
	var selected_item := file_tree.get_selected()
	var selected_path := str(selected_item.get_metadata(0)) if selected_item else "/"
	create_page_dialog.path_label.text = selected_path.get_base_dir().path_join("")
	create_page_dialog.page_name_line_edit.text = ""
	create_page_dialog.show()

func _on_create_child_page_button_pressed() -> void:
	var selected_item := file_tree.get_selected()
	var selected_path := str(selected_item.get_metadata(0)) if selected_item else "/"
	create_page_dialog.path_label.text = selected_path.path_join("")
	create_page_dialog.page_name_line_edit.text = ""
	create_page_dialog.show()

func _on_create_page_dialog_confirmed() -> void:
	var page_path: String = create_page_dialog.get_page_path()
	var page_filepath := get_page_filepath(page_path)
	assert(page_filepath.get_file().is_valid_filename())
	assert(not FileAccess.file_exists(page_filepath))
	ensure_page_dir_exists(page_path)
	var file := FileAccess.open(page_filepath, FileAccess.WRITE)
	if not file:
		printerr("Failed to create page: ", error_string(FileAccess.get_open_error()))
		return
	file.close()
	rescan_page_files()
	open_page(page_path)

func _on_file_tree_item_activated() -> void:
	var selected_page_path: String = file_tree.get_selected().get_metadata(0)
	assert(selected_page_path)
	open_page(selected_page_path)

func _on_file_tree_item_moved(item: TreeItem, target: TreeItem) -> void:
	var item_page_path := str(item.get_metadata(0))
	var dest_page_path := str(target.get_metadata(0)).path_join(item_page_path.get_file())
	if _move_page(item_page_path, dest_page_path):
		rescan_page_files()
		open_page(dest_page_path)

func _on_file_tree_item_edited() -> void:
	var new_name := file_tree.get_edited().get_text(0)
	
	if not new_name.is_valid_filename():
		printerr("Invalid page name: ", new_name)
		return
	
	var item_page_path := str(file_tree.get_edited().get_metadata(0))
	var new_page_path := item_page_path.get_base_dir().path_join(new_name)
	
	if _move_page(item_page_path, new_page_path):
		rescan_page_files()
		open_page(new_page_path)
	else:
		rescan_page_files()

func _move_page(src_page_path: String, dest_page_path: String) -> bool:
	var src_dir := get_page_dir(src_page_path)
	var dest_dir := get_page_dir(dest_page_path)
	if DirAccess.dir_exists_absolute(dest_dir):
		printerr("Cannot move/rename page, destination dir already exists: %s => %s" % [src_dir, dest_dir])
		return false
	if FileAccess.file_exists(dest_dir):
		printerr("Cannot move/rename page, file with same name exists at destination: %s => %s" % [src_dir, dest_dir])
		return false
	var err: int
	if src_page_path.get_file() != dest_page_path.get_file():
		var dest_file := src_dir.path_join(dest_page_path.get_file() + PAGE_FILE_EXT)
		if FileAccess.file_exists(dest_file):
			printerr("Cannot move/rename page, unrecognized file would be overwritten: %s" % [dest_file])
			return false
		var src_file := get_page_filepath(src_page_path)
		err = DirAccess.rename_absolute(src_file, dest_file)
		if err != OK:
			printerr("Failed to move page: %s (%s => %s)" % [error_string(err), src_file, dest_file])
			return false
	err = DirAccess.rename_absolute(src_dir, dest_dir)
	if err != OK:
		printerr("Failed to move page: %s (%s => %s)" % [error_string(err), src_dir, dest_dir])
		return false
	return true

func _on_file_tree_delete_requested(item: TreeItem) -> void:
	delete_page_dialog.path_label.text = item.get_metadata(0)
	delete_page_dialog.show()

func _on_delete_page_dialog_confirmed() -> void:
	var page_path: String = delete_page_dialog.path_label.text
	OS.move_to_trash(ProjectSettings.globalize_path(get_page_dir(page_path)))
	var open_parent = page_path == current_page.path
	rescan_page_files()
	if open_parent:
		open_page(page_path.get_base_dir())

#endregion


#region Rendered view signal handlers

func _on_edit_page_button_pressed() -> void:
	show_edit_view()

func _on_document_rich_text_label_meta_clicked(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("cider:"):
		var page_path: String = make_absolute(url.substr(6))
		if page_path in page_collection:
			open_page(page_path)
		else:
			create_page_dialog.path_label.text = page_path.get_base_dir().path_join("")
			create_page_dialog.page_name_line_edit.text = page_path.get_file()
			create_page_dialog.show()
	elif url.begins_with("res:"):
		var parts := url.rsplit("#", true, 1)
		var path := parts[0]
		var fragment := parts[1] if parts.size() == 2 else ""
		match path.get_extension():
			"tscn", "scn":
				EditorInterface.open_scene_from_path(path)
				if fragment != "":
					var node := EditorInterface.get_edited_scene_root().get_node_or_null(fragment)
					if not node:
						printerr("Node not found in scene: ", url)
					else:
						EditorInterface.get_selection().clear()
						EditorInterface.edit_node(node)
			"gd":
				var script := ResourceLoader.load(path, "Script") as Script
				var line := -1
				if fragment.is_valid_int():
					line = fragment.to_int()
				elif fragment != "":
					var regex := RegEx.create_from_string("(?m)^((static\\s+)?func|(static\\s+)?var|@onready var|@export[^\n]*var)\\s+%s[^a-zA-Z0-9_]" % [fragment])
					var reg_m := regex.search(script.source_code)
					if not reg_m:
						printerr("Member not found in script: ", url)
					else:
						line = 1 + script.source_code.count("\n", 0, reg_m.get_start())
				EditorInterface.set_main_screen_editor("Script")
				EditorInterface.edit_script(script, line)
			_:
				EditorInterface.select_file(path)
	else:
		OS.shell_open(url)

func _on_document_rich_text_label_meta_hover_started(meta: Variant) -> void:
	meta_label.text = str(meta)
	meta_label_container.show()


func _on_document_rich_text_label_meta_hover_ended(meta: Variant) -> void:
	meta_label.text = ""
	meta_label_container.hide()

#endregion


#region Edit view signal handlers

func _on_save_edit_button_pressed() -> void:
	var file := FileAccess.open(current_page.file, FileAccess.WRITE)
	if not file:
		printerr("Failed to save page: %s (%s)", [error_string(FileAccess.get_open_error()), current_page.file])
		return
	file.store_string(document_code_edit.text)
	file.close()
	document_code_edit.is_dirty = false
	open_page(current_page.path)


func _on_cancel_edit_button_pressed() -> void:
	open_page(current_page.path)

func _on_help_edit_button_pressed() -> void:
	help_overlay.show()
	close_help_button.show()

func _on_confirm_unsaved_changes_dialog_confirmed() -> void:
	assert(_pending_open_page_path)
	document_code_edit.is_dirty = false
	open_page(_pending_open_page_path)
	_pending_open_page_path = ""

func _on_confirm_unsaved_changes_dialog_canceled() -> void:
	assert(_pending_open_page_path)
	_pending_open_page_path = ""

#endregion


#region Help overlay signal handlers

func _on_help_rich_text_label_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

func _on_close_help_button_pressed() -> void:
	help_overlay.hide()

#endregion


func _on_visibility_changed() -> void:
	if visible and file_tree:
		rescan_page_files()


class Page:
	var path: String
	var name: String
	var file: String
	var images: String
	var tree_item: TreeItem
	var subpages: PackedStringArray

