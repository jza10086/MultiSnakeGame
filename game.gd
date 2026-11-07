## Scope lifecycle, authenticated steering and host snapshots. Simulation lives in snake_world.
extends Control
const World: Script = preload("res://games/minigame/godot_party_default_multi_snake_game/snake_world.gd")
const Arena: Script = preload("res://games/minigame/godot_party_default_multi_snake_game/arena_view.gd")
const Pages: Script = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
var api: PartyAPI
var request: Dictionary
var players: Array[Dictionary]
var local_id: String = ""
var world: World = World.new()
var pages: Pages
var running: bool = false
var view: Dictionary = {}
var accumulator: float = 0.0
var publish_clock: float = 0.0
var input_clock: float = 0.0
var sequence: int = 0
var revision: int = 0
var received_revision: int = -1
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
	pages = Pages.new()
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

## The local standings action owns its key before the framework's unhandled Tab shortcut.
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
		publish_clock += delta
		if publish_clock >= 0.08:
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
		"boost": api.input.is_pressed(&"multi_snake_boost") and not api.input.input_blocked})
	if error != OK:
		_fail(error)

## Only host snapshots and connected participants' finite, sequenced actions enter the simulation.
func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not running:
		return
	if topic == &"state":
		if sender.peer_id != 1 or not payload is Dictionary:
			return
		if not payload.get("revision") is int or payload.revision <= received_revision:
			return
		received_revision = payload.revision
		view = payload
		arena.accept(view)
	elif topic == &"steer" and api.is_host():
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
	revision += 1
	var snapshot: Dictionary = world.snapshot()
	snapshot.revision = revision
	var error: Error = api.net.broadcast_stream(&"state", snapshot)
	if error != OK:
		_fail(error)

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
	var seconds: int = ceili(view.time)
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
