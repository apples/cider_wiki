@tool
extends RichTextLabel

const WikiTab = preload("wiki_tab.gd")

var wiki_tab: WikiTab

var _highlight_line: int
var _highlight_t: float = 1.0: set = _set_highlight_t

@onready var meta_label_container: PanelContainer = $MetaLabelContainer
@onready var meta_label: Label = $MetaLabelContainer/MetaLabel

func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().is_ancestor_of(self):
		return
	meta_label_container.add_theme_stylebox_override("panel", get_theme_stylebox("PanelForeground", "EditorStyles"))

func _draw() -> void:
	if _highlight_t == 1.0:
		return
	var accent_color := get_theme_color("accent_color", "Editor")
	var highlight_rect := _get_line_rect(_highlight_line)
	var alpha := clampf(remap(_highlight_t, 0.5, 1.0, 1.0, 0.0), 0.0, 1.0)
	draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.33 * alpha), false, 2.0)
	draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.17 * alpha), true)

func highlight_line(line: int) -> void:
	_highlight_line = line
	_highlight_t = 0
	create_tween().tween_property(self, "_highlight_t", 1.0, 1.0)
	get_v_scroll_bar().value += _get_line_rect(_highlight_line).get_center().y - size.y / 2.0

func _set_highlight_t(v: float) -> void:
	_highlight_t = v
	queue_redraw()

func _get_line_rect(line: int) -> Rect2:
	var line_ofs := get_line_offset(_highlight_line)
	return Rect2(
		Vector2(0, line_ofs - get_v_scroll_bar().value + 1),
		Vector2(size.x, get_line_offset(_highlight_line + 1) - line_ofs + 2))

func _on_meta_clicked(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("cider:"):
		var page_path: String = wiki_tab.make_absolute(url.substr(6))
		if page_path in wiki_tab.page_collection:
			wiki_tab.open_page(page_path)
		else:
			wiki_tab.create_page_dialog.path_label.text = page_path.get_base_dir().path_join("")
			wiki_tab.create_page_dialog.page_name_line_edit.text = page_path.get_file()
			wiki_tab.create_page_dialog.show()
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

func _on_meta_hover_started(meta: Variant) -> void:
	meta_label.text = str(meta)
	meta_label_container.show()

func _on_meta_hover_ended(meta: Variant) -> void:
	meta_label.text = ""
	meta_label_container.hide()
