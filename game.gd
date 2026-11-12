## Scope lifecycle, authenticated steering and host snapshots. Simulation lives in snake_world.
extends Control
const World: Script = preload("res://games/minigame/gp_snake_battle/snake_world.gd")
const Arena: Script = preload("res://games/minigame/gp_snake_battle/arena_view.gd")
const Pages: Script = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
var api: PartyAPI
var request: Dictionary
var players: Array[Dictionary]
var local_id: String = ""
var world: World = World.new()
@export var pages: Pages
var running: bool = false
var view: Dictionary = {}
var accumulator: float = 0.0
var publish_clock: float = 0.0
var input_clock: float = 0.0
var sequence: int = 0
var revision: int = 0
var received_revision: int = 0
var _published_snakes: Dictionary = {}
var _published_food: Dictionary = {}
var _food: Dictionary = {}
var _head_history: Dictionary = {}
var _head_ticks: Dictionary = {}
var _tick: int = 0
var _sample: int = 0
var _received_sample: int = 0
var _pending_motion: Dictionary = {}
var _end_msec: int = 0
var action_sequences: Dictionary[String, int] = {}
var last_action: Dictionary[String, float] = {}
var names: Dictionary[String, String] = {}
@onready var arena: Arena = %Arena
@onready var stats: Label = %Stats
@onready var timer: Label = %Timer
@onready var message: Label = %Message
@onready var hint: Label = %Hint
@onready var leaders: Label = %Leaders

func party_setup(context: PartyAPI, config: Dictionary) -> void:
	api = context
	request = config.duplicate(true)
	players = api.get_players()
	for player: Dictionary in players:
		names[player.player_id] = player.name
		if player.is_local:
			local_id = player.player_id
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)
	api.on_close(_disconnect)

func _ready() -> void:
	if api == null:
		push_error("请从 GodotParty 大厅启动蛇蛇大作战。")
		return
	%Title.text = api.i18n.text(&"蛇蛇大作战")
	# Scene captions are editor examples; only round snapshots supply live values.
	stats.text = ""
	timer.text = ""
	message.text = ""
	leaders.text = ""
	arena.local_id = local_id
	arena.names = names
	for player: Dictionary in players:
		arena.colors[player.player_id] = Color(api.get_appearance(player.player_id).color)
	hint.text = api.i18n.text(&"hud.controls", {"boost": api.input.binding_text(&"multi_snake_boost"), "rank": api.input.binding_text(&"multi_snake_ranks")})
	assert(pages != null, "Assign ProtocolPages in the game scene")
	var error: Error = pages.prepare(self, api, request, _start_play)
	if error != OK:
		_fail(error)

func party_start() -> void:
	pages.transport_started()

func _start_play() -> void:
	running = true
	if api.is_host():
		var ids: Array[String] = []
		for player: Dictionary in players:
			ids.append(player.player_id)
		world.reset(ids, api.get_seed(), float(api.get_settings().duration))
		_end_msec = api.net.host_time_msec() + roundi(float(api.get_settings().duration) * 1000.0)
		_players_changed()
		_publish()

func party_stop(_reason: StringName) -> void:
	running = false
	set_process(false)
	_disconnect()

func _disconnect() -> void:
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)

## Local standings use their own binding; Tab is reserved for the framework network panel.
func _input(event: InputEvent) -> void:
	if running and api.input.event_matches(event, &"multi_snake_ranks"):
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not running:
		return
	input_clock += delta
	if input_clock >= 0.05 and not local_id.is_empty() and not view.is_empty():
		input_clock = 0.0
		_send_input()
		if not running:
			return
	arena.show_names = api.input.is_pressed(&"multi_snake_ranks")
	if api.is_host():
		accumulator += delta
		while accumulator >= World.STEP and world.time < world.duration:
			accumulator -= World.STEP
			world.tick(World.STEP)
			_record_heads()
		publish_clock += delta
		if publish_clock >= 0.05:
			publish_clock = 0.0
			_publish()
		if not running:
			return
		if world.time >= world.duration:
			_finish()
	_update_hud()

func _send_input() -> void:
	var snake: Dictionary = view.snakes[local_id]
	if not snake.alive or snake.withdrawn:
		return
	var direction: Vector2 = api.input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var angle: float = snake.angle
	if not api.input.input_blocked:
		if direction.length_squared() > 0.01:
			angle = direction.angle()
		else:
			var target: Vector2 = arena.world_mouse() - arena.display_body(local_id)[0]
			if target.length() > 24.0:
				angle = target.angle()
	sequence += 1
	var error: Error = api.net.send_to_host(&"steer", {"seq": sequence, "angle": angle,
		"boost": api.input.is_pressed(&"multi_snake_boost") and not api.input.input_blocked}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 1)
	if error != OK:
		_fail(error)

