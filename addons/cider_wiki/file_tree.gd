@tool
extends Tree

signal item_moved(item: TreeItem, target: TreeItem)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = get_selected().get_text(0)
	set_drag_preview(preview)
	return { type = "tree_item", tree_item = get_selected() }

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	drop_mode_flags = DROP_MODE_ON_ITEM
	return "type" in data and data.type == "tree_item" and (data.tree_item as TreeItem).get_tree() == self

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var drop_item := data.tree_item as TreeItem
	var target := get_item_at_position(at_position)
	if not target:
		target = get_root()
	if drop_item != target and drop_item.get_parent() != target:
		item_moved.emit(drop_item, target)
