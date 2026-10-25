// 成就录页面：按 data/achievements.js 渲染内容，并驱动各种动效。
(() => {
  "use strict";

  const DATA = window.WXAUTO_DATA;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(pointer: fine)").matches;

  const $ = (sel) => document.querySelector(sel);

  function esc(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function cssVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  // ---------- 链接 ----------

  function fillLinks() {
    const p = DATA.project;
    for (const id of ["link-repo", "footer-repo"]) $("#" + id).href = p.repo;
    for (const id of ["link-releases", "footer-releases"]) $("#" + id).href = p.releases;
  }

  // ---------- 数字 ----------

  function renderStats() {
    const root = $("#stats");
    const done = DATA.milestones.filter((m) => m.status === "done").length;
    root.innerHTML = DATA.stats
      .map((s) => {
        const value = s.label === "里程碑完成" ? done : s.value;
        return `<div class="stat reveal">
          <div class="stat-value"><span data-count="${value}" data-decimals="${s.decimals || 0}">0</span><small>${esc(s.suffix || "")}</small></div>
          <div class="stat-label">${esc(s.label)}</div>
          ${s.note ? `<div class="stat-note">${esc(s.note)}</div>` : ""}
        </div>`;
      })
      .join("");
  }

  function countUp(node) {
    const target = parseFloat(node.dataset.count);
    const decimals = parseInt(node.dataset.decimals, 10) || 0;
    if (reduceMotion) {
      node.textContent = target.toFixed(decimals);
      return;
    }
    const start = performance.now();
    const duration = 1400;
    const step = (now) => {
      const t = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      node.textContent = (target * eased).toFixed(decimals);
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // ---------- 里程碑 ----------

  const STATE_TEXT = { done: "已完成", doing: "进行中", todo: "未开始" };

  function renderRoad() {
    const list = $("#road-list");
    list.innerHTML = DATA.milestones
      .map(
        (m) => `<li class="road-node ${m.status}">
          <div class="road-dot">${m.status === "done" ? "✓" : esc(m.id)}</div>
          <div class="road-name">${esc(m.id)} · ${esc(m.name)}</div>
          <div class="road-goal">${esc(m.goal)}</div>
          <div><span class="road-state">${STATE_TEXT[m.status] || ""}</span></div>
        </li>`
      )
      .join("");
  }

  function fillRoad() {
    const total = DATA.milestones.length;
    const done = DATA.milestones.filter((m) => m.status === "done").length;
    const doing = DATA.milestones.some((m) => m.status === "doing") ? 0.5 : 0;
    const ratio = Math.min(1, (done + doing) / Math.max(1, total - 1));
    $("#road-fill").style.width = (ratio * 100).toFixed(1) + "%";
  }

  // ---------- 红线 ----------

  function renderRedlines() {
    $("#redline-list").innerHTML = DATA.redlines
      .map(
        (r) => `<article class="redline reveal">
          <div class="redline-glyph">${esc(r.glyph)}</div>
          <h3>${esc(r.name)}</h3>
          <dl>
            <dt>旧项目</dt><dd class="old">${esc(r.old)}</dd>
            <dt>验收目标</dt><dd class="target">${esc(r.target)}</dd>
            <dt>当前</dt><dd class="now">${esc(r.now || "—")}</dd>
          </dl>
        </article>`
      )
      .join("");
  }

  // ---------- 成就录 ----------

  function renderMetrics(metrics) {
    if (!metrics || metrics.length === 0) return "";
    const rows = metrics
      .map((m) => {
        const max = Math.max(m.before || 0, m.after || 0, m.target || 0) * 1.08 || 1;
        const pct = (v) => ((v / max) * 100).toFixed(1) + "%";
        const parts = [];
        if (m.before !== undefined) parts.push(`旧 ${m.before}${m.unit}`);
        if (m.after !== undefined) parts.push(`现 ${m.after}${m.unit}`);
        if (m.target !== undefined) parts.push(`目标 ≤${m.target}${m.unit}`);
        return `<div class="metric">
          <div class="metric-head"><span>${esc(m.label)}</span><span>${esc(parts.join(" · "))}</span></div>
          <div class="metric-track">
            ${m.before !== undefined ? `<div class="metric-bar before" data-width="${pct(m.before)}"></div>` : ""}
            ${m.after !== undefined ? `<div class="metric-bar after" data-width="${pct(m.after)}"></div>` : ""}
            ${m.target !== undefined ? `<div class="metric-target" style="left:${pct(m.target)}"></div>` : ""}
          </div>
        </div>`;
      })
      .join("");
    return `<div class="metrics">${rows}
      <div class="metric-legend">
        <span><i style="background:var(--ink-3)"></i>旧项目</span>
        <span><i style="background:var(--jade)"></i>现在</span>
        <span><i style="background:var(--gold)"></i>目标线</span>
      </div>
    </div>`;
  }

  function renderTimeline() {
    const items = DATA.achievements
      .map((a, index) => ({ a, index }))
      .sort((x, y) => (x.a.date === y.a.date ? y.index - x.index : x.a.date < y.a.date ? 1 : -1));
    $("#timeline-list").innerHTML = items
      .map(({ a }, i) => {
        const latest = i === 0;
        return `<li class="tl-item reveal${latest ? " latest" : ""}">
          <div class="tl-dot"></div>
          <article class="card">
            <div class="card-head">
              <span class="tag">${esc(a.tag)}</span>
              <time datetime="${esc(a.date)}">${esc(a.date)}</time>
              ${latest ? '<span class="latest-badge">最新</span>' : ""}
            </div>
            <h3>${esc(a.title)}</h3>
            <p class="summary">${esc(a.summary)}</p>
            ${a.highlights ? `<ul>${a.highlights.map((h) => `<li>${esc(h)}</li>`).join("")}</ul>` : ""}
            ${renderMetrics(a.metrics)}
            ${a.links ? `<div class="card-links">${a.links.map((l) => `<a href="${esc(l.href)}">${esc(l.text)} ↗</a>`).join("")}</div>` : ""}
          </article>
        </li>`;
      })
      .join("");
  }

  // ---------- 滚动出现 ----------

  function setupReveal() {
    const targets = document.querySelectorAll(".reveal, .section-title");
    if (reduceMotion || !("IntersectionObserver" in window)) {
      targets.forEach((t) => t.classList.add("in"));
      document.querySelectorAll("[data-count]").forEach(countUp);
      document.querySelectorAll(".metric-bar").forEach((b) => (b.style.width = b.dataset.width));
      fillRoad();
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const node = entry.target;
          node.classList.add("in");
          node.querySelectorAll("[data-count]").forEach(countUp);
          node.querySelectorAll(".metric-bar").forEach((b, k) => {
            setTimeout(() => (b.style.width = b.dataset.width), 150 + k * 120);
          });
          if (node.classList.contains("road")) setTimeout(fillRoad, 200);
          io.unobserve(node);
        }
      },
      { threshold: 0.18 }
    );
    targets.forEach((t, k) => {
      if (t.classList.contains("stat") || t.classList.contains("redline")) {
        t.style.transitionDelay = (k % 4) * 90 + "ms";
      }
      io.observe(t);
    });
  }

  function setupTimelineProgress() {
    const tl = $("#timeline-list");
    const update = () => {
      const rect = tl.getBoundingClientRect();
      const vh = window.innerHeight;
      const p = Math.max(0, Math.min(1, (vh * 0.75 - rect.top) / Math.max(1, rect.height)));
      tl.style.setProperty("--tl-progress", p.toFixed(3));
    };
    if (reduceMotion) {
      tl.style.setProperty("--tl-progress", "1");
      return;
    }
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  function setupTilt() {
    if (reduceMotion || !finePointer) return;
    document.querySelectorAll(".card, .redline").forEach((card) => {
      card.addEventListener("pointermove", (e) => {
        const r = card.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        card.style.transform = `perspective(900px) rotateX(${(-y * 4).toFixed(2)}deg) rotateY(${(x * 5).toFixed(2)}deg)`;
      });
      card.addEventListener("pointerleave", () => (card.style.transform = ""));
    });
  }

  // ---------- 首屏动画：三路塔防 ----------

  function startBattle() {
    const canvas = $("#battle-canvas");
    const ctx = canvas.getContext("2d");
    const LANES = 3;
    const enemies = [];
    const defenders = [];
    const drops = [];
    const gateFlash = [0, 0, 0];
    let W = 0;
    let H = 0;
    let dpr = 1;
    let gridLayer = null;
    let palette = {};
    let spawnAcc = 0;
    let visible = true;
    let last = performance.now();
    let time = 0;

    const laneCenter = (i) => W * (0.2 + i * 0.3);
    const laneHalf = () => Math.min(W * 0.11, 130);
    const gateY = () => H * 0.94;

    function readPalette() {
      palette = {
        ink: cssVar("--ink"),
        gold: cssVar("--gold"),
        vermilion: cssVar("--vermilion"),
        jade: cssVar("--jade"),
        line: cssVar("--line"),
      };
    }

    function buildGrid() {
      gridLayer = document.createElement("canvas");
      gridLayer.width = W * dpr;
      gridLayer.height = H * dpr;
      const g = gridLayer.getContext("2d");
      g.scale(dpr, dpr);
      const s = Math.max(14, Math.min(22, W / 70));
      const w = Math.sqrt(3) * s;
      g.strokeStyle = palette.ink;
      g.globalAlpha = 0.06;
      g.lineWidth = 1;
      for (let row = 0, y = 0; y < H + s * 2; row++, y += s * 1.5) {
        for (let x = (row % 2) * (w / 2); x < W + w; x += w) {
          g.beginPath();
          for (let k = 0; k < 6; k++) {
            const ang = (Math.PI / 180) * (60 * k - 30);
            const px = x + s * Math.cos(ang);
            const py = y + s * Math.sin(ang);
            if (k === 0) g.moveTo(px, py);
            else g.lineTo(px, py);
          }
          g.closePath();
          g.stroke();
        }
      }
      // 路与路之间的墙：淡淡的墨带，中间留一道窄口
      g.globalAlpha = 0.07;
      g.fillStyle = palette.ink;
      for (let i = 0; i < LANES - 1; i++) {
        const x = (laneCenter(i) + laneCenter(i + 1)) / 2;
        g.fillRect(x - 10, 0, 20, H * 0.46);
        g.fillRect(x - 10, H * 0.56, 20, H * 0.44);
      }
    }

    function placeDefenders() {
      defenders.length = 0;
      for (let lane = 0; lane < LANES; lane++) {
        const c = laneCenter(lane);
        const spacing = laneHalf() / 2;
        for (let row = 0; row < 2; row++) {
          for (let k = 0; k < 4; k++) {
            const hx = c + (k - 1.5) * spacing + (row ? spacing / 2 : 0);
            const hy = H * 0.72 + row * 26;
            defenders.push({ lane, hx, hy, x: hx, y: hy, cd: Math.random(), ranged: row === 1 });
          }
        }
      }
    }

    function resize() {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = canvas.clientWidth;
      H = canvas.clientHeight;
      // 布局还没完成时尺寸为 0，等 ResizeObserver 再调一次
      if (W === 0 || H === 0) {
        gridLayer = null;
        return;
      }
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      readPalette();
      buildGrid();
      placeDefenders();
    }

    function spawnEnemy() {
      const lane = Math.floor(Math.random() * LANES);
      enemies.push({
        lane,
        x: laneCenter(lane) + (Math.random() - 0.5) * 1.6 * laneHalf(),
        y: -14,
        vy: 24 + Math.random() * 22,
        hp: 3,
        r: 3.5 + Math.random() * 2.5,
        wob: Math.random() * Math.PI * 2,
        held: false,
        suicider: Math.random() < 0.08,
      });
    }

    function splash(x, y, color, n) {
      for (let k = 0; k < n; k++) {
        const a = Math.random() * Math.PI * 2;
        const v = 20 + Math.random() * 70;
        drops.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0.6 + Math.random() * 0.5, color, r: 1 + Math.random() * 2.2 });
      }
    }

    function update(dt) {
      time += dt;
      spawnAcc += dt;
      const cap = W < 700 ? 40 : 80;
      while (spawnAcc > 0.28) {
        spawnAcc -= 0.28;
        if (enemies.length < cap) spawnEnemy();
      }

      for (const e of enemies) e.held = false;

      for (const d of defenders) {
        let best = null;
        let bestDist = 1e9;
        for (const e of enemies) {
          if (e.hp <= 0) continue;
          const dh = Math.hypot(e.x - d.hx, e.y - d.hy);
          if (dh > (d.ranged ? 120 : 80)) continue;
          const dd = Math.hypot(e.x - d.x, e.y - d.y);
          if (dd < bestDist) {
            bestDist = dd;
            best = e;
          }
        }
        const reach = d.ranged ? 90 : 12;
        if (best && bestDist > reach && !d.ranged) {
          const k = Math.min(1, (60 * dt) / bestDist);
          d.x += (best.x - d.x) * k;
          d.y += (best.y - d.y) * k;
        } else if (!best) {
          d.x += (d.hx - d.x) * Math.min(1, dt * 2);
          d.y += (d.hy - d.y) * Math.min(1, dt * 2);
        }
        if (best && bestDist <= reach) {
          if (!best.suicider || !d.ranged) best.held = !d.ranged || best.held;
          d.cd -= dt;
          if (d.cd <= 0) {
            d.cd = d.ranged ? 1.1 : 0.7;
            best.hp -= 1;
            if (d.ranged) drops.push({ x: d.x, y: d.y, vx: (best.x - d.x) * 3, vy: (best.y - d.y) * 3, life: 0.3, color: palette.gold, r: 1.6 });
            splash(best.x, best.y, palette.ink, 3);
          }
        }
      }

      for (let i = enemies.length - 1; i >= 0; i--) {
        const e = enemies[i];
        if (e.hp <= 0) {
          splash(e.x, e.y, palette.ink, 14);
          enemies.splice(i, 1);
          continue;
        }
        if (!e.held) {
          e.y += e.vy * (e.suicider ? 1.8 : 1) * dt;
          e.x += Math.sin(time * 2 + e.wob) * 6 * dt;
        }
        if (e.y >= gateY()) {
          gateFlash[e.lane] = 1;
          splash(e.x, gateY(), palette.vermilion, 10);
          enemies.splice(i, 1);
        }
      }

      for (let i = drops.length - 1; i >= 0; i--) {
        const p = drops[i];
        p.life -= dt;
        if (p.life <= 0) {
          drops.splice(i, 1);
          continue;
        }
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= 0.9;
        p.vy *= 0.9;
      }

      for (let i = 0; i < LANES; i++) gateFlash[i] = Math.max(0, gateFlash[i] - dt * 1.5);
    }

    function draw() {
      ctx.clearRect(0, 0, W, H);
      if (gridLayer) ctx.drawImage(gridLayer, 0, 0, W, H);

      for (let i = 0; i < LANES; i++) {
        const c = laneCenter(i);
        const half = laneHalf() * 0.5;
        ctx.globalAlpha = 0.3 + gateFlash[i] * 0.7;
        ctx.fillStyle = palette.vermilion;
        ctx.fillRect(c - half, gateY(), half * 2, 6);
        if (gateFlash[i] > 0) {
          ctx.globalAlpha = gateFlash[i] * 0.25;
          ctx.fillRect(c - half * 1.6, gateY() - 30, half * 3.2, 36);
        }
      }

      ctx.globalAlpha = 1;
      for (const e of enemies) {
        ctx.globalAlpha = 0.18;
        ctx.strokeStyle = palette.ink;
        ctx.lineWidth = e.r;
        ctx.beginPath();
        ctx.moveTo(e.x, e.y - e.r * 3);
        ctx.lineTo(e.x, e.y);
        ctx.stroke();
        ctx.globalAlpha = 0.85;
        ctx.fillStyle = e.suicider ? palette.vermilion : palette.ink;
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r, 0, Math.PI * 2);
        ctx.fill();
      }

      for (const d of defenders) {
        ctx.globalAlpha = 0.9;
        ctx.fillStyle = d.ranged ? palette.jade : palette.gold;
        ctx.beginPath();
        ctx.arc(d.x, d.y, 5.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 0.35;
        ctx.strokeStyle = d.ranged ? palette.jade : palette.gold;
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.arc(d.x, d.y, 9, 0, Math.PI * 2);
        ctx.stroke();
      }

      for (const p of drops) {
        ctx.globalAlpha = Math.max(0, Math.min(1, p.life * 1.4)) * 0.75;
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    function frame(now) {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      requestAnimationFrame(frame);
      if (visible && !document.hidden && gridLayer) {
        update(dt);
        draw();
      }
    }

    resize();
    if ("ResizeObserver" in window) {
      new ResizeObserver(resize).observe(canvas);
    } else {
      window.addEventListener("resize", resize);
    }
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", resize);

    if (reduceMotion) {
      // 不播放动画时只画一帧静态画面
      requestAnimationFrame(() => {
        resize();
        if (!gridLayer) return;
        for (let k = 0; k < 40; k++) spawnEnemy();
        for (const e of enemies) e.y = Math.random() * H * 0.6;
        draw();
      });
      return;
    }

    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        visible = entries[0].isIntersecting;
      }).observe(canvas);
    }
    requestAnimationFrame(frame);
  }

  fillLinks();
  renderStats();
  renderRoad();
  renderRedlines();
  renderTimeline();
  setupReveal();
  setupTimelineProgress();
  setupTilt();
  startBattle();
})();
