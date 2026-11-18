## Host-owned continuous snake simulation. No input, scene or networking dependencies.
extends RefCounted

const RADIUS: float = 1650.0
const STEP: float = 1.0 / 60.0
const SPACING: float = 9.0
const START_MASS: float = 22.0
const MAX_MASS: float = 220.0
const FOOD_COUNT: int = 650
const FOOD_LIMIT: int = 1300
const RESPAWN: float = 3.0
const PROTECTION: float = 2.0

var snakes: Dictionary = {}
var food: Array[Dictionary] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var time: float = 0.0
var duration: float = 180.0
var refill_clock: float = 0.0
var next_food_id: int = 0

var trails: Dictionary[String, PackedVector2Array] = {}

## Oldest point first. At normal speed 640 fixed steps exceed the longest possible snake.
const TRAIL_LIMIT: int = 640

static func append_head(trail: PackedVector2Array, point: Vector2) -> void:
	if trail[-1] != point:
		trail.append(point)
		if trail.size() > TRAIL_LIMIT:
			trail.remove_at(0)

## Sample backwards along the polyline once, at equal distances travelled by the head.
static func sample_body(trail: PackedVector2Array, length: int) -> PackedVector2Array:
	var body: PackedVector2Array = PackedVector2Array()
	var edge: int = trail.size() - 1
	var start: float = 0.0
	var span: float = trail[edge].distance_to(trail[edge - 1])
	for part: int in range(length):
		var distance: float = part * SPACING
		while distance > start + span and edge > 1:
			start += span
			edge -= 1
			span = trail[edge].distance_to(trail[edge - 1])
		body.append(trail[edge].lerp(trail[edge - 1], clampf((distance - start) / span, 0.0, 1.0)))
	return body

func reset(ids: Array[String], seed_value: int, seconds: float) -> void:
	rng.seed = seed_value
	time = 0.0
	duration = seconds
	refill_clock = 0.0
	snakes.clear()
	trails.clear()
	food.clear()
	next_food_id = 0
	for id: String in ids:
		snakes[id] = {"body": PackedVector2Array(), "angle": 0.0, "aim": 0.0,
			"mass": START_MASS, "best": START_MASS, "kills": 0, "deaths": 0,
			"alive": false, "withdrawn": false, "respawn": 0.0,
			"shield": 0.0, "boost": false, "boost_clock": 0.0, "generation": 0,
			"input_time": 0.0}
		_spawn(id)
	for index: int in range(FOOD_COUNT):
		food.append(_food_piece(_random_point(RADIUS - 40.0), 1))

