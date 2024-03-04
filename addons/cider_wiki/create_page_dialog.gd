@tool
extends ConfirmationDialog

@export var wiki_tab: Node

@onready var path_label: Label = $Form/PathLabel
@onready var page_name_line_edit: LineEdit = $Form/PageNameLineEdit
@onready var error_label: Label = $Form/ErrorLabel

func get_page_path() -> String:
	return path_label.text.path_join(page_name_line_edit.text)

func validate() -> void:
	assert(path_label.text.ends_with("/"))
	
	error_label.text = ""
	get_ok_button().disabled = false
	
	var page_name := page_name_line_edit.text
	
	if page_name == "":
		error_label.text = "Page Name is required."
		get_ok_button().disabled = true
		return
	
	if not page_name.is_valid_filename():
		error_label.text = "Page Name is not a valid filename."
		get_ok_button().disabled = true
		return
	
	var filepath: String = wiki_tab.get_page_filepath(get_page_path())
	
	if FileAccess.file_exists(filepath):
		error_label.text = "A Page with that name already exists."
		get_ok_button().disabled = true
		return

func _on_page_name_line_edit_text_changed(new_text: String) -> void:
	validate()

func _on_page_name_line_edit_text_submitted(new_text: String) -> void:
	validate()
	if error_label.text == "":
		hide()
		confirmed.emit()

func _on_visibility_changed() -> void:
	if visible:
		validate()
		page_name_line_edit.caret_column = page_name_line_edit.text.length()
		page_name_line_edit.grab_focus.call_deferred()
		
