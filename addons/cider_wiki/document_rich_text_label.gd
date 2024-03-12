@tool
extends RichTextLabel

const WikiTab = preload("wiki_tab.gd")

var wiki_tab: WikiTab

var _highlight_line: int
var _highlight_t: float = 1.0: set = _set_highlight_t

var _syntax_highlighters: Dictionary = {}
var _code_blocks := []

@onready var meta_label_container: PanelContainer = $MetaLabelContainer
@onready var meta_label: Label = $MetaLabelContainer/MetaLabel

func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().is_ancestor_of(self):
		return
	
	get_v_scroll_bar().value_changed.connect(_on_v_scroll_bar_value_changed)
	
	meta_label_container.add_theme_stylebox_override("panel", get_theme_stylebox("PanelForeground", "EditorStyles"))
	
	var type_color: Color = EditorInterface.get_editor_settings()["text_editor/theme/highlighting/engine_type_color"]
	var usertype_color: Color = EditorInterface.get_editor_settings()["text_editor/theme/highlighting/user_type_color"]
	
	var gdscript_highlighter := preload("highlighters/gdscript_highlighter.tres").duplicate(true)
	
	# Engine types
	var types := ClassDB.get_class_list()
	for t: String in types:
		gdscript_highlighter.add_keyword_color(t, type_color)
	
	# User types
	var global_classes := ProjectSettings.get_global_class_list()
	for d: Dictionary in global_classes:
		gdscript_highlighter.add_keyword_color(d.class, usertype_color)
	
	# Autoloads
	var autoloads := ProjectSettings.get_property_list().filter(func (x): return x.name.begins_with("autoload/"))
	for p: Dictionary in autoloads:
		if ProjectSettings.get_setting(p.name).begins_with("*"):
			gdscript_highlighter.add_keyword_color((p.name as String).trim_prefix("autoload/"), usertype_color)
	
	_syntax_highlighters["gd"] = gdscript_highlighter
	_syntax_highlighters["gdscript"] = gdscript_highlighter

func _draw() -> void:
	if _highlight_t == 1.0:
		return
	var accent_color := get_theme_color("accent_color", "Editor")
	var highlight_rect := _get_line_rect(_highlight_line)
	var alpha := clampf(remap(_highlight_t, 0.5, 1.0, 1.0, 0.0), 0.0, 1.0)
	draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.33 * alpha), false, 2.0)
	draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.17 * alpha), true)

func set_page(page: WikiTab.Page, page_text: String) -> void:
	text = ""
	for c in _code_blocks:
		if c.code_edit:
			c.code_edit.queue_free()
	var res := enhance_bbcode(page, page_text)
	var enhanced_bbcode: String = res[0]
	_code_blocks = res[1]
	text = enhanced_bbcode
	_update_code_blocks(true)

func highlight_line(line: int) -> void:
	_highlight_line = line
	_highlight_t = 0
	create_tween().tween_property(self, "_highlight_t", 1.0, 1.0)
	get_v_scroll_bar().value += _get_line_rect(_highlight_line).get_center().y - size.y / 2.0

func enhance_bbcode(page: WikiTab.Page, page_text: String) -> Array:
	var compiled := "[b][font_size=20]%s[/font_size][/b]\n\n" % [page.name]
	var code_snippets := []
	
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
		elif tag_text.begins_with("code:"):
			var l := page_text.find("[[/]]", k + 2)
			if l == -1:
				l = page_text.length()
			var snippet_text := page_text.substr(k + 2, l - (k + 2)).trim_prefix("\n").trim_suffix("\n")
			var code_edit := CodeEdit.new()
			code_edit.editable = false
			code_edit.gutters_draw_line_numbers = true
			code_edit.scroll_fit_content_height = true
			code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			code_edit.autowrap_mode = TextServer.AUTOWRAP_WORD
			code_edit.syntax_highlighter = _syntax_highlighters.get(tag_text.trim_prefix("code:"), null)
			code_edit.text = snippet_text
			add_child(code_edit)
			code_edit.size.y = code_edit.get_minimum_size().y
			code_snippets.append({ code_edit = code_edit, pos_y = 0 })
			var TS := TextServerManager.get_primary_interface()
			var rid := get_theme_font("normal_font").get_rids()[0]
			var spacing := TS.font_get_spacing(rid, TextServer.SPACING_TOP) + TS.font_get_spacing(rid, TextServer.SPACING_BOTTOM)
			var asc100 := TS.font_get_ascent(rid, 100) + TS.font_get_descent(rid, 100) + spacing
			var sz := ceili(lerpf(0, 100, inverse_lerp(0, asc100, code_edit.get_minimum_size().y))) 
			compiled += "[font_size=%s]_[/font_size]{code_block %s}" % [sz, code_snippets.size() - 1]
			k = l + 3
		elif tag_text.begins_with("page:"):
			tag_text = tag_text.trim_prefix("page:")
			compiled += "[url=cider:%s]%s[/url]" % [tag_text, tag_text.get_file().trim_prefix(">")]
		else:
			compiled += "[url=cider:%s]%s[/url]" % [tag_text, tag_text.get_file().trim_prefix(">")]
		
		i = k + 2
	
	return [compiled, code_snippets]

func _set_highlight_t(v: float) -> void:
	_highlight_t = v
	queue_redraw()

func _get_line_rect(line: int) -> Rect2:
	var line_ofs := get_line_offset(_highlight_line)
	return Rect2(
		Vector2(0, line_ofs - get_v_scroll_bar().value + 1),
		Vector2(size.x, get_line_offset(_highlight_line + 1) - line_ofs + 2))

func _update_code_blocks(reset: bool = false) -> void:
	await get_tree().process_frame
	for i in _code_blocks.size():
		var c: Dictionary = _code_blocks[i]
		if reset:
			var line := get_character_line(get_parsed_text().find("_{code_block %s}" % i))
			c.pos_y = get_line_offset(line + 1) - c.code_edit.get_minimum_size().y + 2
		c.code_edit.position.y = c.pos_y - get_v_scroll_bar().value
		c.code_edit.size.x = size.x - (get_v_scroll_bar().size.x - 2 if get_v_scroll_bar().visible else 0)
		c.code_edit.size.y = c.code_edit.get_minimum_size().y

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

func _on_v_scroll_bar_value_changed(value: float) -> void:
	_update_code_blocks()

func _on_resized() -> void:
	_update_code_blocks(true)
