"""Bounded, reproducible Sokoban push-optimal analysis. No game or save side effects."""
from __future__ import annotations

import argparse
import base64
from collections import deque
from functools import lru_cache
import heapq
import json
from pathlib import Path
import re
import struct
import time

ROOT = Path(__file__).resolve().parents[1]
DIRS = ((0, -1, "U"), (1, 0, "R"), (0, 1, "D"), (-1, 0, "L"))


def geometry(entry):
    floor = {(x, y) for y, row in enumerate(entry["rows"]) for x, c in enumerate(row) if c != "#"}
    return floor, tuple(entry["player"]), tuple(sorted(map(tuple, entry["boxes"]))), tuple(sorted(map(tuple, entry["goals"])))


def reachable(start, boxes, floor):
    paths = {start: ""}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        for dx, dy, label in DIRS:
            cell = x + dx, y + dy
            if cell in floor and cell not in boxes and cell not in paths:
                paths[cell] = paths[(x, y)] + label
                queue.append(cell)
    return paths


def replay(entry, solution):
    floor, player, boxes, goals = geometry(entry)
    boxes = set(boxes)
    pushes = 0
    visited = {player} | boxes
    switches = 0
    last_box = None
    for label in solution:
        dx, dy, _ = next(item for item in DIRS if item[2] == label)
        dest = player[0] + dx, player[1] + dy
        assert dest in floor, (label, player, "wall")
        if dest in boxes:
            after = dest[0] + dx, dest[1] + dy
            assert after in floor and after not in boxes, (label, dest, "blocked box")
            if last_box is not None and last_box != dest:
                switches += 1
            last_box = after
            boxes.remove(dest)
            boxes.add(after)
            pushes += 1
            visited.add(after)
        player = dest
        visited.add(player)
    assert boxes == set(goals), "Route does not solve the level"
    return {"solution_steps": len(solution), "solution_pushes": pushes, "box_switches": switches}, visited


def solve(entry, seconds=8.0, max_states=60000):
    """A* over (box positions, reachable player region), unit cost per push.

    Walking loops collapse into a region. Result is push-optimal, not step-optimal.
    Expanded-state counts are search effort, never a count of all solutions.
    """
    floor, player, boxes, goals = geometry(entry)
    goal_set = set(goals)
    distances = []
    for goal in goals:
        dist = {goal: 0}
        queue = deque([goal])
        while queue:
            x, y = queue.popleft()
            for dx, dy, _ in DIRS:
                prev, support = (x - dx, y - dy), (x - 2 * dx, y - 2 * dy)
                if prev in floor and support in floor and prev not in dist:
                    dist[prev] = dist[(x, y)] + 1
                    queue.append(prev)
        distances.append(dist)
    live = set().union(*(set(d) for d in distances))

    @lru_cache(None)
    def assignment(bs, wall_aware=True):
        costs = {0: 0}
        for box in bs:
            next_costs = {}
            for mask, cost in costs.items():
                for i, goal in enumerate(goals):
                    if mask & (1 << i):
                        continue
                    step = distances[i].get(box, 100000) if wall_aware else abs(box[0] - goal[0]) + abs(box[1] - goal[1])
                    target = mask | (1 << i)
                    next_costs[target] = min(next_costs.get(target, 100000), cost + step)
            costs = next_costs
        return costs.get((1 << len(goals)) - 1, 100000)

    start_time = time.monotonic()
    serial = 0
    heap = [(assignment(boxes), 0, serial, player, boxes, "")]
    seen = {}
    pruned = 0
    while heap:
        if len(seen) >= max_states or time.monotonic() - start_time > seconds:
            return {"status": "limit", "expanded_states": len(seen)}
        _, negative_depth, _, current, bs, route = heapq.heappop(heap)
        depth = -negative_depth
        paths = reachable(current, set(bs), floor)
        key = bs, min(paths)
        if seen.get(key, 100000) <= depth:
            continue
        seen[key] = depth
        if set(bs) == goal_set:
            metrics, _ = replay(entry, route)
            metrics.update(status="solved", minimum_pushes=depth, manhattan_lower_bound=assignment(boxes, False),
                           forced_extra_pushes=depth - assignment(boxes, False), expanded_states=len(seen),
                           static_dead_squares=len(floor - live), pruned_dead_pushes=pruned,
                           narrow_cells=sum(sum((x + dx, y + dy) in floor for dx, dy, _ in DIRS) <= 2 for x, y in floor),
                           solution=route)
            return metrics
        occupied = set(bs)
        for box in bs:
            for dx, dy, label in DIRS:
                behind = box[0] - dx, box[1] - dy
                dest = box[0] + dx, box[1] + dy
                if behind not in paths or dest not in floor or dest in occupied:
                    continue
                if dest not in live:
                    pruned += 1
                    continue
                new_boxes = tuple(sorted((occupied - {box}) | {dest}))
                lower = assignment(new_boxes)
                if lower >= 100000:
                    continue
                serial += 1
                heapq.heappush(heap, (depth + 1 + lower, -(depth + 1), serial, box, new_boxes, route + paths[behind] + label))
    return {"status": "unsolvable", "expanded_states": len(seen)}


def original_entry():
    text = (ROOT / "level_1.tscn").read_text(encoding="utf-8")
    raw = base64.b64decode(re.search(r'PackedByteArray\("([^"]+)', text).group(1))
    walls = {(x, y) for x, y, *_ in struct.iter_unpack("<hhHHHH", raw[2:])}
    area = {(x, y) for x in range(3, 19) for y in range(1, 11)}
    floor = set(reachable((10, 5), set(), area - walls))
    rows = ["".join(" " if (x, y) in floor else "#" for x in range(20)) for y in range(12)]
    return dict(title="苔石庭院", rows=rows, player=[10, 5], boxes=[[8, 6], [9, 6], [13, 5]], goals=[[9, 8], [10, 8], [11, 8]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=12.0)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    entries = json.loads((ROOT / "campaign_levels.json").read_text(encoding="utf-8"))
    entries.insert(3, original_entry())
    results = []
    for i, entry in enumerate(entries):
        result = solve(entry, args.seconds)
        results.append(dict(level=i + 1, title=entry["title"], **result))
        print(i + 1, {k: v for k, v in result.items() if k != "solution"}, flush=True)
    if args.report:
        args.report.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    raise SystemExit(0 if all(r["status"] == "solved" for r in results) else 1)


if __name__ == "__main__":
    main()
