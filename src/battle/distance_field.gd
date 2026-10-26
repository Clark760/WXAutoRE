class_name DistanceField
extends RefCounted

## 多源最短路距离场（设计文档 6.3），用桶队列（Dial 算法）求解，复杂度 O(格子数)。
## dist[c] = 站在格子 c 的单位走到"最近起点格"所需的代价。
## 代价：踏进空格 1；踏进被"走路这一方"自己人占着的格子 3（让后面的人绕行）；墙不可通行。
## 起点格本身是目标单位所在的格子，踏进去等于"接触到了"，代价按 1 算。
## 起点可以带初始代价（source_cost）：我方迎击场用它表示威胁，离城门越近的敌人初始代价越小，越优先被拦截。

const UNREACHABLE: int = 1 << 29
const CROWD_COST: int = 3

var dist: PackedInt32Array = PackedInt32Array()

var _map: BattleMap
var _walk: PackedByteArray
var _bucket_head: PackedInt32Array = PackedInt32Array()
var _entry_cell: PackedInt32Array = PackedInt32Array()
var _entry_next: PackedInt32Array = PackedInt32Array()


## walk：使用这张场的一方能站的格子（我方用 walk_ally，敌方用 walk_enemy）。
func setup(map: BattleMap, walk: PackedByteArray) -> void:
	_map = map
	_walk = walk
	dist.resize(map.cell_count)
	dist.fill(UNREACHABLE)
	# 最大代价 = 起点初始代价（不超过格子数）+ 路径代价（不超过 3 × 格子数）
	_bucket_head.resize(map.cell_count * (CROWD_COST + 1) + 8)
	_entry_cell.resize(map.cell_count * 7 + 8)
	_entry_next.resize(map.cell_count * 7 + 8)


## sources：起点格。occupant / unit_team / mover_team 用来判断"自己人占着的格子"；
## mover_team < 0 表示不考虑占格（城门场、敌方场）。limit：超过这个代价就不再展开，省时间。
## source_cost：每个起点的初始代价（可选，不传就都是 0）。
func build(sources: PackedInt32Array, source_count: int, occupant: PackedInt32Array,
		unit_team: PackedByteArray, mover_team: int, limit: int = UNREACHABLE,
		source_cost: PackedInt32Array = PackedInt32Array()) -> void:
	var d_arr: PackedInt32Array = dist
	var head: PackedInt32Array = _bucket_head
	var e_cell: PackedInt32Array = _entry_cell
	var e_next: PackedInt32Array = _entry_next
	var nb: PackedInt32Array = _map.neighbors
	var walk: PackedByteArray = _walk
	var use_crowd: bool = mover_team >= 0
	var has_cost: bool = source_cost.size() >= source_count
	var head_size: int = head.size()
	d_arr.fill(UNREACHABLE)

	var count: int = 0
	var max_d: int = 0
	head[0] = -1
	for s in source_count:
		var c: int = sources[s]
		var d0: int = mini(source_cost[s], head_size - 1) if has_cost else 0
		if d0 >= d_arr[c]:
			continue
		d_arr[c] = d0
		while max_d < d0:
			max_d += 1
			head[max_d] = -1
		e_cell[count] = c
		e_next[count] = head[d0]
		head[d0] = count
		count += 1

	var d: int = 0
	while d <= max_d:
		var e: int = head[d]
		while e != -1:
			var c: int = e_cell[e]
			e = e_next[e]
			if d_arr[c] != d:
				continue
			# 起点格站的是对方单位，不会被算成拥挤
			var nd: int = d + 1
			if use_crowd:
				var o: int = occupant[c]
				if o >= 0 and unit_team[o] == mover_team:
					nd = d + CROWD_COST
			if nd > limit or nd >= head_size:
				continue
			var base: int = c * 6
			for k in 6:
				var n: int = nb[base + k]
				if n < 0 or walk[n] == 0 or nd >= d_arr[n]:
					continue
				d_arr[n] = nd
				while max_d < nd:
					max_d += 1
					head[max_d] = -1
				e_cell[count] = n
				e_next[count] = head[nd]
				head[nd] = count
				count += 1
		d += 1


## 从格子 c 往"更近"的方向走一步，返回最好的空邻格；没有更近的空格返回 -1。
## 平局时从 rot 指定的方向开始找，让不同单位往不同方向分流。
func downhill(c: int, occupant: PackedInt32Array, rot: int) -> int:
	var d_arr: PackedInt32Array = dist
	var nb: PackedInt32Array = _map.neighbors
	var walk: PackedByteArray = _walk
	var best: int = -1
	var best_d: int = d_arr[c]
	var base: int = c * 6
	for kk in 6:
		var n: int = nb[base + (rot + kk) % 6]
		if n < 0 or walk[n] == 0 or occupant[n] >= 0:
			continue
		var dn: int = d_arr[n]
		if dn < best_d:
			best_d = dn
			best = n
	return best
