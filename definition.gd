## Lightweight catalog data. Do not load gameplay scenes or scripts here.
extends RefCounted

static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "tags": ["original", "arcade"], "controls": {"multi_snake_boost": "加速（消耗长度）", "multi_snake_ranks": "按住查看全部排名"}}
