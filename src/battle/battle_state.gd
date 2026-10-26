class_name BattleState
extends RefCounted

## 战斗状态：每个单位一个下标 i，每个字段一个 Packed 数组（设计文档 9.3）。
## 这里只放数据和最基础的读写；规则在 BattleSim 和各 AI 模块里。
## Packed 数组在 Godot 4.7 里按引用共享，所以各模块可以缓存同一份数组的引用直接读写，
## 但数组只能在 setup() 里分配一次，之后不能整体替换，否则缓存会失效。

const TEAM_ALLY: int = 0
const TEAM_ENEMY: int = 1

const FLAG_SUICIDER: int = 1
const FLAG_RANGED: int = 2
const FLAG_HERO: int = 4

enum UnitState { GUARD, MOVING, ATTACKING, BLOCKED, RETURNING, ADVANCING, DEAD }

## 我方行为模式（设计文档 6.5）：迎击 = 主动寻敌、优先拦截离城门近的；驻守 = 只在防区内迎敌。
const MODE_INTERCEPT: int = 0
const MODE_GUARD: int = 1

## 0 = 外功（用 def_ext 减免），1 = 内功（用 def_int 减免）
const DAMAGE_EXTERNAL: int = 0
const DAMAGE_INTERNAL: int = 1

var map: BattleMap
var defs: Array[UnitDef] = []
var capacity: int = 0
var unit_count: int = 0

var team: PackedByteArray = PackedByteArray()
var def_index: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()
var flags: PackedByteArray = PackedByteArray()
var state: PackedByteArray = PackedByteArray()
## 我方行为模式，见 MODE_*；敌方不用。
var mode: PackedByteArray = PackedByteArray()
var damage_type: PackedByteArray = PackedByteArray()

var cell: PackedInt32Array = PackedInt32Array()
var home: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()
var attackers: PackedInt32Array = PackedInt32Array()
var last_attacker: PackedInt32Array = PackedInt32Array()
var attack_range: PackedInt32Array = PackedInt32Array()
var guard_radius: PackedInt32Array = PackedInt32Array()
var alert_radius: PackedInt32Array = PackedInt32Array()

var hp: PackedFloat32Array = PackedFloat32Array()
var hp_max: PackedFloat32Array = PackedFloat32Array()
var offense: PackedFloat32Array = PackedFloat32Array()
var def_ext: PackedFloat32Array = PackedFloat32Array()
var def_int: PackedFloat32Array = PackedFloat32Array()
var attack_interval: PackedFloat32Array = PackedFloat32Array()
var move_interval: PackedFloat32Array = PackedFloat32Array()
var crit: PackedFloat32Array = PackedFloat32Array()

## 计时器（秒）
var attack_cd: PackedFloat32Array = PackedFloat32Array()
var move_cd: PackedFloat32Array = PackedFloat32Array()
var retarget_cd: PackedFloat32Array = PackedFloat32Array()
var sidestep_cd: PackedFloat32Array = PackedFloat32Array()
var blocked_time: PackedFloat32Array = PackedFloat32Array()
var provoked_at: PackedFloat32Array = PackedFloat32Array()
## 远程开火延迟统计：-1 = 射程内没有敌人；>=0 = 敌人进入射程的时刻；-2 = 这一轮已经开过火
var range_since: PackedFloat32Array = PackedFloat32Array()

## 表现层插值用：从哪格走过来、什么时候开始走、走多久
var move_from: PackedInt32Array = PackedInt32Array()
var move_start: PackedFloat32Array = PackedFloat32Array()
var move_dur: PackedFloat32Array = PackedFloat32Array()
var hit_time: PackedFloat32Array = PackedFloat32Array()

## 每个格子上站着的单位下标，-1 表示空格。一个单位的位置只存这一份（加上 cell[i]）。
var occupant: PackedInt32Array = PackedInt32Array()

var alive_count: PackedInt32Array = PackedInt32Array([0, 0])