func _random_point(radius: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius

## Pick the clearest of 32 candidates, then protect the entire newborn body.
func _spawn(id: String) -> void:
	var best: Vector2 = Vector2.ZERO
	var clearance: float = -1.0
	for attempt: int in range(32):
		var candidate: Vector2 = _random_point(RADIUS - 320.0)
		var distance: float = RADIUS - candidate.length()
		for other: Dictionary in snakes.values():
			if not other.alive:
				continue
			for point: Vector2 in other.body:
				distance = minf(distance, candidate.distance_to(point))
		if distance > clearance:
			best = candidate
			clearance = distance
	var snake: Dictionary = snakes[id]
	var angle: float = best.angle() + PI
	var body: PackedVector2Array = PackedVector2Array()
	for index: int in range(int(START_MASS)):
		body.append(best - Vector2.from_angle(angle) * SPACING * index)
	trails[id] = PackedVector2Array([best - Vector2.from_angle(angle) * SPACING * MAX_MASS, best])
	snake.body = body
	snake.angle = angle
	snake.aim = angle
	snake.mass = START_MASS
	snake.alive = true
	snake.respawn = 0.0
	snake.shield = PROTECTION
	snake.boost = false
	snake.boost_clock = 0.0
	snake.input_time = time
	snake.generation += 1

func steer(id: String, angle: float, boost: bool) -> void:
	var snake: Dictionary = snakes[id]
	if not snake.alive or snake.withdrawn:
		return
	snake.aim = wrapf(angle, -PI, PI)
	snake.boost = boost
	snake.input_time = time

static func body_radius(mass: float) -> float:
	return 12.0 + sqrt(mass) * 0.2

## Fixed steps keep all heads moving before collision resolution, including simultaneous deaths.
func tick(delta: float) -> void:
	time = minf(time + delta, duration)
	for id: String in snakes:
		var snake: Dictionary = snakes[id]
		if snake.withdrawn:
			continue
		if not snake.alive:
			snake.respawn = maxf(0.0, snake.respawn - delta)
			if snake.respawn <= 0.0 and time < duration:
				_spawn(id)
			continue
		snake.shield = maxf(0.0, snake.shield - delta)
		if time - snake.input_time > 0.4:
			snake.boost = false
		var boosting: bool = snake.boost and snake.mass > START_MASS + 1.0
		snake.angle = rotate_toward(snake.angle, snake.aim, 3.0 * delta)
		var head: Vector2 = snake.body[0] + Vector2.from_angle(snake.angle) * (310.0 if boosting else 190.0) * delta
		append_head(trails[id], head)
		var body: PackedVector2Array = sample_body(trails[id], int(snake.mass))
		if boosting:
			snake.mass = maxf(START_MASS, snake.mass - 3.0 * delta)
			snake.boost_clock += delta
			if snake.boost_clock >= 0.25:
				snake.boost_clock -= 0.25
				_add_food(body[body.size() - 1], 1)
		snake.body = body
	var deaths: Dictionary = {}
	for id: String in snakes:
		var snake: Dictionary = snakes[id]
		if not snake.alive:
			continue
		var head: Vector2 = snake.body[0]
		if head.length() + body_radius(snake.mass) >= RADIUS:
			deaths[id] = ""
			continue
		if snake.shield > 0.0:
			continue
		for other_id: String in snakes:
			var other: Dictionary = snakes[other_id]
			if other_id == id or not other.alive or other.shield > 0.0:
				continue
			var hit_radius: float = body_radius(snake.mass) + body_radius(other.mass)
			for point: Vector2 in other.body:
				if head.distance_squared_to(point) < hit_radius * hit_radius:
					deaths[id] = other_id
					break
			if deaths.has(id):
				break
	for id: String in deaths:
		_die(id, deaths[id])
	for id: String in snakes:
		var snake: Dictionary = snakes[id]
		if not snake.alive:
			continue
		var body: PackedVector2Array = snake.body
		var eat_radius: float = body_radius(snake.mass) + 9.0
		for index: int in range(food.size() - 1, -1, -1):
			if body[0].distance_squared_to(food[index].p) <= eat_radius * eat_radius:
				snake.mass = minf(MAX_MASS, snake.mass + float(food[index].value))
				snake.best = maxf(snake.best, snake.mass)
				food.remove_at(index)
		var length: int = int(snake.mass)
		if body.size() != length:
			snake.body = sample_body(trails[id], length)
	refill_clock += delta
	if refill_clock >= 0.2:
		refill_clock = 0.0
		for index: int in range(mini(8, FOOD_COUNT - food.size())):
			food.append(_food_piece(_random_point(RADIUS - 40.0), 1))

func _add_food(point: Vector2, value: int) -> void:
	if food.size() < FOOD_LIMIT:
		food.append(_food_piece(point.limit_length(RADIUS - 24.0), value))

func _die(id: String, killer: String) -> void:
	var snake: Dictionary = snakes[id]
	var body: PackedVector2Array = snake.body
	# Newborn starting mass never becomes food: repeated deaths cannot farm free length.
	var drops: int = maxi(0, int((snake.mass - START_MASS) * 0.7))
	for index: int in range(drops):
		var point: Vector2 = body[mini(body.size() - 1, int(float(index) / maxf(1, drops) * body.size()))]
		_add_food(point + _random_point(12.0), 1)
	snake.alive = false
	snake.boost = false
	snake.deaths += 1
	snake.respawn = RESPAWN
	if not killer.is_empty():
		snakes[killer].kills += 1

func withdraw(id: String) -> void:
	if snakes[id].alive:
		_die(id, "")
	snakes[id].withdrawn = true
	snakes[id].respawn = 0.0

func snapshot() -> Dictionary:
	var positions: PackedVector2Array = PackedVector2Array()
	for pellet: Dictionary in food:
		positions.append(pellet.p)
	return {"snakes": snakes.duplicate(true), "food": positions, "time": maxf(0.0, duration - time)}

func rankings() -> Array:
	var result: Array = []
	for id: String in snakes:
		var snake: Dictionary = snakes[id]
		var rank_value: int = 1
		for other: Dictionary in snakes.values():
			if not other.withdrawn and int(other.best) > int(snake.best):
				rank_value += 1
		result.append({"player_id": id, "rank": 0 if snake.withdrawn else rank_value,
			"status": "withdrawn" if snake.withdrawn else "completed",
			"metrics": {"length": int(snake.best), "kills": snake.kills, "deaths": snake.deaths}})
	return result

func _food_piece(point: Vector2, value: int) -> Dictionary:
	next_food_id += 1
	return {"id": next_food_id, "p": point, "value": value}