## Only host snapshots and connected participants' finite, sequenced actions enter the simulation.
func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not running:
		return
	if topic in [&"snake/events", &"snake/motion"] and sender.peer_id == 1 and not api.is_host():
		if payload is Dictionary:
			_receive_update(topic, payload)
		return
	if topic == &"steer" and api.is_host():
		if not payload is Dictionary or not payload.get("seq") is int or payload.seq < 1:
			return
		if not (payload.get("angle") is float or payload.get("angle") is int) or not is_finite(float(payload.angle)) or not payload.get("boost") is bool:
			return
		for player: Dictionary in api.get_players():
			var id: String = player.player_id
			if player.connected and id in sender.player_ids and world.snakes.has(id) and not world.snakes[id].withdrawn:
				if payload.seq <= action_sequences.get(id, 0) or world.time - last_action.get(id, -1.0) < 0.025:
					return
				action_sequences[id] = payload.seq
				last_action[id] = world.time
				world.steer(id, float(payload.angle), payload.boost)
				return

func _publish() -> void:
	var snakes: Dictionary = {}
	var motion: Dictionary = {}
	for id: String in world.snakes:
		var snake: Dictionary = world.snakes[id]
		var previous: Dictionary = _published_snakes.get(id, {})
		var facts: Dictionary = {}
		var saved: Dictionary = {}
		for field: String in ["mass", "best", "kills", "deaths", "alive", "withdrawn", "generation", "boost"]:
			var value: Variant = int(snake[field]) if field in ["mass", "best"] else snake[field]
			saved[field] = value
			if not previous.has(field) or previous[field] != value:
				facts[field] = value
		if previous.is_empty() or previous.generation != snake.generation:
			facts["body"] = snake.body.duplicate()
			facts["angle"] = snake.angle
			facts["shield_end_msec"] = api.net.host_time_msec() + roundi(snake.shield * 1000.0)
		if previous.is_empty() or previous.alive != snake.alive:
			facts["respawn_end_msec"] = api.net.host_time_msec() + roundi(snake.respawn * 1000.0)
		if not facts.is_empty():
			snakes[id] = facts
		_published_snakes[id] = saved
		if snake.alive and _head_history.has(id):
			motion[id] = {"generation": snake.generation, "angle": snake.angle, "heads": _head_history[id].points}
	var live_food: Dictionary = {}
	var added: Dictionary = {}
	for piece: Dictionary in world.food:
		live_food[piece.id] = piece.p
		if not _published_food.has(piece.id):
			added[piece.id] = piece.p
	var removed: Array[int] = []
	for id: int in _published_food:
		if not live_food.has(id):
			removed.append(id)
	if not snakes.is_empty() or not added.is_empty() or not removed.is_empty() or revision == 0:
		revision += 1
		var event: Dictionary = {"revision": revision, "tick": _tick, "snakes": snakes, "food_added": added, "food_removed": removed}
		if revision == 1:
			event["end_msec"] = _end_msec
		var error: Error = api.net.broadcast(&"snake/events", event, MultiplayerPeer.TRANSFER_MODE_RELIABLE, false)
		if error != OK:
			_fail(error)
			return
	_published_food = live_food
	if not motion.is_empty():
		_sample += 1
		var error: Error = api.net.broadcast(&"snake/motion", {"revision": revision, "sample": _sample, "tick": _tick, "snakes": motion}, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, false, "instance", 2)
		if error != OK:
			_fail(error)
			return
	view = world.snapshot()
	arena.accept(view)

func _players_changed() -> void:
	if not running or not api.is_host():
		return
	for player: Dictionary in api.get_players():
		if not player.connected and not world.snakes[player.player_id].withdrawn:
			world.withdraw(player.player_id)

func _finish() -> void:
	running = false
	var error: Error = pages.present({"request_id": request.request_id, "reason": "completed",
		"rankings": world.rankings(), "columns": [
			{"key": "length", "title": api.i18n.text(&"result.length"), "format": "integer"},
			{"key": "kills", "title": api.i18n.text(&"result.kills"), "format": "integer"},
			{"key": "deaths", "title": api.i18n.text(&"result.deaths"), "format": "integer"}]})
	if error != OK:
		_fail(error)

func _fail(error: Error) -> void:
	running = false
	api.fail("multi_snake_failed", error_string(error))

func _update_hud() -> void:
	if view.is_empty():
		return
	var now: int = api.net.host_time_msec()
	for snake: Dictionary in view.snakes.values():
		if not api.is_host():
			snake.shield = maxf(0.0, float(snake.shield_end_msec - now) / 1000.0)
			snake.respawn = maxf(0.0, float(snake.respawn_end_msec - now) / 1000.0)
	var seconds: int = maxi(0, ceili(float(_end_msec - now) / 1000.0))
	timer.text = api.i18n.text(&"hud.timer", {"minutes": str(seconds / 60).pad_zeros(2), "seconds": str(seconds % 60).pad_zeros(2)})
	message.text = ""
	if local_id.is_empty():
		stats.text = api.i18n.text(&"hud.spectating")
	else:
		var snake: Dictionary = view.snakes[local_id]
		stats.text = api.i18n.text(&"hud.stats", {"length": int(snake.mass), "best": int(snake.best), "kills": snake.kills})
		if not snake.alive:
			message.text = api.i18n.text(&"hud.respawn", {"seconds": ceili(snake.respawn)})
		elif snake.shield > 0.0:
			message.text = api.i18n.text(&"hud.protected", {"seconds": ceili(snake.shield)})
	var rows: Array = view.snakes.keys()
	rows.sort_custom(func(a: String, b: String) -> bool: return view.snakes[a].best > view.snakes[b].best)
	var lines: PackedStringArray = PackedStringArray([api.i18n.text(&"hud.leaders")])
	var limit: int = rows.size() if arena.show_names else mini(3, rows.size())
	for index: int in range(limit):
		var id: String = rows[index]
		lines.append(api.i18n.text(&"hud.leader_row", {"position": index + 1, "player": names[id], "length": int(view.snakes[id].best)}))
	# Keep one editable Label; only replace its caption when visible standings change.
	var caption: String = "\n".join(lines)
	if leaders.text != caption:
		leaders.text = caption

