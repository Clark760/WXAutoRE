// 成就页的全部数据。每完成一个里程碑：
// 1. 把对应里程碑的 status 改成 "done"（下一个改成 "doing"）；
// 2. 在 achievements 末尾追加一条记录；
// 3. 按需要更新 stats 和 redlines 的 now 字段。
// 页面按日期倒序显示，最新的一条会带"最新"标记。

const REPO = "https://github.com/Clark760/WXAutoRE";

window.WXAUTO_DATA = {
  project: {
    name: "武侠自走棋 · 重铸",
    repo: REPO,
    pages: "https://clark760.github.io/WXAutoRE/",
    releases: REPO + "/releases",
  },

  stats: [
    { label: "里程碑完成", value: 0, suffix: " / 5" },
    { label: "50v200 逻辑帧", value: 0.94, decimals: 2, suffix: " ms", note: "旧项目 49.6ms · 目标 ≤4ms" },
    { label: "自动化测试", value: 26, suffix: " 个" },
    { label: "已定决策", value: 29, suffix: " 条" },
  ],

  milestones: [
    { id: "M0", name: "战斗核心", goal: "坐标、地图、数组化战斗、距离场、敌我 AI、城门、压测", status: "done" },
    { id: "M1", name: "数据与 Mod", goal: "类型化数据、Mod 加载与校验、注册表", status: "doing" },
    { id: "M2", name: "功法与 Buff", goal: "触发器、选择器、效果、状态媒介与连携", status: "todo" },
    { id: "M3", name: "局内循环", goal: "卡池、商店、布阵、六关与参考解", status: "todo" },
    { id: "M4", name: "操作与可读性", goal: "框选分组、驻守追击、战报与画中画", status: "todo" },
  ],

  redlines: [
    {
      name: "卡顿",
      glyph: "滞",
      old: "250 单位时逻辑帧均值 49.6ms、峰值 159ms",
      target: "50v200：均值 ≤4ms · p99 ≤8ms · 最大 ≤12ms",
      now: "M0 达标：均值 0.94ms · p99 1.79ms · 最大 2.16ms；窗口模式 p95 7.1ms",
    },
    {
      name: "索敌失效",
      glyph: "盲",
      old: "大部分角色拿不到目标，在后排干等；58% 的移动被堵",
      target: "我方闲置率 ≤10% · 远程 1 秒内开火 ≥95% · 驻守不越界",
      now: "M0 达标：我方闲置率 0% · 远程 1 秒内开火 100% · 越界 0 · 无死锁",
    },
    {
      name: "功法乱放",
      glyph: "乱",
      old: "周期触发只看时间和蓝量，满血也回血、没敌人也放",
      target: "场景测试无效施放 = 0 · 50v200 无效施放率 ≤1%",
      now: "M2 实现",
    },
  ],

  achievements: [
    {
      date: "2026-10-25",
      tag: "序章 · 壹",
      title: "旧项目复盘：找到卡住的根因",
      summary: "把停更半年的 WXAuto 从文档、代码到实测完整过了一遍，确认卡顿、索敌失效、功法乱放三个问题的根因。",
      highlights: [
        "5.1 万行 GDScript、36 个测试在 Godot 4.7.2 上全部通过",
        "50v200 压测：逻辑帧均值 49.6ms、峰值 159ms，九成耗在单位逻辑的常数开销上",
        "查实两个索敌 bug：偏移坐标被当轴向坐标算距离；流场在部分人数区间永远不刷新",
        "规则引擎有 30 个触发器、70 多个效果，基础数据只用了 2 个触发器、35 个效果",
      ],
      metrics: [
        { label: "逻辑帧均值", before: 49.6, target: 4, unit: "ms" },
        { label: "逻辑帧峰值", before: 158.8, target: 12, unit: "ms" },
        { label: "移动被堵比例", before: 58.4, target: 10, unit: "%" },
      ],
      links: [
        { text: "审查文档", href: REPO + "/blob/main/doc/01-WXAuto旧项目审查.md" },
        { text: "提交 820bbdf", href: REPO + "/commit/820bbdf" },
      ],
    },
    {
      date: "2026-10-25",
      tag: "序章 · 贰",
      title: "最小可玩设计定稿",
      summary: "定下两条支柱、三条红线和塔防式分路战场，29 条决策全部拍板。",
      highlights: [
        "两条支柱：多人数对战（终局 50v200）、数据驱动可 Mod",
        "三条红线都有能自动测的验收指标",
        "塔防式分路：任意一个敌人踏上城门即失败，敌人一次全部出现、全部可见",
        "侠客全局唯一，靠星级概率、卡池顺延和关卡保底稳定拿到高星",
        "功法搭配：状态媒介 + 直接连携，连携带 6 条护栏",
      ],
      links: [
        { text: "设计文档", href: REPO + "/blob/main/doc/02-最小可玩设计.md" },
        { text: "提交 1dc98ac", href: REPO + "/commit/1dc98ac" },
      ],
    },
    {
      date: "2026-10-25",
      tag: "M0 · 战斗核心",
      title: "五十人守关，两百人叩门：战斗核心跑通",
      summary: "数组化的战斗模拟、三种距离场、敌我 AI 和城门判定全部完成。50v200 逻辑帧均值 0.94ms，比旧项目快 50 倍。",
      highlights: [
        "逻辑里只有一个距离函数、一个射程判定，偏移坐标只在地图解析里出现一次——旧项目的索敌 bug 从根上消失",
        "50v200 逻辑帧均值 0.94ms、最大 2.16ms；300 单位也只要 1.2ms",
        "窗口模式约 150 FPS，全线接敌前后单帧最大 11.9ms",
        "驻守 AI：远程优先打离城门最近的敌人；我方闲置率 0%，防区越界 0 次",
        "压测抓到并修掉一个死锁：弓手停在墙后一直射，改成「走得到才停下射击」",
        "26 个自动化测试 + 一键检查脚本；同一种子跑三次，结果哈希完全一致",
      ],
      metrics: [
        { label: "50v200 逻辑帧均值", before: 49.6, after: 0.94, target: 4, unit: "ms" },
        { label: "50v200 逻辑帧峰值", before: 158.8, after: 2.16, target: 12, unit: "ms" },
        { label: "每个单位每帧的逻辑开销", before: 190, after: 3.8, target: 16, unit: "µs" },
      ],
      links: [
        { text: "设计文档 v0.4", href: REPO + "/blob/main/doc/02-最小可玩设计.md" },
        { text: "提交 2db6827", href: REPO + "/commit/2db6827" },
      ],
    },
  ],
};
