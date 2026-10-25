# WXAuto 旧项目审查（2026-10-25）

> 审查对象：<https://github.com/Clark760/WXAuto>，克隆在 `C:\Code\WXAuto`，最后一次提交 2026-04-09。
> 文中路径都相对 WXAuto 仓库根目录，`文件:行号` 指 HEAD 版本。
> 实测环境：本机 Godot 4.7.2（项目写的是 4.6），全部用 headless 模式跑。

---

## 0. 结论

这个项目卡住，不是因为哪个 bug 修不好，而是下面三件事叠在一起：

1. **一直没有能玩的核心循环。** 现在的 HEAD 里一个关卡都没有，等级表也没有；400 个角色全都没有初始功法、没有特性、没有图片，名字一部分是占位（"坦克白14"），一部分是历史人物（吕布、王昭君、甘宁）。没有能玩的东西，就没法判断"好不好玩"，于是只能继续往上加系统。
2. **规模目标压垮了技术方案。** 文档定的是 50v200、250 单位 60fps、逻辑帧 <8ms。实测 250 单位时**逻辑帧平均 49.6ms、峰值 159ms**，而且是在不渲染的 headless 模式下。这不是调几个参数能解决的。
3. **代码量远超一个人能维护的范围。** 3 周内累计新增 20.4 万行、删除 9.7 万行，现在剩 5.1 万行 GDScript（生产代码 4 万行、2283 个函数）。规则引擎（约 30 个 trigger、70 多个 effect op，外加一套 tag 联动查询语法）比游戏内容长得还快——基础数据只用了其中 2 个 trigger、35 个 op，tag 联动一次没用。一次大重构是"为了过行数门禁"做的机械拆分，改任何东西都要穿过好几层 support/service/facade。

一句话：**引擎和工具链做成了 60 分，游戏本身还是 0 分**，而且引擎是为一个从没验证过的规模目标设计的。

---

## 1. 基本盘（全部实测）

| 项目 | 数据 |
|---|---|
| 提交 | 34 次，2026-03-19 ～ 04-09 |
| 节奏 | 03-19 ～ 03-22 四天"完成" M0～M5；03-23 之后都在删机制、重构、调帧率、补数据 |
| 累计改动 | 新增 204,158 行，删除 97,159 行 |
| 现存代码 | 172 个 .gd，共 51,330 行（测试 36 个，10,926 行） |
| 数据（mods/base） | 角色 400、功法 162、装备 90、Buff 61、Tag 72、地形 20；**关卡 0、等级表 0** |
| 美术 | 只有 `assets/ui/ink/` 下 9 个水墨 UI 的 SVG；角色精灵图、立绘一张都没有（400 个 `sprite_path` 全部指向不存在的文件） |
| 文档 | 现存 8 份，共 255KB；git 历史里另有约 30 份写完又删掉的设计/修正文档 |
| 测试 | 36 个 headless 测试**全部通过**（Godot 4.7.2） |
| 压测（`m5_battlefield_stress_50v200_probe`） | 50v200，逻辑帧平均 **49.6ms**、峰值 **158.8ms**；移动成功率 41.6%，**58.4% 的移动被堵**；流场重建 37ms/次；8 秒后己方剩 20/50、敌方剩 191/200 |
| 架构门禁（`tools/architecture_guard.ps1 -ReportOnly`） | 9 个文件超过 600 行（1 个超过 900），剩 49 处动态 `call()` |

---

## 2. 做得好的地方（重来时值得保留）

1. **测试和压测的意识很强。** 36 个 headless 测试能一键跑完，而且全绿；50v200 压测探针会按分段（`combat_logic_tick`、`combat_move_phase`、`combat_target_pick`……）输出耗时和诊断结论。个人项目很少做到这一步，重来时这套思路可以直接沿用。
2. **自带校验链。** `tools/check.ps1` 把 headless 启动、JSON 语法、架构门禁、泄漏检测串成一键检查，还有基线和豁免文件，思路是对的。
3. **数据外置 + Mod 化方向正确。** 本体数据已经搬进 `mods/base`，支持 `res://mods` 和 `user://mods` 两个根、按 `load_order` 覆盖、资源路径覆盖；有 JSON Schema，还有一个独立的数据编辑器（`tools/mod_data_editor`，Python + JS 约 5000 行）。
4. **依赖装配是显式的。** `scripts/infra/app_root.gd` + `service_registry.gd` 统一创建、注入服务，没有一堆 AutoLoad 全局单例，`_get_root_node` 这类到处找根节点的写法已经清零。
5. **面向 Mod 作者的文档写得像产品文档。** `doc/模组触发器与特效手册.md` 每个 trigger/op 都有参数表、最小示例、注意事项；`doc/角色属性调查.md` 把完整的伤害公式链列了出来。即使代码不要了，这两份也能当"需求库"。
6. **愿意删。** 联动、升星、红色品质、Boss 机制、AI 生成的兼容字段都删过，说明有收敛意识。问题在于删了之后没有补上替代的玩法（见 3.1）。
7. **水墨 UI 风格有方向。** 调色板、SVG 边框模板、Theme 构建器（`scripts/ui/ink_theme_builder.gd`）是一套能复用的视觉规范。

