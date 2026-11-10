## Authored defaults; room rules are frozen at round start.
extends RefCounted
static func schema() -> Dictionary:
	var fields: Dictionary = {
	}
	var movement: Array = [["move_left", "向左", 65, 4194319], ["move_right", "向右", 68, 4194321],
		["move_up", "向上", 87, 4194320], ["move_down", "向下", 83, 4194322]]
	for entry: Array in movement:
		fields[entry[0]] = {"type": "array", "action": entry[0],
			"default": [{"kind": "key", "code": entry[2], "physical": true}, {"kind": "key", "code": entry[3], "physical": true}],
			"title": entry[1], "audience": "local", "apply": "immediate",
			"control": "binding", "items": {"type": "object", "format": "binding"}, "max_items": 2}
	var result: Dictionary = {
		"schema_format": 3, "settings_version": 1,
		"fields": {
			"duration": {"type": "int", "default": 180, "title": "比赛时限（秒）",
				"audience": "room", "apply": "next_round", "min": 30, "max": 600, "control": "number"},
			"multi_snake_boost": {"type": "array", "action": "multi_snake_boost",
				"default": [{"kind": "mouse", "code": 1}, {"kind": "key", "code": 32, "physical": true}],
				"title": "加速（消耗长度）", "audience": "local", "apply": "immediate",
				"control": "binding", "items": {"type": "object", "format": "binding"}, "max_items": 2},
			"multi_snake_ranks": {"type": "array", "action": "multi_snake_ranks",
				"default": [{"kind": "key", "code": KEY_R, "physical": true}],
				"title": "查看全部排名", "audience": "local", "apply": "immediate",
				"control": "binding", "items": {"type": "object", "format": "binding"}, "max_items": 2}
		},
		"layout": [
			{"id": "rules", "title": "游戏规则", "expanded": true, "children": [{"field": "duration"}]},
			{"id": "input", "title": "操作", "expanded": true,
				"children": [{"field": "move_left"}, {"field": "move_right"}, {"field": "move_up"}, {"field": "move_down"}, {"field": "multi_snake_boost"}, {"field": "multi_snake_ranks"}]}
		]
	}
	result.fields.merge(fields)
	return result
