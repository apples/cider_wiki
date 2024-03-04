@tool
extends EditorPlugin

const WIKI_TAB = preload("wiki_tab.tscn")
const ICON_CIDER = preload("icons/icon_cider.svg")

var wiki_tab: Control

func _enter_tree() -> void:
	wiki_tab = WIKI_TAB.instantiate()
	EditorInterface.get_editor_main_screen().add_child(wiki_tab)
	_make_visible(false)


func _exit_tree() -> void:
	if wiki_tab:
		wiki_tab.queue_free()
		wiki_tab = null


func _has_main_screen():
	return true

func _make_visible(visible):
	if wiki_tab:
		wiki_tab.visible = visible

func _get_plugin_name():
	return "Wiki"

func _get_plugin_icon():
	return ICON_CIDER