> 战斗和技能效果子系统里做得好的点，见第 4.3、4.4 节。

---

## 3. 产品与设计层的问题

### 3.1 没有可玩闭环 【严重】

- 2026-03-31 的提交"删除测试数据"把 `mods/base/data/stages/*` 和 `mods/base/data/levels/base.json` 一起删了，之后再没补回来。现在：
  - 主菜单的章节列表是空的（`scripts/main/main_scene.gd:105` 起，没有序列就只显示空提示）；
  - 进入战场后 `start_first_stage()` 返回 false，界面显示 `"Phase 2 提示：未检测到关卡配置，沿用基础战场模式。"`（`scripts/app/battlefield/battlefield_coordinator.gd:377`）——重构阶段的过程文案直接出现在玩家界面上；
  - 门派等级表没了，经济系统**静默**回退到写死的 `DEFAULT_LEVEL_ROWS`（`scripts/domain/economy/economy_progression_service.gd:17`），没有任何报错。
- 总纲 M5 写着"完整单局流程可玩（招募→布阵→战斗→结算→下一关）"，但"配置首批关卡 20+"这一项从来没勾上。**整个项目从来没有一个能从头玩到尾的版本。**

### 3.2 内容是生成的占位，武侠身份几乎不存在 【严重】

- 400 个角色：`initial_gongfa` 全部为空，没有 `traits`；职业是坦克/战士/射手/刺客/法师/牧师（MOBA 六职业），不是总纲写的先锋/剑客/刺客/射手/术师/医者/统领；角色上没有门派归属。
- 名字有三种来源混在一起：武侠风（张盾、黄大锤）、占位（坦克白14、坦克橙12、射手紫12）、历史人物（吕布、典韦、王昭君、甘宁、尉迟恭、养由基——"养由基圣"还重名了两次）。
- 功法名是模板拼出来的：`武当·太极绵化·绝学内功·第四式`，描述是英文的 `武当 Taiji line gongfa.`，数值是 0.88、29.4、4.45 这种生成器风格的小数。
- `tmp/generated_gongfa*/` 下的生成中间文件被提交进仓库，里面的中文已经变成 `????`。

结果是：系统支持 70 种效果，但玩家能看到的角色只是一堆"品质 × 职业"的属性块，彼此没有区别。

### 3.3 核心卖点删掉后没有替代 【严重】

- 总纲 3.4 把"功法联动（同门 / 五行共鸣 / 武技连携 / 阵法联动）"定为**核心差异化机制**，03-23 被整体删除，换成通用的 tag 计数（`tag_linkage_branch`）。通用 tag 计数是一个**引擎能力**，不是一个**玩法**：玩家能看懂的"三才剑阵""木生火"之类的组合，现在一个都没有。
- 03-30 删了升星和"同类单位只能上一个"。自走棋最核心的几个决策——凑羁绊、三合一升星、存钱吃利息——现在一个都不在：利息没实现（代码里搜不到 interest/利息），装备合成没实现（搜不到 recipe/合成），升星删了，联动删了。剩下的循环是"买属性块、往槽里塞功法"。

### 3.4 规模目标和玩法互相冲突 【高】

- 自走棋的乐趣在于"少量棋子的取舍"；50 个己方单位 + 200 个敌人会把每个决策的价值稀释掉，玩家也看不清战场上发生了什么。总纲第八节自己的风险表就写了"大规模战斗可读性差 / 看不懂打了什么"，但没有给出验证方式。
- 压测里 58% 的移动被堵，说明 250 个单位挤在六角格上，大部分时间在互相卡位，而不是在"武功交锋"。
- 这个目标同时是性能问题的根源（见 4.3）。**规模目标应该先用一个最小原型证明"好玩 + 跑得动"，而不是一开始就写进架构。**

---

## 4. 代码与架构层的问题

### 4.1 数据全靠字符串约定，错误被静默吞掉 【高】

在 4 万行生产代码里（不含测试）：

| 写法 | 次数 |
|---|---|
| `.get("某个键")` 字典取字段 | 2,092 |
| 出现 `Dictionary` | 2,364 |
| `Variant` 类型标注 | 741 |
| `has_method(...)` 鸭子类型 | 222 |
| `== null` / `!= null` 判断 | 1,525 |
| `is_instance_valid(...)` | 397 |
| 名字里带 fallback | 373 |
| `push_warning` / `push_error` | **只有 30** |

