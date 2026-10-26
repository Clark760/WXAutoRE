# 武侠自走棋 · 重铸（WXAutoRE）

[![成就录](https://img.shields.io/badge/%E6%88%90%E5%B0%B1%E5%BD%95-GitHub%20Pages-a8322d)](https://clark760.github.io/WXAutoRE/)

> 五十人守关，两百人叩门。一个塔防式的武侠自走棋：多人数对战、数据驱动、可 Mod。

**成就录：<https://clark760.github.io/WXAutoRE/>**
每完成一个里程碑，都会在成就录里追加一条记录。

## 这是什么

旧项目 [WXAuto](https://github.com/Clark760/WXAuto) 的重铸版。旧项目卡在三个问题上：大规模战斗卡顿、索敌失效（大部分角色在后排干等）、功法无条件乱放。这次从头设计，三个问题都定成"红线"，每条都有能自动测的验收指标。

- **两条支柱**：多人数对战（终局 50v200）；数据驱动、可 Mod。
- **玩法**：参照塔防。敌人从地图一端冲向城门，我方在多条路上布防；任意一个敌人踏上城门，这一局就失败。重心在功法搭配、门派联动和分路布防。

## 进度

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M0 战斗核心 | 坐标、字符画地图、数组化战斗、距离场、敌我 AI（默认迎击）、城门、MultiMesh、压测 | ✅ 完成：50v200 逻辑帧均值 1.49ms（旧项目 49.6ms） |
| M1 数据与 Mod | 类型化数据、Mod 加载与校验、注册表 | 下一步 |
| M2 功法与 Buff | 触发器、选择器、效果、状态媒介与连携 | 未开始 |
| M3 局内循环 | 侠客卡池、商店、布阵、六关与参考解 | 未开始 |
| M4 操作与可读性 | 框选分组、驻守/追击、战报、画中画 | 未开始 |

## 运行

需要 Godot 4.7（开发时用的是 4.7.2）。用 Godot 打开项目直接运行，主场景是 M0 的战斗演示：

- `1`～`4` 切换压测场景 B1～B4，`空格` 暂停，`Q`/`E` 调倍速，`R` 重开
- `F3` 调试叠加：单位按状态上色，被堵超过 2 秒的标红，画出我方防区
- `WASD`/方向键/中键拖动平移，滚轮缩放

命令行（把 `godot` 换成你的 Godot 可执行文件）：

```bash
godot --headless --path . --script res://tests/run_all.gd
```

```bash
godot --headless --path . --script res://tests/bench/run_bench.gd
```

```bash
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

第一条跑全部测试，第二条跑 B1～B4 压测，第三条是一键检查（导入、测试、压测；加 `-Windowed` 再跑一次窗口压测）。

## 文档

- [旧项目审查](doc/01-WXAuto旧项目审查.md)：旧项目的问题、实测数据和优先级。
- [最小可玩设计](doc/02-最小可玩设计.md)：两条支柱、三条红线、塔防式分路战场、全部决策（D-001～D-029）。

## 目录

| 目录 | 内容 |
|---|---|
| `src/core/` | 六角坐标（全项目唯一的距离公式） |
| `src/data/` | 地图与字符画解析、单位定义 |
| `src/battle/` | 战斗模拟：数组化状态、距离场、空间分桶、敌我 AI、压测统计 |
| `src/view/` | 表现层：MultiMesh 绘制、插值、调试叠加 |
| `src/dev/` | M0 压测场景（M1 起搬进 `mods/base`） |
| `src/app/` | 演示场景 |
| `tests/` | 单元测试、场景测试、压测 |
| `tools/` | 一键检查脚本 |
| `doc/` | 设计文档 |
| `site/` | 成就录页面（GitHub Pages），数据在 `site/data/achievements.js` |
