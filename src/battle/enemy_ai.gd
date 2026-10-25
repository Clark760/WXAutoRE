class_name EnemyAI
extends RefCounted

## 敌方行为（设计文档 6.4）。
## 1. 射程内有我方单位、而且走得过去（走路距离 ≤ 射程 + 2）就打；隔着墙够不着的不停下来，
##    否则远程会停在墙后面一直射，形成死锁（M0 压测 B3 发现）。死士只打挡住自己的人。
## 2. 交战：普通敌人在"警戒范围内出现我方单位"或"刚挨了打"时，沿敌方动态场去找最近的我方单位。
## 3. 否则沿城门场冲城门。前面全被我方单位挡住时，和挡路的人交战（死士也一样）。
## 动态场是按路径算的，所以隔着墙的我方单位不会把敌人引过去贴墙。

const PROVOKED_SECONDS: float = 1.0
const SIDESTEP_COOLDOWN: float = 0.5
## 停下来射击的条件：最近的我方单位走路距离不超过射程 + 这个余量。
const REACH_SLACK: int = 2

const ALLY: int = BattleState.TEAM_ALLY

## 只在 BattleSim.tick() 期间有值（见 BattleSim.tick 的说明）。
var sim: BattleSim
var map: BattleMap
var st: BattleState
var buckets: UnitBuckets
var field: DistanceField
var gate_dist: PackedInt32Array

var cell: PackedInt32Array
var target: PackedInt32Array
var alive: PackedByteArray
var team: PackedByteArray
var state: PackedByteArray
var flags: PackedByteArray
var attack_range: PackedInt32Array
var alert_radius: PackedInt32Array
var occupant: PackedInt32Array
var hp: PackedFloat32Array
var attack_cd: PackedFloat32Array
var move_cd: PackedFloat32Array
var sidestep_cd: PackedFloat32Array
var blocked_time: PackedFloat32Array
var provoked_at: PackedFloat32Array
var neighbors: PackedInt32Array
var cell_type: PackedByteArray


func bind(p_sim: BattleSim) -> void:
	map = p_sim.map
	st = p_sim.st
	buckets = p_sim.buckets
	field = p_sim.enemy_field
	gate_dist = p_sim.gate_field.dist
	cell = st.cell
	target = st.target
	alive = st.alive
	team = st.team
	state = st.state
	flags = st.flags
	attack_range = st.attack_range
	alert_radius = st.alert_radius
	occupant = st.occupant
	hp = st.hp
	attack_cd = st.attack_cd
	move_cd = st.move_cd
	sidestep_cd = st.sidestep_cd
	blocked_time = st.blocked_time
	provoked_at = st.provoked_at
	neighbors = map.neighbors
	cell_type = map.cell_type


func step(i: int) -> void:
	var dt: float = BattleSim.TICK
	attack_cd[i] = maxf(attack_cd[i] - dt, 0.0)
	move_cd[i] = maxf(move_cd[i] - dt, 0.0)
	sidestep_cd[i] = maxf(sidestep_cd[i] - dt, 0.0)

	var c: int = cell[i]
	var rng: int = attack_range[i]
	var suicider: bool = (flags[i] & BattleState.FLAG_SUICIDER) != 0

	# 1. 射程内的我方单位
	var t: int = target[i]
	if t >= 0 and (alive[t] == 0 or map.distance(c, cell[t]) > rng):
		sim.set_target(i, -1)
		t = -1
	# 射程按 Hex 格距判断（隔着自己人也能射）；但只有我方单位走得到时才停下来打
	if t >= 0 and field.dist[c] > rng + REACH_SLACK:
		sim.set_target(i, -1)
		t = -1
	if t < 0 and not suicider and field.dist[c] <= rng + REACH_SLACK:
		t = _pick_in_range(c, rng)
		if t >= 0:
			sim.set_target(i, t)
	if t >= 0:
		state[i] = BattleState.UnitState.ATTACKING
		blocked_time[i] = 0.0
		if attack_cd[i] <= 0.0:
			sim.attack(i, t)
		return

	if move_cd[i] > 0.0:
		state[i] = BattleState.UnitState.MOVING
		return

	# 2. 交战：警戒范围内有我方单位，或刚挨了打
	if not suicider:
		var engage: int = maxi(alert_radius[i], rng)
		var provoked: bool = sim.time - provoked_at[i] <= PROVOKED_SECONDS
		if field.dist[c] <= engage or provoked:
			var n: int = field.downhill(c, occupant, (i + sim.tick_index) % 6)
			if n >= 0:
				_move(i, n)
				state[i] = BattleState.UnitState.MOVING
				blocked_time[i] = 0.0
				return

	# 3. 冲城门
	_advance(i, c)


func _pick_in_range(c: int, rng: int) -> int:
	var best: int = -1
	if rng <= 1:
		var base: int = c * 6
		for k in 6:
			var n: int = neighbors[base + k]
			if n < 0:
				continue
			var u: int = occupant[n]
			if u >= 0 and team[u] == ALLY and (best < 0 or hp[u] < hp[best]):
				best = u
		return best
	var count: int = buckets.gather(ALLY, c, rng)
	var res: PackedInt32Array = buckets.result
	var best_d: int = 1 << 30
	for k in count:
		var u: int = res[k]
		var d: int = map.distance(c, cell[u])
		if d < best_d or (d == best_d and hp[u] < hp[best]):
			best = u
			best_d = d
	return best


## 沿城门场前进一格。所有更近的格子都被我方单位占着 → 和挡路的人交战。
func _advance(i: int, c: int) -> void:
	var cur: int = gate_dist[c]
	var best: int = -1
	var best_g: int = cur
	var side: int = -1
	var blocker: int = -1
	var rot: int = (i + sim.tick_index) % 6
	var base: int = c * 6
	for kk in 6:
		var n: int = neighbors[base + (rot + kk) % 6]
		if n < 0:
			continue
		var g: int = gate_dist[n]
		var o: int = occupant[n]
		if g < cur:
			if o < 0:
				if g < best_g:
					best_g = g
					best = n
			elif team[o] == ALLY and (blocker < 0 or hp[o] < hp[blocker]):
				blocker = o
		elif g == cur and o < 0 and side < 0:
			side = n

	if best >= 0:
		_move(i, best)
		state[i] = BattleState.UnitState.ADVANCING
		blocked_time[i] = 0.0
		return
	if blocker >= 0:
		# 被挡住：和挡路的人交战（相邻格，一定在射程内）
		sim.set_target(i, blocker)
		state[i] = BattleState.UnitState.ATTACKING
		blocked_time[i] = 0.0
		if attack_cd[i] <= 0.0:
			sim.attack(i, blocker)
		return
	if side >= 0 and sidestep_cd[i] <= 0.0:
		_move(i, side)
		sidestep_cd[i] = SIDESTEP_COOLDOWN
		state[i] = BattleState.UnitState.ADVANCING
		blocked_time[i] = 0.0
		return
	# 被自己人堵住，原地等
	blocked_time[i] += BattleSim.TICK
	state[i] = BattleState.UnitState.BLOCKED


func _move(i: int, to: int) -> void:
	sim.move_unit(i, to)
	if cell_type[to] == BattleMap.CellType.GATE:
		sim.on_breach(i)