- 技能、效果、事件、上下文、统计全部是无类型 Dictionary 在各层之间传递，字段名错了不会报错，只会走到某个 fallback 分支，安静地给出错误结果。
- 运行时不按 JSON Schema 校验数据（`scripts/data/data_manager.gd:196` 直接跳过 `_schema`），校验散落在各个 `normalize_*` 函数里，失败就回退默认值。关卡和等级表整个缺失时系统照样运行（3.1），就是这种风格的直接后果。
- 总纲 7.1 承诺"全面使用类型标注"，但关键边界恰恰没有类型：`ServiceRegistry` 里所有服务都声明成 `Node`；coordinator 的 `_refs: Node`、`_state: RefCounted` 全靠动态属性访问；5 个 support 成员变量是无类型的 `= null`（`battlefield_coordinator.gd:63-67`）。

### 4.2 "为过门禁而拆分"：行数降了，耦合没降 【高】

- 编码规范要求单文件 ≤600/900 行、函数 ≤80 行、中文注释 ≥10%、80% 的函数要有注释，并由 `architecture_guard.ps1` 强制执行。结果：
  - **用继承链拼一个类**：`battlefield_hud_catalog_support` → `hud_text_support` → `hud_effect_formatter_support` → `hud_support`，四层 `extends "res://..."`，合计 2161 行，本质上还是一个类，只是切成了四个文件。
  - **support 反向回调宿主**：`battlefield_world_controller.gd` 里有 35 处对宿主/协作者（`_owner.`、`_coordinator.`、`_presenter.`、`_controller.`）的回调，`battlefield_coordinator_economy_support.gd` 有 23 处这类回调、80 处 `_refs.`。被删掉的 `doc/项目代码重构方案.md` 自己就诊断过"把运行时动态装配当作模块化，实际上只是把耦合转移成了隐藏耦合"——重构完成后这个问题依然存在。
  - **凑数注释**：117 条 `# 获取 get event bus`、`# 处理 ready`、`# 收集 collect sequence entries` 这种"中文动词 + 英文函数名"的注释；`battlefield_hud_support.gd:3-6` 同一个函数上方有两段意思完全相同的注释。
- 门禁让指标好看了，但没让代码更好读，反而增加了文件数和跳转次数。

### 4.3 战斗与性能子系统 【高】

**总体判断**：大方向是对的——10Hz 定步长逻辑帧、占格表作为逻辑坐标的唯一依据、每队共享一张流场、单位走对象池。问题出在实现形态：`CombatManager`（788 行）其实是一个装着约 45 个私有字段的"状态袋"，周围的 service 自己不持有状态，靠直接读写 `manager._私有字段` 干活（约 470 处）；下面还有一层"兼容壳"，再下面是自称"纯规则"的 domain 层，但 domain 里仍有 64 处 `runtime_port._xxx` 回调 manager 的私有方法。**瓶颈主要不在算法复杂度，而在常数开销**：每个单位每个 tick 要穿过 4～5 层动态调用、字符串反射、字典拷贝和逐单位信号。

**卡顿的成因拆解（来自压测探针，250 单位，headless 不渲染）**

| 每个逻辑帧里 | 单次耗时 | 每帧调用次数 | 每帧合计 |
|---|---|---|---|
| 寻敌 `combat_target_pick` | 53µs | 约 211 | 约 11.2ms |
| 移动 `combat_move_phase` | 133µs | 约 89 | 约 11.8ms |
| 攻击 `combat_attack_execute` | 83µs | 约 94 | 约 7.8ms |
| 组件 tick | 4.5µs | 约 235 | 约 1.1ms |
| 未单独计时（信号、增强系统事件处理等，推测） | — | — | 约 13ms |
| **单位逻辑合计** | | | **44.9ms**（整帧 49.6ms 的 90%） |

- 渲染不是主因：不渲染的 headless 模式下就已经 50ms；世界、HUD、VFX 的 `_process` 加起来每帧不到 2.5ms。
- 单个算法也不是主因：流场重建 37ms/次虽然慢，但 80 帧里只发生 3 次。
- **主因是每个单位每次动作都太重**：一次寻敌 53µs、一次移动 133µs，开销来自层层动态调用、字符串取字段、字典拷贝和逐单位信号，而不是算法本身。
- **调度方式把它放大成卡顿**：整个逻辑帧在一个渲染帧里算完，没有分帧也没有插值。每 0.1 秒就有一帧要多花 50ms（峰值 159ms），所以平均帧率看着有 83，手感却是一顿一顿的。攻击帧还要额外做预扫描、跟随锚点和流场，攻击帧与移动帧一重一轻，节奏更不均匀。

**总纲性能承诺逐项核对**