func setup(p_map: BattleMap, p_capacity: int) -> void:
	map = p_map
	capacity = p_capacity
	unit_count = 0
	# 逐个 resize：用 as 转型会复制出新数组，原数组不会变
	team.resize(capacity)
	alive.resize(capacity)
	flags.resize(capacity)
	state.resize(capacity)
	mode.resize(capacity)
	damage_type.resize(capacity)
	def_index.resize(capacity)
	cell.resize(capacity)
	home.resize(capacity)
	target.resize(capacity)
	attackers.resize(capacity)
	last_attacker.resize(capacity)
	attack_range.resize(capacity)
	guard_radius.resize(capacity)
	alert_radius.resize(capacity)
	move_from.resize(capacity)
	hp.resize(capacity)
	hp_max.resize(capacity)
	offense.resize(capacity)
	def_ext.resize(capacity)
	def_int.resize(capacity)
	attack_interval.resize(capacity)
	move_interval.resize(capacity)
	crit.resize(capacity)
	attack_cd.resize(capacity)
	move_cd.resize(capacity)
	retarget_cd.resize(capacity)
	sidestep_cd.resize(capacity)
	blocked_time.resize(capacity)
	provoked_at.resize(capacity)
	range_since.resize(capacity)
	move_start.resize(capacity)
	move_dur.resize(capacity)
	hit_time.resize(capacity)
	occupant.resize(map.cell_count)
	occupant.fill(-1)
	alive_count[0] = 0
	alive_count[1] = 0


func def_id(d: UnitDef) -> int:
	var idx: int = defs.find(d)
	if idx < 0:
		defs.append(d)
		idx = defs.size() - 1
	return idx


## 放一个单位到指定格子。格子必须是该阵营能站的空格，否则返回 -1。
func add_unit(d: UnitDef, p_team: int, p_cell: int) -> int:
	if unit_count >= capacity:
		push_error("战斗单位超出容量 %d" % capacity)
		return -1
	var walk: PackedByteArray = map.walk_ally if p_team == TEAM_ALLY else map.walk_enemy
	if p_cell < 0 or p_cell >= map.cell_count or walk[p_cell] == 0 or occupant[p_cell] >= 0:
		push_error("单位 %s 不能放在格子 %d" % [d.id, p_cell])
		return -1

	var i: int = unit_count
	unit_count += 1
	team[i] = p_team
	def_index[i] = def_id(d)
	alive[i] = 1
	var f: int = 0
	if d.suicider:
		f |= FLAG_SUICIDER
	if d.attack_range >= 2:
		f |= FLAG_RANGED
	if d.is_hero:
		f |= FLAG_HERO
	flags[i] = f
	state[i] = UnitState.GUARD if p_team == TEAM_ALLY else UnitState.ADVANCING
	mode[i] = MODE_INTERCEPT
	# 普攻用两种攻击里较高的一种
	if d.atk >= d.iat:
		damage_type[i] = DAMAGE_EXTERNAL
		offense[i] = d.atk
	else:
		damage_type[i] = DAMAGE_INTERNAL
		offense[i] = d.iat

	cell[i] = p_cell
	home[i] = p_cell
	target[i] = -1
	attackers[i] = 0
	last_attacker[i] = -1
	attack_range[i] = maxi(1, d.attack_range)
	guard_radius[i] = d.guard_radius
	alert_radius[i] = d.alert_radius

	hp[i] = d.hp
	hp_max[i] = d.hp
	def_ext[i] = d.def_ext
	def_int[i] = d.def_int
	attack_interval[i] = d.attack_interval
	move_interval[i] = d.move_interval
	crit[i] = d.crit

	attack_cd[i] = 0.0
	move_cd[i] = 0.0
	retarget_cd[i] = 0.0
	sidestep_cd[i] = 0.0
	blocked_time[i] = 0.0
	provoked_at[i] = -100.0
	range_since[i] = -1.0

	move_from[i] = p_cell
	move_start[i] = -100.0
	move_dur[i] = d.move_interval
	hit_time[i] = -100.0

	occupant[p_cell] = i
	alive_count[p_team] += 1
	return i


func unit_def(i: int) -> UnitDef:
	return defs[def_index[i]]
