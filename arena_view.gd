## Presentation only: interpolate authoritative bodies and follow the local snake.
extends Control
const World: Script = preload("res://games/minigame/godot_party_default_multi_snake_game/snake_world.gd")
var current: Dictionary = {}
var previous: Dictionary = {}
var blend: float = 1.0
var local_id: String = ""
var names: Dictionary[String, String] = {}
var colors: Dictionary[String, Color] = {}
var camera: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var camera_ready: bool = false
var show_names: bool = false
var aim: Vector2 = Vector2.ZERO
@onready var font: Font = get_theme_default_font()
var pulse: float = 0.0

func accept(snapshot: Dictionary) -> void:
	previous = current
	current = snapshot
	blend = 0.0

func _process(delta: float) -> void:
	if current.is_empty():
		return
	blend = minf(1.0, blend + delta / 0.05)
	pulse += delta
	var follow: String = local_id
	if follow.is_empty():
		for id: String in current.snakes:
			if current.snakes[id].alive:
				follow = id
				break
	if not follow.is_empty():
		var snake: Dictionary = current.snakes[follow]
		var body: PackedVector2Array = display_body(follow)
		var destination: Vector2 = body[0]
		if not camera_ready:
			camera = destination
			camera_ready = true
		camera = camera.lerp(destination, 1.0 - exp(-delta * 9.0))
		var target_zoom: float = clampf(1.12 - (snake.mass - World.START_MASS) * 0.0025, 0.65, 1.12)
		zoom = lerpf(zoom, target_zoom, 1.0 - exp(-delta * 2.0))
	queue_redraw()

func display_body(id: String) -> PackedVector2Array:
	var snake: Dictionary = current.snakes[id]
	var body: PackedVector2Array = snake.body.duplicate()
	if previous.is_empty() or not previous.snakes.has(id):
		return body
	var old: Dictionary = previous.snakes[id]
	if old.generation != snake.generation or old.alive != snake.alive:
		return body
	for index: int in range(mini(body.size(), old.body.size())):
		body[index] = old.body[index].lerp(body[index], blend)
	return body

func world_mouse() -> Vector2:
	return (get_local_mouse_position() - size * 0.5) / zoom + camera

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080e20"))
	if current.is_empty():
		return
	var offset: Vector2 = size * 0.5 - camera * zoom
	draw_set_transform(offset, 0.0, Vector2.ONE * zoom)
	draw_circle(Vector2.ZERO, World.RADIUS, Color("#101d30"))
	# Sparse world grid makes motion legible without shrinking the playfield.
	var left: Vector2 = camera - size * 0.5 / zoom
	var right: Vector2 = camera + size * 0.5 / zoom
	for x: int in range(int(floor(left.x / 90.0)), int(ceil(right.x / 90.0)) + 1):
		for y: int in range(int(floor(left.y / 90.0)), int(ceil(right.y / 90.0)) + 1):
			var p: Vector2 = Vector2(x, y) * 90.0
			if p.length() < World.RADIUS - 30.0:
				draw_circle(p, 1.8, Color("#28415a"))
	draw_arc(Vector2.ZERO, World.RADIUS, 0.0, TAU, 200, Color("#ff537e"), 7.0, true)
	draw_arc(Vector2.ZERO, World.RADIUS - 26.0, 0.0, TAU, 200, Color(1, 0.3, 0.5, 0.12), 30.0, true)
	for point: Vector2 in current.food:
		if point.x < left.x - 20 or point.x > right.x + 20 or point.y < left.y - 20 or point.y > right.y + 20:
			continue
		var hue: float = fposmod(point.x * 0.003 + point.y * 0.002, 1.0)
		var tint: Color = Color.from_hsv(hue, 0.55, 1.0)
		draw_circle(point, 11.0, Color(tint, 0.08))
		draw_circle(point, 6.5, Color(tint, 0.2))
		draw_circle(point, 3.3 + sin(pulse * 3.0 + hue * TAU) * 0.5, tint)
	for id: String in current.snakes:
		var snake: Dictionary = current.snakes[id]
		if not snake.alive:
			continue
		var body: PackedVector2Array = display_body(id)
		var radius: float = World.body_radius(snake.mass)
		var tint: Color = colors[id]
		if snake.shield > 0.0:
			tint.a = 0.5 + 0.3 * (sin(pulse * 9.0) + 1.0) * 0.5
		for index: int in range(body.size() - 1, -1, -1):
			var p: Vector2 = body[index]
			if p.x < left.x - 45 or p.x > right.x + 45 or p.y < left.y - 45 or p.y > right.y + 45:
				continue
			var taper: float = clampf(float(body.size() - index) / 7.0, 0.32, 1.0)
			if snake.boost and snake.mass > World.START_MASS + 1.0:
				draw_circle(p, radius * taper + 6.0, Color(tint, 0.07))
			draw_circle(p + Vector2(2, 5), radius * taper + 2, Color(0, 0, 0, 0.25))
			draw_circle(p, radius * taper + 1.8, Color("#728599").lerp(tint, 0.4))
			draw_circle(p, radius * taper, tint.darkened(0.12 if index % 4 < 2 else 0.0))
			draw_circle(p + Vector2(-3, -4), radius * taper * 0.4, Color(1, 1, 1, 0.12))
		var head: Vector2 = body[0]
		var forward: Vector2 = Vector2.from_angle(snake.angle)
		var side: Vector2 = forward.orthogonal()
		for sign_value: float in [-1.0, 1.0]:
			var eye: Vector2 = head + forward * 6.0 + side * 6.0 * sign_value
			draw_circle(eye, 5.0, Color.WHITE)
			draw_circle(eye + forward * 1.8, 2.5, Color("#111a2a"))
		if snake.shield > 0:
			draw_arc(head, radius + 9, 0, TAU, 32, Color(0.6, 0.95, 1.0, 0.55), 1.8, true)
		if id == local_id:
			draw_arc(head, radius + 15, snake.angle - 0.5, snake.angle + 0.5, 16, Color("#a4fce9"), 2.0, true)
		if show_names or id == local_id:
			var caption: String = names[id]
			var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string_outline(font, head + Vector2(-width * 0.5, -31), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color("#081220"))
			draw_string(font, head + Vector2(-width * 0.5, -31), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
	_draw_minimap()

func _draw_minimap() -> void:
	var center: Vector2 = size - Vector2(115, 124)
	var radius: float = 77.0
	draw_circle(center, radius + 7, Color(0.02, 0.04, 0.09, 0.85))
	draw_circle(center, radius, Color("#14273b"))
	draw_arc(center, radius, 0, TAU, 64, Color("#577086"), 1.5, true)
	for id: String in current.snakes:
		var snake: Dictionary = current.snakes[id]
		if not snake.alive:
			continue
		var point: Vector2 = center + snake.body[0] / World.RADIUS * radius
		if id == local_id:
			draw_circle(point, 6.0, Color.WHITE)
		draw_circle(point, 3.5, colors[id])