| 承诺 | 实际 | 证据 |
|---|---|---|
| 10fps 逻辑帧 | 有。但攻击、移动隔帧交替，各自实际只有 5Hz | `scripts/combat/combat_runtime_service.gd:22-38, 113-116` |
| 渲染帧插值 | **没有**。每走一格起一个约 0.075s 的 Tween 跳格 | `scripts/combat/combat_movement_service.gd:641-658`，`scripts/unit/unit_base.gd:314-335` |
| 空间哈希 | 实现干净，但查询半径 360px，在 32×32、格子 16px 的棋盘上几乎覆盖全盘，**等于全量遍历**；寻敌主路径其实走的是占格表 | `scripts/board/spatial_hash.gd`，`scenes/battle/battlefield_scene.tscn:38-40` |
| 分组 AI | 半实现：每队只算一个"离己方质心最近的敌人"当集火目标 | `scripts/domain/combat/combat_targeting.gd:24-50` |
| LOD 行为 | **没有**。只有按总人数（120/180/220/320）的全局降级 | `scripts/combat/combat_manager.gd:472-507` |
| 流场寻路 | 有，但 Dijkstra 用线性扫描找最小值（O(V²)），每次重建都清空 1024 格邻接缓存；算出来的方向图从没被用过 | `scripts/domain/combat/flow_field.gd:27-32, 46, 60-69, 88-136` |
| MultiMesh 批量渲染 | **名义上有**：只画一层半透明的辅助标记点，单位数 ≥180 时直接关掉；单位本体是每个一个 Node2D 自己 `_draw` | `scripts/unit/unit_multimesh_renderer.gd:14, 51-62` |
| 对象池 | 有，而且在用（单位、飘字、粒子），开战前分批预热 | `scripts/core/object_pool.gd` |
| Draw Call < 100 | 推测达不到：每个单位依次画"贴图 + 名字文字"，两种纹理交替，无法合批 | `scripts/unit/unit_visual_root.gd:40-56` |

**已确认的两个逻辑 bug**（我逐行核对过）

1. **流场周期刷新在某些人数区间永远不触发。** 逻辑帧计数从 1 开始，攻击帧永远是奇数帧，而流场刷新只在攻击帧检查 `_logic_frame % interval == 0`（`combat_runtime_service.gd:113-116` 交替相位，`:162-165` 刷新条件）。基础间隔是 5，人数 120～219 时翻倍成 10、≥320 时变成 20（`combat_manager.gd:472-481`）——这两档的倍数全是偶数，**流场永远不会周期刷新**，单位一直在追一张过期的流场。（250 人那档间隔是 15，所以压测里能看到 3 次重建，正好对应第 15、45、75 帧。）反过来，只要有击退/恐惧把 `_flow_force_rebuild` 置位，又会每 0.2 秒全量重建一次。
2. **两套六角格距离公式。** 战场用的是"奇行偏移"坐标（`hex_grid.gd:37`，`use_staggered_square_layout = true`），`hex_grid.gd:203` 的 `get_cell_distance()` 会先转成轴向坐标再算距离，这是对的；但 `scripts/domain/combat/combat_targeting.gd:395` 的 `_hex_cell_distance()` 和 `scripts/domain/combat/combat_pathfinding.gd:506` 的 `_axial_distance()` 直接把偏移坐标当轴向坐标代入公式。射程 ≤4 的寻敌扫描、集火距离、跟随锚点都用的是后者。推断后果：远程单位在移动阶段误以为"目标已在射程内"而原地不动，到攻击阶段用正确距离判定又打不到，于是卡住。**这很可能就是"棋子重叠 / 寻路错误"写了 5 份修正文档还反复出现的根因之一。**

**"战斗开始时帧率下降"的最可能原因**（推测，需要用 profiler 确认）

1. 开战那一帧串行做完所有重活：warmup 预扫描 + 跟随锚点 + 两次 O(V²) 流场重建（`combat_runtime_service.gd:58-61, 340-369`）→ 同步发 `battle_started`，增强系统对全体单位触发 `on_combat_start` → 回到 coordinator 收底栏、改 hex_size、重设全体单位缩放和位置、1024 格整盘重绘。压测里 `combat_start_prewarm` 一次就 46ms。
2. 累加器把长帧放大成连锁：上一帧卡 200ms，下一帧就要补跑多个 tick（最多 6 个）。
3. 第一个移动 tick 全员同时迈步：N 个 Tween + N 次 `cell_changed`/`move_success` 信号 + N 个动画器 `set_process`（`sprite_animator.gd:176-190` 的注释自己承认了这个问题）。
4. 首次交火：飘字数量没有上限——`max_active_damage_texts` 声明了（`vfx_factory.gd:23`）但从没被用过。
5. 稳态噪声：冷却中的单位每个攻击 tick 发一次 `attack_failed("cooldown")`，射程内驻留的单位每个移动 tick 发一次 `unit_move_failed("in_range_hold")`，都要进增强系统的触发器扫描。

**单位状态散在 5 个地方**：UnitBase 的属性和 `runtime_stats` 字典、UnitCombat 组件、节点 meta（字符串键，如 `status_stun_until`）、CombatManager 里约 20 个按 instance_id 索引的字典、增强系统的 state_service。单位所在格子至少存了 3 份，格子键还有 int 和 `"%d,%d"` 字符串两套。同一个概念有两套类（两个 `cell_occupancy.gd`、两个 `combat_metrics.gd`、两个 `combat_targeting.gd`）。

