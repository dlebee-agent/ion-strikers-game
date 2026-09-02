class_name Crosshair
extends Control

## Four-arm HUD reticle. Draws in the centre of whatever rect the parent
## gives it, so the same node works as a full-screen overlay and as the
## settings preview.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if CrosshairSettings:
		CrosshairSettings.changed.connect(queue_redraw)


func _draw() -> void:
	if not CrosshairSettings:
		return
	var c := size * 0.5
	var col := CrosshairSettings.color()
	var arm := CrosshairSettings.size
	var thick := CrosshairSettings.thickness
	var space := CrosshairSettings.gap
	var ht := thick * 0.5
	draw_rect(Rect2(c.x - space - arm, c.y - ht, arm, thick), col)
	draw_rect(Rect2(c.x + space, c.y - ht, arm, thick), col)
	draw_rect(Rect2(c.x - ht, c.y - space - arm, thick, arm), col)
	draw_rect(Rect2(c.x - ht, c.y + space, thick, arm), col)
