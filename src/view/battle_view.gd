class_name BattleView
extends Node2D

## 战场表现层（设计文档 9.5）：只读 BattleSim 的状态，不改任何数据。
## - 地图：所有格子画成六边形，画一次。
## - 单位：每种单位一个 MultiMeshInstance2D，每帧用 multimesh_set_buffer 一次提交。
## - 插值：按"从哪格到哪格、什么时候开始、走多久"线性插值，移动是连续的。
## - 调试叠加（F3）：单位按状态上色，被堵超过 2 秒标红，我方防区画圈。

const HEX_SIZE: float = 16.0
const UNIT_SCALE: float = 1.55
const HERO_SCALE: float = 2.1
const HIT_FLASH_SECONDS: float = 0.15
## 每个实例 12 个浮点：Transform2D 8 个（x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y）+ 颜色 4 个
const FLOATS_PER_INSTANCE: int = 12

const STATE_COLORS: Array[Color] = [
	Color("9a9a9a"),  # 驻守
	Color("4f86d6"),  # 移动
	Color("3bb273"),  # 攻击
	Color("e39b2d"),  # 被堵
	Color("57c4d8"),  # 回位
	Color("5a4a3a"),  # 推进
	Color(0, 0, 0, 0),
]
const IDLE_COLOR: Color = Color("e0403a")

var sim: BattleSim
var overlay: bool = false:
	set(value):
		overlay = value
		if _map_layer != null:
			_map_layer.overlay = value
			_map_layer.queue_redraw()

var _map_layer: _MapLayer
var _atlas: GlyphAtlas
var _pixel: PackedVector2Array = PackedVector2Array()
var _groups: Array[Dictionary] = []
var _hp_mm: MultiMesh
var _hp_buffer: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_map_layer = _MapLayer.new()
	add_child(_map_layer)
	_atlas = GlyphAtlas.new()
	add_child(_atlas)
	_atlas.textures_ready.connect(_apply_textures)


func bind(p_sim: BattleSim) -> void:
	for g in _groups:
		(g["node"] as Node).queue_free()
	_groups.clear()
	if _hp_mm != null:
		_hp_mm = null
		get_node("HpBars").queue_free()
	sim = p_sim
	var map: BattleMap = sim.map
	_pixel.resize(map.cell_count)
	for c in map.cell_count:
		_pixel[c] = map.to_pixel(c, HEX_SIZE)
	_map_layer.setup(sim, _pixel)

	var st: BattleState = sim.st
	for d in st.defs.size():
		var indices := PackedInt32Array()
		for i in st.unit_count:
			if st.def_index[i] == d:
				indices.append(i)
		var node := MultiMeshInstance2D.new()
		node.multimesh = _make_multimesh(indices.size())
		node.texture = _atlas.texture_for(st.defs[d])
		add_child(node)
		var buffer := PackedFloat32Array()
		buffer.resize(indices.size() * FLOATS_PER_INSTANCE)
		_groups.append({"def": st.defs[d], "node": node, "indices": indices, "buffer": buffer})

	var hp_node := MultiMeshInstance2D.new()
	hp_node.name = "HpBars"
	_hp_mm = _make_multimesh(st.unit_count)
	hp_node.multimesh = _hp_mm
	add_child(hp_node)
	_hp_buffer.resize(st.unit_count * FLOATS_PER_INSTANCE)
	_atlas.build(st.defs)


func map_size() -> Vector2:
	var max_p := Vector2.ZERO
	for p in _pixel:
		max_p = max_p.max(p)
	return max_p + Vector2(HEX_SIZE, HEX_SIZE) * 2.0