**战斗不可复现**（确认）：种子默认取当前时间、正常开战传 0；单位顺序洗牌、增强系统的随机都用全局 RNG；增强系统跑在渲染帧时钟上而不是逻辑时钟（`unit_augment_manager.gd:70-72`）；逻辑读取的是 Tween 进行中的渲染位置；平局按 instance_id 比较，而 instance_id 每次运行都不同。`m5_battle_replay_check` 只是冒烟测试，不比对两次战斗结果。这意味着平衡调参、复现 bug 都没有可靠基础。

**这一块做得好的**：占格表是逻辑坐标的唯一依据、射程按格距判定；定步长加子步上限；寻敌有目标记忆和重扫窗口；SpatialHash 和 ObjectPool 写得干净（`query_radius_into` 复用输出数组）；VFX 集中管理生命周期、空闲时关 `_process`；死亡处理有幂等登记；RuntimeProbe 分段计时和 50v200 压测探针是后续优化最值钱的资产。

### 4.4 功法 / 装备 / Buff / 地形效果子系统 【高】

**总体判断**：`scripts/unit_augment` + `scripts/domain/unit_augment` 共 31 个文件、约 1.2 万行，占全项目约 1/4。它是一个**通用规则引擎 + 性能基础设施**，而不是游戏内容。手册列了约 30 个 trigger、70 多个 op，基础数据只用到其中一小部分；号称核心卖点的 `tag_linkage_branch` 在基础数据里**一次都没用到**。

**引擎能力 vs 实际使用**（扫描 `mods/base/data` 全部 JSON）

| | 手册声称 | 基础数据实际用到 |
|---|---|---|
| trigger | 约 30 个 | **2 个**：`on_attack_hit`（85 次）、`periodic_seconds`（77 次）；连"满蓝放大招"的 `auto_mp_full` 都没用 |
| op | 70 多个 | 35 个，且集中在 `stat_add`、`mp_regen_add`、`attack_speed_bonus` 这类加属性的 |
| `tag_linkage_branch` | "推荐复杂机制都落在该 op" | **0 次** |
| 召唤、复活、偷取/驱散/净化、控制类、绝大多数位移 | 已实现 | 0 次 |
| Buff 定义 | 61 个 | 50 个没有被任何内容引用 |

162 本功法每本恰好 1 个技能。玩家能感知到的效果实际上只有"命中时触发"和"周期光环"两类。

**一个技能从触发到生效要走约 11 跳**：`combat_event_bridge` → `unit_augment_manager` → `trigger_runtime` → `condition_service` → `execution_service`（拼一个 18 个键的 context 字典）→ `effect_engine` → `active_effect_dispatcher` → 具体 ops → `effect_runtime_gateway` → `buff_manager` → `telemetry_emitter`（这一步又可能触发 `on_debuff_applied`）。其中 manager、trigger_runtime、effect_engine、buff_manager 都是只做转发的 facade，是重构留下的，不是需求要的；各服务又把 `manager: Node` 当服务定位器，有 54 处直接访问 `manager._私有字段`，形成环状依赖。按实际需要，"事件 → 条件 → 执行 → op → 状态"5 层就够了。

**新增一个主动 op 要改 5～8 处**：ops 处理函数 + `register_routes`、可能要加 gateway 方法、目标白名单（`unit_augment_skill_target_service.gd:134-175`）、HUD 格式化的 match、`ui_texts/特效字段.json`、手册、手册测试里的常量。trigger 别名和轮询名单还写了两份（`unit_augment_trigger_runtime.gd:335-351` 与 `unit_augment_unit_state_service.gd:1022-1025`）。

**状态表示**：子系统内 838 次 `.get("键")`、涉及 276 个不同的字符串键；30 个类都声明了 `class_name`，但没有一处被当成静态类型使用（getter 一律返回 Variant）。没有 EffectDef / TriggerEntry / BuffInstance 这类数据类，effect 的"身份"靠 `var_to_str(effect)` 序列化成文本来比对。字段名不统一就靠多别名兜底，比如 `pull_target` 同时读 `distance / cells / distance_cells`。

**"已实现"的标准本身是 grep**：`scripts/tests/m5_mod_trigger_manual_spec_test.gd:182-218` 只检查源码文本里有没有出现带引号的 trigger/op 名字，不检查行为。所以下面这些问题测试都发现不了。

**已确认的实现缺陷**（我逐条核对过前四条）

