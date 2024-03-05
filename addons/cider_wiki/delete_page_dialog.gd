@tool
extends ConfirmationDialog

@onready var path_label: Label = $Form/PathLabel
@onready var warning_label: Label = $Form/WarningLabel

func _ready() -> void:
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().is_ancestor_of(self):
		return
	warning_label.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
