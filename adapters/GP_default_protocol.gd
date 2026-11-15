## Only the default protocol's standard ranking mode is supported.
extends RefCounted

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}

func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "蛇蛇大作战仅支持普通排名局。"}
	return {"ok": true}

func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