1. **召唤在真实战斗中失效。** `unit_augment_effect_runtime_gateway.gd:351-355` 要求 `context.battlefield` 有 `spawn_enemy_wave` 方法，而 `battlefield` 取的是 `combat_manager.get_parent()`（`unit_augment_trigger_execution_service.gd:270`），也就是战场根节点 `BattlefieldScene`——它没有这个方法，于是 `has_method` 判断失败、静默返回 0。真正的 `spawn_enemy_wave(count: int)` 在 `scripts/battle/unit_deploy_manager.gd:184`，签名也对不上。测试之所以能过，是因为测试里的 Mock（`m5_effect_engine_smoke_test.gd:159`）还保留着旧接口。**这是"has_method + 静默返回"风格最典型的后果。**
2. **按手册写分档联动，永远命中第一档。** 手册示例 A、7.3、7.6 把 `min_count/max_count` 直接写在 case 上，但代码只认 case 里的 `all/any` 条件数组（`unit_augment_tag_linkage_case_evaluator.gd:337-347`）；没有 `all` 时 `all_ok` 直接为真，第一个 case 必然命中。
3. **`team_scope: "all"` 无效。** 手册写的取值是 `ally/enemy/all`，代码只认 `both`；写 `all` 会落到默认分支、静默按己方算（`unit_augment_trigger_condition_service.gd:529-539`）。
4. **手册测试是 grep**（见上）。
5. **语义和手册不一致的还有**（子代理确认，我未逐条复核）：`resurrect_self` 实际只是活着时回血（系统里没有"死亡时"触发器）；`steal_buff` 忽略 `prefer_ids` 随机偷；`dispel` 忽略 `buff_ids`；`cleanse` 忽略 `count/radius`、一律清空；`damage_if_marked` 在目标未被标记时照样打基础伤害；`passive_aura` 的 `interval` 被忽略；`source_bound_aura` 挂在 `periodic_seconds` 下时（基础数据里 18 处都是这样）走 fallback 作用域，离场后要等一个周期才移除。
6. **推测，需运行验证**：技能施加的 Buff 似乎不会立刻重算单位属性，要等身上某个 Buff 过期才重算（`unit_augment_battlefield_effect_runtime.gd:129-150`），基础数据里有 114 处攻速/增伤类 Buff 依赖这条路径；AOE 半径按 `radius × hex_size × 1.2` 算（`target_query_service.gd:244`），而相邻格中心距是 `√3 × hex_size ≈ 1.73 × hex_size`，`radius=1` 可能碰不到相邻格。

**Schema 与数据对不上**：运行时从不校验（`data_manager.gd:196` 跳过 `_schema`）；terrain 的效果行只允许 `op` 字段，数据里却都带 `value` 或 `buff_id`；装备的 trigger 没声明 `trigger_params`；`tags/*.json` 不参与运行时，`tag_job_healer` 重复定义。

**复杂度和价值不匹配**：总纲 3.4.2 原本是四种具体、玩家看得见的联动；现在换成了一套查询语言 + 约 2500 行的调度、位掩码、分桶代码，却没有一条内容用它。"同门联动"缺门派 tag 做不了，"武技连携"缺跨单位的技能事件也做不了。

**这一块做得好的**：主动 op 用注册表并按领域分组（`scripts/domain/unit_augment/effects/active_effect_dispatcher.gd:31-42`）；被动层是纯数据变换，modifier bundle 契约清楚；触发器在装配时预先分组，信号 connect/disconnect 写法对称；Buff 实例分桶、光环进出差集、死亡清理的模型是对的；`on_hp_below` 做了边沿触发这类细节处理用心。

### 4.5 应用编排层（战场 coordinator）【中】

- `battlefield_coordinator.gd` 1028 行，再加上 5 个 support、22 个文件、共 11,932 行的 `scripts/app/battlefield/`。
- **开战流程写了两遍**：`start_battle_from_session()`（133 行起）和 `_start_battle_from_session_async()`（208 行起）各自实现一遍"自动部署 + 刷敌军"；后者还要用 `has_method("build_enemy_wave_plan")`（237 行）判断协作者有没有这个方法。
- **三份几乎一样的事件处理**：`_on_damage_resolved` / `_on_skill_effect_damage` / `_on_skill_effect_heal`（522～642 行），每条都手工拼一个约 10 个字段的字典。事件 payload 还有两种形状：有的带 `source_id`（要再按 id 查节点），有的直接带 `source` 节点引用。
- **同一事件走两条通道**：`stage_manager.gd` 先发自己的 signal，再用字符串方法名 `_emit_stage_event_to_bus("emit_stage_loaded", [config])`（128、129、146、189、202 行）转发到 EventBus，每次还 `duplicate(true)` 深拷贝一次配置——这违反了项目自己规范里"禁止用动态 call() 代替明确接口"那一条。
- **默认刷 200 个敌人**：`@export var enemy_wave_size: int = 200`（49 行）。没有关卡数据时，每场战斗默认就是压测规模。
- **重复的工具函数**：`_get_event_bus` 定义了 9 次，`_get_unit_augment_manager` 6 次，`_get_data_manager` 5 次，`const TEAM_ALLY` 7 处。
- **过程痕迹留在生产代码里**：170 处注释带 `Batch N / Phase N / 兼容 / 旧接口 / 保留入口`，例如 `# Batch 3 暂时不需要逐帧 coordinator 逻辑，这里保留稳定入口。`（119 行，下面是一个空函数 `process_runtime`）。

### 4.6 仓库卫生 【低】

