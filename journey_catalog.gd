extends RefCounted

const Classic = preload("res://campaign_catalog.gd")
const VERSION: int = 2
const DIRS: Dictionary = {"U": Vector2i.UP, "D": Vector2i.DOWN, "L": Vector2i.LEFT, "R": Vector2i.RIGHT}
const BRIDGE_STEP: Dictionary = {2: 12, 4: 14, 6: 0, 8: 2}

static func actor(at: Vector2i, timber: bool = false, tool: bool = false) -> Dictionary:
	return {"cell": at, "from": at, "t": 1.0, "duration": 0.17, "timber": timber, "tool": tool, "used": false}

static func empty_room() -> Dictionary:
	return {"size": Vector2i(20, 12), "floor": {}, "water": {}, "goals": [], "boxes": [], "enemies": [], "cat": {}, "chest_open": false, "flowers": [], "blooms": {}, "bridges": {}, "render_tiles": {}, "combat_gates": {}}

static func baseline(index: int) -> Dictionary:
	var scene: Node2D = Classic.create_level(index)
	var tiles: TileMapLayer = scene.get_node("TileMapLayer")
	var r: Dictionary = empty_room()
	var start: Vector2i = Vector2i(scene.get_node("player").position / 64.0)
	var bounds: Rect2i = tiles.get_used_rect()
	for c: Vector2i in tiles.get_used_cells(): r["render_tiles"][c] = tiles.get_cell_source_id(c)
	var queue: Array[Vector2i] = [start]
	r["floor"][start] = true
	var cursor: int = 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		for d: Vector2i in DIRS.values():
			var to: Vector2i = at + d
			if bounds.has_point(to) and not r["render_tiles"].has(to) and not r["floor"].has(to):
				r["floor"][to] = true
				queue.append(to)
	for b: Node2D in scene.get_node("Boxes").get_children(): r["boxes"].append(actor(Vector2i(b.position / 64.0)))
	for g: Node2D in scene.get_node("Goals").get_children(): r["goals"].append(Vector2i(g.position / 64.0))
	r["start"] = start
	scene.free()
	return r

