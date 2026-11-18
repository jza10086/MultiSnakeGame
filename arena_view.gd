## Presentation only: interpolate authoritative bodies and follow the local snake.
extends Control
const World: Script = preload("res://games/minigame/GP_snake_battle/snake_world.gd")
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
const FRUIT: Texture2D = preload("res://games/minigame/GP_snake_battle/fruit.svg")
const INK: Color = Color("#233d36")
const PAPER: Color = Color("#fbfcf6")
const FIELD: Color = Color("#edf3e9")

func accept(snapshot: Dictionary) -> void:
	previous = current
	current = snapshot
	blend = 0.0

func _process(delta: float) -> void:
	if current.is_empty():
		return
	blend = minf(1.0, blend + delta / 0.05)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("#e5d9cb"))
	if current.is_empty():
		return
	var bounds: Rect2 = Rect2(camera - size * 0.5 / zoom, size / zoom)
	draw_set_transform(size * 0.5 - camera * zoom, 0.0, Vector2.ONE * zoom)
	draw_circle(Vector2.ZERO, World.RADIUS, FIELD, true, -1, true)
	for x: int in range(floori(bounds.position.x / 72.0), ceili(bounds.end.x / 72.0) + 1):
		for y: int in range(floori(bounds.position.y / 72.0), ceili(bounds.end.y / 72.0) + 1):
			var dot: Vector2 = Vector2(x, y) * 72.0
			if dot.length() < World.RADIUS - 12.0:
				draw_circle(dot, 1.6, Color("#bed1c0"), true, -1, true)
	draw_arc(Vector2.ZERO, World.RADIUS, 0.0, TAU, 360, Color("#b9604b"), 4.0, true)
	var visible_food: Rect2 = bounds.grow(9.0)
	for point: Vector2 in current.food:
		if visible_food.has_point(point):
			var kind: int = posmod(roundi(point.x) + roundi(point.y), 3)
			draw_texture_rect_region(FRUIT, Rect2(point - Vector2(8, 8), Vector2(16, 16)), Rect2(kind * 32, 0, 32, 32))
	for id: String in current.snakes:
		if current.snakes[id].alive:
			_draw_snake(id, bounds.grow(50))
	draw_set_transform(Vector2.ZERO)
	_draw_minimap()

func _draw_snake(id: String, bounds: Rect2) -> void:
	var snake: Dictionary = current.snakes[id]
	var body: PackedVector2Array = display_body(id)
	var radius: float = World.body_radius(snake.mass)
	var tint: Color = colors[id]
	# Outline the whole silhouette first so overlapping discs form a continuous ribbon.
	for outline: bool in [true, false]:
		for i: int in range(body.size() - 1, -1, -1):
			if bounds.has_point(body[i]):
				var taper: float = clampf(float(body.size() - i) / 6.0, 0.36, 1.0)
				draw_circle(body[i], radius * taper + (1.7 if outline else 0.0), INK if outline else tint, true, -1, true)
	for i: int in range(4, body.size() - 4, 4):
		var side: Vector2 = body[i - 1].direction_to(body[i + 1]).orthogonal()
		draw_line(body[i] - side * 4.0, body[i] + side * 4.0, tint.lerp(INK if tint.get_luminance() > 0.3 else PAPER, 0.55), 2.5, true)
	var head: Vector2 = body[0]
	var forward: Vector2 = Vector2.from_angle(snake.angle)
	var side: Vector2 = forward.orthogonal()
	for sign_value: float in [-1.0, 1.0]:
		var eye: Vector2 = head + forward * 4.5 + side * 6.0 * sign_value
		draw_circle(eye, 4.8, PAPER, true, -1, true)
		draw_circle(eye + forward * 1.4, 2.7, INK, true, -1, true)
	if snake.shield > 0:
		for quadrant: int in range(4):
			var start: float = quadrant * PI * 0.5
			draw_arc(head, radius + 7.0, start + 0.15, start + 1.4, 12, Color("#187356"), 2.3, true)
	if id == local_id or (snake.boost and snake.mass > World.START_MASS + 1.0):
		var count: int = 2 if snake.boost and snake.mass > World.START_MASS + 1.0 else 1
		for i: int in range(count):
			var tip: Vector2 = head + forward * (radius + 11.0 + i * 7.0)
			draw_polyline(PackedVector2Array([tip - forward * 4.0 - side * 4.0, tip, tip - forward * 4.0 + side * 4.0]), INK, 2.3, true)
	if show_names or id == local_id:
		var caption: String = names[id]
		var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(font, head + Vector2(-width * 0.5, -29), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)

func _draw_minimap() -> void:
	var center: Vector2 = size - Vector2(112, 112)
	var radius: float = 72.0
	draw_circle(center, radius + 5.0, PAPER, true, -1, true)
	draw_arc(center, radius + 5.0, 0, TAU, 96, Color("#91aa99"), 1.5, true)
	draw_circle(center, radius, Color("#dce9da"), true, -1, true)
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
		draw_dashed_line(center - axis * radius, center + axis * radius, Color("#afc5b2"), 1.0, 4.0)
	for id: String in current.snakes:
		var snake: Dictionary = current.snakes[id]
		if snake.alive:
			var point: Vector2 = center + snake.body[0] / World.RADIUS * radius
			draw_circle(point, 6.0 if id == local_id else 4.5, INK, true, -1, true)
			draw_circle(point, 4.0 if id == local_id else 3.0, colors[id], true, -1, true)