- `tmp/generated_gongfa/`、`tmp/generated_gongfa_fix/` 生成物带乱码被提交；`tools/_tmp_quit.gd` 是临时脚本。
- 2 个孤立的 `.uid` 文件（对应的测试已删除）：`scripts/tests/m5_mod_test_buff_tag_linkage_test.gd.uid`、`m5_terrain_effect_rework_test.gd.uid`。
- `check.ps1` 把 `.godot-check-*.log` 写到项目根目录，且没有进 `.gitignore`。
- 测试统一叫 `m5_*`，名字记录的是"哪个里程碑写的"，而不是"测什么"。

---

## 5. 文档层的问题

### 5.1 "唯一权威参考"和代码对不上 【高】

`doc/项目规划总纲.md` 开头写着"作为各子系统实现的唯一权威参考"，但：

| 总纲写的 | 实际情况 |
|---|---|
| M1 [√] 升星合成 | 03-30 已删除 |
| M3 [√] 联动检测器（四种联动类型） | 03-23 已删除，换成 tag 计数 |
| M5 [√] Boss 战特殊机制 | 03-24"删除 boss 机制遗留代码" |
| M1 [√] 创建示例 Mod（`example_mod`） | 不存在，只有 `mods/base` 和 `mods/test` |
| M0 [√] GameManager（AutoLoad 单例） | 不存在；`project.godot` 里没有任何 AutoLoad，改成了 AppRoot + ServiceRegistry |
| 4.1 目录：`scripts/gongfa/`、`linkage_data.gd`、`battlefield.gd`、`scripts/ai/` | 都不存在，实际是 `unit_augment/`、`domain/`、`app/` |
| 4.6 先加载 `res://data/` 的基础数据 | `res://data/` 下只剩 `_schema`，基础数据在 `mods/base` |
| 3.4.1 五类功法（含奇术） | 数据里只有内功/外功/身法/阵法四类 |
| 3.3 品质含红色 | 03-24 已删除 |
| 3.5 利息、装备合成 | 没有实现 |

另外，总纲内部也有矛盾：SPD 和 MOV 两个属性都叫"身法"；4.5 说"所有数据用 JSON 而非 Godot Resource"，7.1 又说"所有游戏数据资源化"。

`doc/模组触发器与特效手册.md` 第 1 节说单位触发走 `GongfaManager + TriggerEngine`，这两个类在代码里都不存在（已改名为 `UnitAugment*`）；`doc/角色属性调查.md` 也引用了 `GongfaManager`。

### 5.2 文档在为 AI 写，而不是为人写 【中】

- 总纲第一句话："本文档面向 AI 代码生成"；UI 指南标题是"面向代码 AI"；里程碑一节写"人类负责需求定义、审查与测试"。但 5 万行代码实际上是审查不过来的，"审查"这一环名存实亡。
- 文档里大段嵌代码（`doc/战斗日志规划.md` 1386 行，`doc/水墨风UI修改指南.md` 815 行），代码一改文档就过时。
- **一个 bug 一份文档，修完就删**：git 历史里约 30 份 M0～M5 的设计/修正文档写完又删掉，其中"棋子重叠 / 寻路 / 战后状态"相关的就有 5 份（`M5棋子重叠与寻路错误以及错误战后状态修正.md`、`M5棋子重叠和错误战后状态修正.md`、`M5寻路问题与战后状态修复.md`、`M5角色移动逻辑修正.md`、`M4严格六角格战斗修正文档.md`）。同一类问题反复出现，说明根因一直没解决，而知识随着文档删除丢掉了。
- 没有一份"现在游戏是什么样、哪些能玩、下一步做什么"的短文档，也没有决策记录。哪些机制是故意删的、为什么删，只能从提交信息里猜。

### 5.3 编码规范变成了配额 【中】

`doc/GDScript可读性与编码规范.md` 本意是好的（禁止为压行数而压缩排版），但"10% 中文注释、8% 空行、80% 函数有注释"这类比例指标，配合 AI 生成，必然产生 4.2 里那种凑数注释。规范自己也写了"禁止为了满足注释率堆砌同义反复"，但门禁只能数行数，判断不了注释有没有意义。

---

## 6. 过程层：为什么会"进行不下去"

1. **"完成"的标准是"AI 生成完、测试通过"，不是"玩过觉得好"。** M0～M5 用 4 天全部打勾，日均新增约 1 万行；之后两周半都在删机制、改 bug、重构、调帧率——这些都是前 4 天欠下的债。
2. **还没有可玩的切片，就先做通用化。** Mod 加载、数据编辑器、70 个 effect op、tag 查询语法、架构门禁、泄漏检测，全部在"一关都没有"的情况下完成。通用化的前提是知道要通用什么，而这一点从来没有被验证过。
3. **目标太大，又没有中间验收点。** 50v200 + 全面 Mod + 七大门派 + 五类功法 + 四种联动，是一个商业团队的范围。总纲里没有"最小可玩版本"这一档。
4. **代码量超出了人的审查能力。** 人的角色被设定为"审查与测试"，但没人能审 5 万行。于是只能靠门禁数行数、数注释，而门禁管不了设计质量。
5. **反复的结构性 bug（卡位、寻路、帧率）一直在打补丁。** 每次写一份修正文档、修完删掉，下次换个形式又出现。

