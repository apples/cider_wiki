@tool
extends Tree

func _get_drag_data(at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = get_selected().get_text(0)
	set_drag_preview(preview)
	return { type = "tree_item", tree_item = get_selected() }
