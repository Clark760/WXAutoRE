class_name UnitBuckets
extends RefCounted

## 空间分桶：按轴向坐标把单位分进 4×4 的桶，用来找"某格附近 K 格内的某方单位"。
## 桶只负责给出候选，是否在范围内一律再用 Hex 距离判断（设计文档 6.1 的唯一距离函数）。
## 每个逻辑帧开头重建一次；帧内单位移动后，候选可能差一格，下一帧自动修正。

const SIZE: int = 4

var result: PackedInt32Array = PackedInt32Array()

var _map: BattleMap
var _st: BattleState
var _bq_count: int = 0
var _br_count: int = 0
var _cell_bucket: PackedInt32Array = PackedInt32Array()
var _start: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _items: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _fill: PackedInt32Array = PackedInt32Array()


func setup(map: BattleMap, st: BattleState) -> void:
	_map = map
	_st = st
	_bq_count = (map.q_max - map.q_min) / SIZE + 1
	_br_count = (map.height - 1) / SIZE + 1
	var bucket_count: int = _bq_count * _br_count
	_cell_bucket.resize(map.cell_count)
	for c in map.cell_count:
		var bq: int = (map.cell_q[c] - map.q_min) / SIZE
		var br: int = map.cell_r[c] / SIZE
		_cell_bucket[c] = br * _bq_count + bq
	for t in 2:
		_start[t].resize(bucket_count + 1)
		_items[t].resize(st.capacity)
	_fill.resize(bucket_count)
	result.resize(st.capacity)


func rebuild() -> void:
	var st: BattleState = _st
	var cell: PackedInt32Array = st.cell
	var alive: PackedByteArray = st.alive
	var team: PackedByteArray = st.team
	var cb: PackedInt32Array = _cell_bucket
	var bucket_count: int = _fill.size()
	for t in 2:
		var start: PackedInt32Array = _start[t]
		var items: PackedInt32Array = _items[t]
		var fill: PackedInt32Array = _fill
		fill.fill(0)
		for i in st.unit_count:
			if alive[i] == 1 and team[i] == t:
				fill[cb[cell[i]]] += 1
		var acc: int = 0
		for b in bucket_count:
			start[b] = acc
			acc += fill[b]
			fill[b] = start[b]
		start[bucket_count] = acc
		for i in st.unit_count:
			if alive[i] == 1 and team[i] == t:
				var b: int = cb[cell[i]]
				items[fill[b]] = i
				fill[b] += 1


## 把 team 方、距离 center 不超过 radius 格的单位放进 result，返回个数。
func gather(team: int, center: int, radius: int) -> int:
	var map: BattleMap = _map
	var cq: int = map.cell_q[center]
	var cr: int = map.cell_r[center]
	var bq0: int = clampi((cq - radius - map.q_min) / SIZE, 0, _bq_count - 1)
	var bq1: int = clampi((cq + radius - map.q_min) / SIZE, 0, _bq_count - 1)
	var br0: int = clampi((cr - radius) / SIZE, 0, _br_count - 1)
	var br1: int = clampi((cr + radius) / SIZE, 0, _br_count - 1)
	var start: PackedInt32Array = _start[team]
	var items: PackedInt32Array = _items[team]
	var cell: PackedInt32Array = _st.cell
	var qs: PackedInt32Array = map.cell_q
	var rs: PackedInt32Array = map.cell_r
	var out: PackedInt32Array = result
	var n: int = 0
	for br in range(br0, br1 + 1):
		var row_base: int = br * _bq_count
		for bq in range(bq0, bq1 + 1):
			var b: int = row_base + bq
			for k in range(start[b], start[b + 1]):
				var u: int = items[k]
				var uc: int = cell[u]
				if Hex.distance_qr(qs[uc], rs[uc], cq, cr) <= radius:
					out[n] = u
					n += 1
	return n