---

## 7. 问题优先级汇总

| 级别 | 问题 | 章节 |
|---|---|---|
| 严重 | 没有可玩闭环：关卡、等级表缺失，从未从头玩通 | 3.1 |
| 严重 | 内容是占位/生成物，没有武侠身份，角色之间没有区别 | 3.2 |
| 严重 | 核心卖点（联动、升星）删掉后没有替代玩法 | 3.3 |
| 高 | 250 单位时逻辑帧 49.6ms / 峰值 159ms，远超 8ms 目标；主因是每单位每次动作太重 + 整个逻辑帧压在一帧里算 | 1、4.3 |
| 高 | 六角格两套距离公式（偏移坐标被当轴向坐标算），很可能是反复出现的卡位/寻路 bug 的根因 | 4.3 |
| 高 | 流场周期刷新在 120～219 人、≥320 人时永远不触发 | 4.3 |
| 高 | 规则引擎约 30 trigger / 70+ op，基础数据只用 2 trigger / 35 op，`tag_linkage_branch` 用了 0 次 | 4.4 |
| 高 | 召唤实战失效、手册分档写法永远命中第一档、`team_scope: all` 无效；手册测试只是 grep | 4.4 |
| 高 | 战斗不可复现（全局随机、渲染时钟、instance_id 比较），平衡与复现 bug 没有基础 | 4.3 |
| 高 | 规模目标与自走棋玩法冲突，从未验证 | 3.4 |
| 高 | 无类型字典 + 静默 fallback，错误被吞掉 | 4.1 |
| 高 | 为过门禁机械拆分，耦合转成隐藏耦合 | 4.2 |
| 高 | 总纲号称权威，但十多处与代码不符 | 5.1 |
| 中 | coordinator 重复流程、重复事件处理、双通道事件 | 4.5 |
| 中 | 文档为 AI 写、一 bug 一文档、知识随删除丢失 | 5.2 |
| 中 | 编码规范的比例指标催生凑数注释 | 5.3 |
| 低 | tmp 生成物、孤立 uid、日志写进项目根 | 4.6 |

---

## 8. 对 WXAutoRE 的建议（简版）

1. **先做一个 10 分钟能玩完的切片**：8～12 个有名字、有特色的武侠角色，3～5 关，一种联动机制（比如"同门 2/4 人"），保留三合一升星和利息。先确认好玩，再谈扩展。（具体方案以 `02-最小可玩设计.md` 为准：18 个全局唯一的侠客 + 弟子、6 关、门派 2/4 联动、有利息，不做升星。）
2. ~~规模从小开始：先做 8v8～15v20。~~ **已被否决（2026-10-25）**：多人数对战是核心支柱，不缩规模，见 `02-最小可玩设计.md` 的 D-001。保留的部分：把战斗核心（单位状态放在数组里而不是每个单位一个 Node，渲染用 MultiMesh，逻辑在一个循环里跑）作为第一个里程碑，先用压测证明 50v200 能在预算内跑完。
3. **数据加载时一次性转成有类型的对象，出错就报错**：用 typed class 或 Resource 解析 JSON，字段缺失或拼错直接 `push_error` 并拒绝加载，不要静默回退默认值。
4. **效果系统按需长**：先 10～15 个 op、5 个 trigger，用"注册表 + 每个 op 一个类"，新增一个 op 只改一处。旧手册里的 trigger/op 表当作需求池，等具体角色需要时再挑着加。tag 查询语法往后放。
5. **少分层**：一个功能尽量一个文件；不要 support/runtime/gateway/facade 套娃，不要用继承链拆文件。门禁只保留真正有用的（能跑起来、测试通过、类型检查），去掉注释率之类的比例指标。
6. **文档给人看**：一份短的"当前状态 + 下一步"文档，加一份决策记录（像 GJB、rts-arena 那样按 D-编号记"决定了什么、为什么"）。删机制要记一条决策，而不是删一份文档。
7. **可以从旧项目带走的**：六角格网格（`scripts/board/hex_grid.gd`）、伤害公式链（`doc/角色属性调查.md`）、触发器/效果手册当需求库、测试和压测探针的思路、水墨 UI 的 SVG 和调色板、Mod 数据编辑器。

---

## 附录 A：复现命令

```bash
# 导入项目（首次）
/c/Godot/godot_console --headless --import --path /c/Code/WXAuto
```

```bash
# 跑 50v200 压测探针
/c/Godot/godot_console --headless --path /c/Code/WXAuto --script res://scripts/tests/m5_battlefield_stress_50v200_probe.gd
```

```bash
# 跑项目自带的架构门禁（只报告）
powershell -ExecutionPolicy Bypass -File C:/Code/WXAuto/tools/architecture_guard.ps1 -Root C:/Code/WXAuto -ReportOnly
```