## render_time：逻辑时间 + 累加器里还没走完的那一截。
func update_frame(render_time: float) -> void:
	if sim == null:
		return
	var st: BattleState = sim.st
	var alive: PackedByteArray = st.alive
	var cell: PackedInt32Array = st.cell
	var move_from: PackedInt32Array = st.move_from
	var move_start: PackedFloat32Array = st.move_start
	var move_dur: PackedFloat32Array = st.move_dur
	var hit_time: PackedFloat32Array = st.hit_time
	var state: PackedByteArray = st.state
	var blocked_time: PackedFloat32Array = st.blocked_time
	var hp: PackedFloat32Array = st.hp
	var hp_max: PackedFloat32Array = st.hp_max
	var team: PackedByteArray = st.team
	var px: PackedVector2Array = _pixel
	var hb: PackedFloat32Array = _hp_buffer

	for g in _groups:
		var d: UnitDef = g["def"]
		var indices: PackedInt32Array = g["indices"]
		var buf: PackedFloat32Array = g["buffer"]
		var size: float = HEX_SIZE * (HERO_SCALE if d.is_hero else UNIT_SCALE)
		for k in indices.size():
			var i: int = indices[k]
			var o: int = k * FLOATS_PER_INSTANCE
			if alive[i] == 0:
				_write(buf, o, Vector2.ZERO, 0.0, Color(0, 0, 0, 0))
				_write(hb, i * FLOATS_PER_INSTANCE, Vector2.ZERO, 0.0, Color(0, 0, 0, 0))
				continue
			var t: float = clampf((render_time - move_start[i]) / maxf(move_dur[i], 0.001), 0.0, 1.0)
			var pos: Vector2 = px[move_from[i]].lerp(px[cell[i]], t)
			var color := Color.WHITE
			if overlay:
				color = STATE_COLORS[state[i]]
				if state[i] == BattleState.UnitState.BLOCKED and blocked_time[i] >= 2.0:
					color = IDLE_COLOR
			elif render_time - hit_time[i] < HIT_FLASH_SECONDS:
				color = Color(1.6, 1.4, 1.4)
			_write(buf, o, pos, size, color)
			# 血条：只画受过伤的
			var ratio: float = hp[i] / hp_max[i]
			if ratio < 0.999:
				var bar_color: Color = Color("3bb273") if team[i] == BattleState.TEAM_ALLY else Color("d0453c")
				var bw: float = size * 0.9
				var bo: int = i * FLOATS_PER_INSTANCE
				hb[bo] = bw * ratio
				hb[bo + 1] = 0.0
				hb[bo + 2] = 0.0
				hb[bo + 3] = pos.x - bw * (1.0 - ratio) * 0.5
				hb[bo + 4] = 0.0
				hb[bo + 5] = 3.0
				hb[bo + 6] = 0.0
				hb[bo + 7] = pos.y - size * 0.62
				hb[bo + 8] = bar_color.r
				hb[bo + 9] = bar_color.g
				hb[bo + 10] = bar_color.b
				hb[bo + 11] = 1.0
			else:
				_write(hb, i * FLOATS_PER_INSTANCE, Vector2.ZERO, 0.0, Color(0, 0, 0, 0))
		RenderingServer.multimesh_set_buffer((g["node"] as MultiMeshInstance2D).multimesh.get_rid(), buf)
	RenderingServer.multimesh_set_buffer(_hp_mm.get_rid(), hb)
	if overlay and Engine.get_process_frames() % 15 == 0:
		_map_layer.queue_redraw()


static func _write(buf: PackedFloat32Array, o: int, pos: Vector2, size: float, color: Color) -> void:
	buf[o] = size
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = pos.x
	buf[o + 4] = 0.0
	# QuadMesh 的 y 轴朝上，2D 里要翻一下贴图才是正的
	buf[o + 5] = -size
	buf[o + 6] = 0.0
	buf[o + 7] = pos.y
	buf[o + 8] = color.r
	buf[o + 9] = color.g
	buf[o + 10] = color.b
	buf[o + 11] = color.a


func _make_multimesh(count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = count
	return mm


func _apply_textures() -> void:
	for g in _groups:
		(g["node"] as MultiMeshInstance2D).texture = _atlas.texture_for(g["def"])


class _MapLayer:
	extends Node2D

	const COLORS: Dictionary = {
		BattleMap.CellType.FLOOR: Color("ece2cc"),
		BattleMap.CellType.WALL: Color("3b342c"),
		BattleMap.CellType.SPAWN: Color("e6cfc4"),
		BattleMap.CellType.DEPLOY: Color("d6e2cf"),
		BattleMap.CellType.GATE: Color("a8322d"),
	}

	var overlay: bool = false
	var _sim: BattleSim
	var _pixel: PackedVector2Array
	var _corners: PackedVector2Array = PackedVector2Array()

	func setup(p_sim: BattleSim, pixel: PackedVector2Array) -> void:
		_sim = p_sim
		_pixel = pixel
		_corners.resize(6)
		var r: float = BattleView.HEX_SIZE * 0.96
		for k in 6:
			var a: float = deg_to_rad(60.0 * k - 30.0)
			_corners[k] = Vector2(cos(a), sin(a)) * r
		queue_redraw()

	func _draw() -> void:
		if _sim == null:
			return
		var map: BattleMap = _sim.map
		var poly := PackedVector2Array()
		poly.resize(6)
		for c in map.cell_count:
			var p: Vector2 = _pixel[c]
			for k in 6:
				poly[k] = p + _corners[k]
			draw_colored_polygon(poly, COLORS[map.cell_type[c]])
		if not overlay:
			return
		# 调试：我方防区
		var st: BattleState = _sim.st
		var step: float = BattleView.HEX_SIZE * Hex.SQRT3
		for i in st.unit_count:
			if st.alive[i] == 1 and st.team[i] == BattleState.TEAM_ALLY:
				var radius: float = (st.guard_radius[i] + 0.5) * step
				draw_arc(_pixel[st.home[i]], radius, 0.0, TAU, 32, Color(0.2, 0.5, 0.9, 0.25), 1.0)
