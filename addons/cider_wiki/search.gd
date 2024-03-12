@tool
extends Control

const WikiTab = preload("wiki_tab.gd")
const DocumentRichTextLabel = preload("res://addons/cider_wiki/document_rich_text_label.gd")

static var escape_chars := RegEx.create_from_string("[\\\\.\\^$*+?()\\[\\]{}|]")

var wiki_tab: WikiTab

var _search_queue: Array[WikiTab.Page] = []
var _search_regex: RegEx = null
var _page_items: Dictionary = {} # { [page_name: String]: TreeItem }

@onready var search_line_edit: LineEdit = $SearchBar/SearchLineEdit
@onready var search_popup_panel: PopupPanel = $SearchPopupPanel
@onready var message: Label = $SearchPopupPanel/ResultsContainer/MessageContainer/Message
@onready var results_tree: Tree = $SearchPopupPanel/ResultsContainer/ResultsTree
@onready var regex_flag_button: Button = $SearchBar/RegexFlagButton
@onready var source_flag_button: Button = $SearchBar/SourceFlagButton

func _ready() -> void:
	set_process(false)
	results_tree.create_item()

func _process(delta: float) -> void:
	if _search_queue.is_empty():
		set_process(false)
		if results_tree.get_root().get_child_count() == 0:
			message.text = "No results."
		else:
			message.text = "Search complete."
		return
	
	var page: WikiTab.Page = _search_queue.pop_front()
	
	for subpage: String in page.subpages:
		_search_queue.append(wiki_tab.page_collection[page.path.path_join(subpage)])
	
	if page.path == "/":
		return
	
	var raw_page_text := FileAccess.get_file_as_string(page.file)
	if FileAccess.get_open_error() != OK:
		printerr("Failed to search page: ", page.path)
		return
	
	var searched_page_text := raw_page_text
	if not source_flag_button.button_pressed:
		var fake_images := wiki_tab.preload_all_images(page.images, true)
		var rtl := DocumentRichTextLabel.new()
		rtl.auto_translate = false
		var parsed: Array = rtl.enhance_bbcode(page, raw_page_text)
		rtl.parse_bbcode(parsed[0])
		searched_page_text = rtl.get_parsed_text()
		for i: int in parsed[1].size():
			searched_page_text = searched_page_text.replace("_{code_block %s}" % i, parsed[1][i].code_edit.text.replace("\n", "\\n"))
		rtl.free()
	
	var name_match := _search_regex.search(page.name)
	var matches := _search_regex.search_all(searched_page_text)
	if name_match == null and matches.is_empty():
		return
	
	var page_item: TreeItem = _page_items.get(page.path, null)
	if not page_item:
		page_item = results_tree.create_item()
		_page_items[page.path] = page_item
		page_item.set_cell_mode(0, TreeItem.CELL_MODE_CUSTOM)
		page_item.set_text(0, page.path)
		if name_match:
			page_item.set_metadata(0, {
				page_path = page.path,
				match_text = name_match.get_string(),
				match_start = name_match.get_start() + page.path.get_base_dir().path_join("").length(),
			})
		else:
			page_item.set_metadata(0, { page_path = page.path })
		page_item.set_custom_draw(0, self, "_match_item_custom_draw")
		page_item.set_custom_color(0, results_tree.get_theme_color("font_color") * Color(1, 1, 1, 0.67))
	
	for m: RegExMatch in matches:
		var label := RichTextLabel.new()
		var line_start := searched_page_text.rfind("\n", m.get_start()) + 1
		var line_end := posmod(searched_page_text.find("\n", m.get_end()), searched_page_text.length() + 1)
		var line_number := searched_page_text.count("\n", 0, line_start) if line_start > 0 else 0
		var line_text := searched_page_text.substr(line_start, line_end - line_start)
		var line_number_text := "%s: " % [line_number + 1]
		var match_item := results_tree.create_item(page_item)
		match_item.set_cell_mode(0, TreeItem.CELL_MODE_CUSTOM)
		match_item.set_text(0, line_number_text + line_text)
		match_item.set_metadata(0, {
			line_number = line_number,
			char_index = m.get_start(),
			match_text = m.get_string(),
			match_start = line_number_text.length() + m.get_start() - line_start,
		})
		match_item.set_custom_draw(0, self, "_match_item_custom_draw")

func start_search():
	if not regex_flag_button.button_pressed:
		_search_regex = RegEx.create_from_string("(?i)" + escape_chars.sub(search_line_edit.text, "\\$0", true))
	else:
		_search_regex = RegEx.create_from_string("(?mi)" + search_line_edit.text)
	if not _search_regex.is_valid():
		add_theme_color_override("font_color", Color.RED)
		_search_regex = null
		return
	_search_queue = [wiki_tab.page_collection["/"] as WikiTab.Page]
	set_process(true)

func stop_search():
	_search_queue = []
	_search_regex = null
	_page_items.clear()
	results_tree.clear()
	results_tree.create_item()
	set_process(false)

func _on_search_line_edit_text_changed(new_text: String) -> void:
	remove_theme_color_override("font_color")

func _on_search_line_edit_text_submitted(new_text: String) -> void:
	if search_line_edit.text == "":
		return
	
	var popup_rect := get_global_rect()
	popup_rect.position += Vector2(get_window().position) + Vector2(0, size.y)
	popup_rect.size.y = get_parent().size.y / 2.0
	search_popup_panel.popup(popup_rect)
	message.text = "Searching..."
	start_search()

func _on_search_popup_panel_popup_hide() -> void:
	stop_search()

func _on_results_tree_item_activated() -> void:
	if results_tree.get_selected().get_parent() == results_tree.get_root():
		wiki_tab.open_page(results_tree.get_selected().get_metadata(0).page_path)
	else:
		wiki_tab.open_page(results_tree.get_selected().get_parent().get_metadata(0).page_path)
		if source_flag_button.button_pressed:
			wiki_tab.show_edit_view()
			wiki_tab.document_code_edit.set_caret_line(int(results_tree.get_selected().get_metadata(0).line_number))
			wiki_tab.document_code_edit.grab_focus()
		else:
			var rtl_line := wiki_tab.document_rich_text_label.get_character_line(results_tree.get_selected().get_metadata(0).char_index)
			wiki_tab.document_rich_text_label.highlight_line(rtl_line)
			wiki_tab.document_rich_text_label.grab_focus()
	search_popup_panel.hide.call_deferred()

func _match_item_custom_draw(tree_item: TreeItem, rect: Rect2) -> void:
	if "match_text" not in tree_item.get_metadata(0):
		return
	
	var font := results_tree.get_theme_font("font")
	var font_size := results_tree.get_theme_font_size("font_size")
	var accent_color := results_tree.get_theme_color("accent_color", "Editor")
	var inner_item_margin_left := results_tree.get_theme_constant("inner_item_margin_left")
	
	var highlight_rect := Rect2(
		rect.position.x + font.get_string_size(tree_item.get_text(0).left(tree_item.get_metadata(0).match_start), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x - 1 + inner_item_margin_left,
		rect.position.y + 1.0 * EditorInterface.get_editor_scale(),
		font.get_string_size(tree_item.get_metadata(0).match_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2.0,
		rect.size.y - 2.0 * EditorInterface.get_editor_scale())
	
	results_tree.draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.33), false, 2.0)
	results_tree.draw_rect(highlight_rect, accent_color * Color(1, 1, 1, 0.17), true)