static func trace(r: Dictionary, route: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var player: Vector2i = r["start"]
	var boxes: Array[Vector2i] = []
	for b: Dictionary in r["boxes"]: boxes.append(b["cell"])
	for letter: String in route:
		var to: Vector2i = player + DIRS[letter]
		var index: int = boxes.find(to)
		var target: Vector2i = to + DIRS[letter]
		result.append({"from": player, "to": to, "box": index, "target": target})
		if index >= 0: boxes[index] = target
		player = to
	return result

static func add_flower(r: Dictionary, moves: Array[Dictionary]) -> bool:
	for n: int in range(moves.size()):
		var move: Dictionary = moves[n]
		if move["box"] < 0 or r["water"].has(move["target"]) or r["goals"].has(move["target"]): continue
		for goal: Vector2i in r["goals"]:
			var safe: bool = goal != r["start"]
			for b: Dictionary in r["boxes"]:
				if b["cell"] == goal: safe = false
			for earlier: int in range(n + 1):
				if moves[earlier]["to"] == goal or (moves[earlier]["box"] >= 0 and moves[earlier]["target"] == goal): safe = false
			if safe:
				r["flowers"].append({"cell": move["target"], "gates": [goal]})
				return true
	return false

static func add_cat(r: Dictionary, moves: Array[Dictionary]) -> void:
	var used: Dictionary = {r["start"]: true}
	for b: Dictionary in r["boxes"]: used[b["cell"]] = true
	for move: Dictionary in moves:
		used[move["to"]] = true
		if move["box"] >= 0: used[move["target"]] = true
	for c: Vector2i in r["floor"]:
		if used.has(c): continue
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if r["floor"].has(c + d) and not used.has(c + d):
				r["cat"] = actor(c)
				r["cat"].merge({"dir": d, "wait": 4.0, "patrol_cells": [c, c + d]})
				return

static func build(index: int) -> Dictionary:
	var source: Dictionary = Classic.entries()[index]
	var r: Dictionary = baseline(index)
	var route: String = source["solution"]
	var moves: Array[Dictionary] = trace(r, route)
	var topics: Array[String] = ["basics", "rules"]
	if BRIDGE_STEP.has(index):
		var n: int = BRIDGE_STEP[index]
		assert(moves[n]["box"] < 0 and moves[n + 1]["box"] < 0)
		r["boxes"].append(actor(moves[n]["to"], true))
		r["water"][moves[n + 1]["to"]] = true
		topics.append("bridge")
	if index in [1, 3, 4, 5, 6, 7, 8]:
		assert(add_flower(r, moves), "Expected a real cargo-triggered delivery gate")
		topics.append("flower")
	if index in [5, 8]:
		add_cat(r, moves)
		topics.append("cat")
	if int(r["render_tiles"].get(Vector2i(11, 8), 0)) not in [1, 3, 4]:
		r["render_tiles"].erase(Vector2i(11, 8))
		r["floor"][Vector2i(11, 8)] = true
	r["theme"] = source["theme"]
	r["art"] = source.get("art_index", index)
	var all_rooms: Array[Dictionary] = [r]
	if index == 6:
		r["portal"] = r["start"] + Vector2i(0, 3)
		all_rooms.append(hidden_room())
	var hints: Array[String] = ["一个箱子，一个目标。", "先压花坛开门，再分别交货。", "先用蓝绳木料修桥，再运送两箱货物。", "原来的三箱围栏：开门后再安排归位顺序。", "保留四箱工坊，先修桥、开门，再调度货物。", "四箱换位，留意边道上的园丁猫。", "四箱密林：修复水道；起点藤洞可选挑战。", "五箱迷庭：保留原通道，先后顺序很重要。", "五箱大仓：修桥、开门和货物调度的综合考验。"]
	return {"id": "original_%02d_v2" % index, "title": "%02d %s" % [index + 1, source["title"]], "hint": hints[index], "rooms": all_rooms, "start": r["start"], "solution": route, "reference": route.length(), "topics": topics, "original_index": index, "difficulty_metrics": source["difficulty_metrics"]}

static func enemy(at: Vector2i, low: Vector2i, high: Vector2i, boss: bool) -> Dictionary:
	var e: Dictionary = actor(at)
	e.merge({"dir": Vector2i.DOWN, "low": low, "high": high, "alive": true, "boss": boss, "wait": 2.5})
	return e

static func hidden_room(advanced: bool = false) -> Dictionary:
	var r: Dictionary = empty_room()
	r["size"] = Vector2i(13, 9)
	r["theme"] = 3 if advanced else 2
	r["art"] = 8 if advanced else 3
	for y: int in range(1, 8):
		for x: int in range(1, 12):
			if x != 6: r["floor"][Vector2i(x, y)] = true
	r["floor"][Vector2i(6, 2)] = true
	for c: Vector2i in [Vector2i(5, 4), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(10, 6), Vector2i(11, 6), Vector2i(11, 3), Vector2i(11, 4), Vector2i(11, 5)]: r["floor"].erase(c)
	for y: int in range(3, 6): r["water"][Vector2i(10, y)] = true
	r["boxes"] = [actor(Vector2i(3, 4), false, true), actor(Vector2i(8, 4), false, true)]
	r["enemies"] = [enemy(Vector2i(4, 4), Vector2i(4, 3), Vector2i(4, 5), false), enemy(Vector2i(9, 4), Vector2i(9, 3), Vector2i(9, 5), true)]
	if advanced:
		r["water"][Vector2i(7, 4)] = true
		r["boxes"][1] = actor(Vector2i(8, 3), false, true)
		r["enemies"][1]["wait"] = 1.5
	r["combat_gates"] = {Vector2i(6, 2): 0, Vector2i(9, 6): 1}
	r["spawn"] = Vector2i(2, 2)
	r["portal"] = Vector2i(2, 2)
	r["chest"] = Vector2i(9, 7)
	r["landmarks"] = {Vector2i(5, 4): "挤压石墙", Vector2i(10, 4): "落水机关", Vector2i(6, 2): "击败小怪开门", Vector2i(9, 6): "击败Boss开门"}
	for y: int in range(9):
		for x: int in range(13):
			var c: Vector2i = Vector2i(x, y)
			if not r["floor"].has(c): r["render_tiles"][c] = 4
	r["render_tiles"][Vector2i(5, 4)] = 5
	for c: Vector2i in [Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6)]: r["render_tiles"][c] = 7
	for c: Vector2i in [Vector2i(7, 6), Vector2i(8, 6), Vector2i(10, 6), Vector2i(11, 6)]: r["render_tiles"][c] = 10
	return r