## A short redundant head trail covers ordinary packet loss without retransmitting entire bodies.
func _record_heads() -> void:
	_tick += 1
	for id: String in world.snakes:
		var snake: Dictionary = world.snakes[id]
		if not _head_history.has(id) or _head_history[id].generation != snake.generation:
			_head_history[id] = {"generation": snake.generation, "points": PackedVector2Array()}
		var points: PackedVector2Array = _head_history[id].points
		points.append(snake.body[0])
		if points.size() > 24:
			points.remove_at(0)
		_head_history[id].points = points

func _receive_update(topic: StringName, payload: Dictionary) -> void:
	if not payload.get("revision") is int:
		return
	if topic == &"snake/motion":
		if not payload.get("sample") is int or payload.sample <= _received_sample or not payload.get("tick") is int or not payload.get("snakes") is Dictionary or payload.revision < received_revision:
			return
		_received_sample = payload.sample
		if payload.revision > received_revision:
			_pending_motion = payload
		else:
			_apply_heads(payload)
		return
	if payload.revision <= received_revision:
		return
	if payload.revision != received_revision + 1 or not payload.get("tick") is int or not payload.get("snakes") is Dictionary or not payload.get("food_added") is Dictionary or not payload.get("food_removed") is Array:
		_fail(ERR_INVALID_DATA)
		return
	if view.is_empty():
		view = {"snakes": {}, "food": PackedVector2Array()}
	for id: Variant in payload.snakes:
		if not id is String or not names.has(id) or not payload.snakes[id] is Dictionary:
			return
		var facts: Dictionary = payload.snakes[id]
		if not view.snakes.has(id):
			view.snakes[id] = {"shield": 0.0, "respawn": 0.0}
		if facts.has("body"):
			if not facts.body is PackedVector2Array or facts.body.is_empty() or facts.body.size() > int(World.MAX_MASS):
				return
			for point: Vector2 in facts.body:
				if not point.is_finite():
					return
			_head_ticks[id] = payload.tick
		view.snakes[id].merge(facts, true)
	for id: Variant in payload.food_added:
		if not id is int or not payload.food_added[id] is Vector2 or not payload.food_added[id].is_finite():
			return
		_food[id] = payload.food_added[id]
	for id: Variant in payload.food_removed:
		if not id is int:
			return
		_food.erase(id)
	view.food = PackedVector2Array(_food.values())
	if payload.has("end_msec"):
		if not payload.end_msec is int:
			return
		_end_msec = payload.end_msec
	received_revision = payload.revision
	if not _pending_motion.is_empty() and _pending_motion.revision <= received_revision:
		if _pending_motion.revision == received_revision:
			_apply_heads(_pending_motion, false)
		_pending_motion.clear()
	arena.accept(view.duplicate(true))

func _apply_heads(payload: Dictionary, present: bool = true) -> void:
	for id: Variant in payload.snakes:
		if not id is String or not view.snakes.has(id) or not payload.snakes[id] is Dictionary:
			continue
		var sample: Dictionary = payload.snakes[id]
		var snake: Dictionary = view.snakes[id]
		if sample.get("generation") != snake.generation or not sample.get("heads") is PackedVector2Array or sample.heads.size() > 24 or not (sample.get("angle") is float or sample.get("angle") is int) or not is_finite(float(sample.angle)):
			continue
		var body: PackedVector2Array = snake.body
		var length: int = clampi(int(snake.mass), 1, int(World.MAX_MASS))
		while body.size() < length:
			body.append(body[body.size() - 1])
		body.resize(length)
		for index: int in sample.heads.size():
			var step_id: int = payload.tick - sample.heads.size() + index + 1
			var point: Vector2 = sample.heads[index]
			if step_id <= int(_head_ticks.get(id, -1)) or not point.is_finite():
				continue
			body[0] = point
			for part: int in range(1, body.size()):
				var gap: Vector2 = body[part - 1] - body[part]
				if gap.length_squared() > World.SPACING * World.SPACING:
					body[part] = body[part - 1] - gap.normalized() * World.SPACING
			_head_ticks[id] = step_id
		snake.body = body
		snake.angle = sample.angle
	if present:
		arena.accept(view.duplicate(true))
