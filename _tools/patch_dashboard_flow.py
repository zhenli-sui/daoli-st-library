# -*- coding: utf-8 -*-
"""把云端看板的「七席产线」改成真实交互关系流程图：
   S0 派工 → S1 规划 → S3 编码 → S4 编译闸 → S5 审校 → S0 入库
   并行支线：S2 供料（按需）→ S3
   否决回派：S4 --FAIL--> S6，S5 --MAJOR--> S6，S6 --复裁--> S4（唯一回环）
用法: python patch_dashboard_flow.py <work_dir>/index.html
"""
import io
import re
import sys

P = sys.argv[1]
t = io.open(P, encoding="utf-8").read()
orig = len(t)
done = []


def rep(a, b, name):
    global t
    if a not in t:
        raise SystemExit("❌ 未命中：" + name + " -> " + a[:60])
    t = t.replace(a, b, 1)
    done.append(name)


# ── 1. 标题与容器 ────────────────────────────────────────────────
OLD_TITLE = ('<h2 data-page-node-id="Os69GFYOBvnK7nTjVcfvf1" class="sec-title">'
             '<!--pnid:GMcoaOF5LKIBA9SX6SlFlX-->七席产线（S0 主控 + S1~S6 专席 · 点击节点查看席位详情）</h2>')
NEW_TITLE = ('<h2 data-page-node-id="Os69GFYOBvnK7nTjVcfvf1" class="sec-title">'
             '<!--pnid:GMcoaOF5LKIBA9SX6SlFlX-->七席协作流程图 · 实际交互关系（点击任一席位看职责详情）</h2>')
rep(OLD_TITLE, NEW_TITLE, "标题")

OLD_PIPE = '<div data-page-node-id="PZvKAtwOMPltYswHPBOwfk" class="pipe" id="pipe"></div>'
NEW_PIPE = """<div id="flowChart" style="width:100%;overflow-x:auto;overflow-y:hidden"></div>
    <div class="flow-legend">
      <span><i style="background:#22d3ee"></i>派工（主控 → S1，唯一入口）</span>
      <span><i style="background:#38bdf8"></i>计划 / 数据流（计划表、待裁件、PASS 件）</span>
      <span><i style="background:#4ade80"></i>通过链（PASS → 下一席 / 入库）</span>
      <span><i style="background:#f87171"></i>否决回派（S4 FAIL → S6）</span>
      <span><i style="background:#fbbf24"></i>审校回派（S5 MAJOR → S6）</span>
      <span><i style="background:#fb923c"></i>修复回环（S6 → S4 复裁，唯一环路）</span>
      <span><i style="background:#34d399"></i>按需支线（S2 缺料才触发，虚线）</span>
    </div>
    <p style="margin:12px 0 0; font-size:12px; color:var(--dim2); line-height:1.9">
      三条铁律体现在线上：<b style="color:var(--red)">只有 S4 和 S5 能退件</b>，退件只进 S6，<b style="color:var(--orange,#fb923c)">S6 修完必须回 S4 复裁</b>，不能自己判 PASS；
      S2 是支线，队列有效 ≥30 条时整轮不触发；S0 不与任何执行席反向连线，<b style="color:var(--cyan)">主控不写码、不改码、不裁编译</b>。
    </p>
    <h3 style="margin:18px 0 0; font-size:13px; color:var(--dim)">九道工序明细（点击查看）</h3>
    <div class="flow-chips" id="pipe" data-page-node-id="PZvKAtwOMPltYswHPBOwfk"></div>"""
rep(OLD_PIPE, NEW_PIPE, "管线容器→流程图容器")

rep("🔒 registry / JSONL 单点写入，五步串行生命周期",
    "🔒 registry / JSONL 单点写入，S1→S3→S4→S5→S0 五段串行不可跳步", "图例末条")

# ── 2. CSS ──────────────────────────────────────────────────────
rep(".exp-grid{grid-template-columns:repeat(5,1fr)}",
    ".exp-grid{grid-template-columns:repeat(auto-fit,minmax(196px,1fr))}\n"
    ".flow-chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}\n"
    ".fchip{display:flex;flex-direction:column;gap:2px;padding:8px 12px;border:1px solid var(--line);"
    "border-radius:10px;background:var(--panel2);cursor:pointer;transition:.25s}\n"
    ".fchip:hover{border-color:var(--cyan);transform:translateY(-2px)}\n"
    ".fchip b{color:var(--txt);font-weight:600;font-size:12px}\n"
    ".fchip span{color:var(--dim2);font-size:10.5px;font-family:Consolas,monospace}\n"
    ".flow-legend{display:flex;flex-wrap:wrap;gap:6px 18px;margin-top:10px;font-size:11.5px;color:var(--dim)}\n"
    ".flow-legend i{display:inline-block;width:22px;height:3px;border-radius:2px;margin-right:6px;vertical-align:middle}\n"
    ".fnode rect{transition:.25s}\n"
    ".fnode:hover rect{stroke-width:2.6;filter:brightness(1.35)}",
    "CSS 补充")

# ── 3. 管线渲染 → 流程图 + chips ──────────────────────────────────
OLD_JS = """/* ═════════ pipeline ═════════ */
const pipe=document.getElementById('pipe');
DATA.stages.forEach((s,i)=>{
 const d=document.createElement('div');d.className='stage';
 d.innerHTML=`<div class="box"><div class="ic">${s.ic}</div><div class="nm">${s.nm}</div><div class="ag">${s.ag}</div>
  <div class="st ${s.st}"><i></i>${s.stt}</div></div>`;
 d.onclick=()=>showStage(s);pipe.appendChild(d);
 if(i<DATA.stages.length-1){const l=document.createElement('div');l.className='link';l.innerHTML='<i></i><i></i>';pipe.appendChild(l);}
});"""

NEW_JS = r"""/* ═════════ 七席协作流程图（实际交互关系） ═════════ */
(function(){
 const fw=document.getElementById('flowChart'); if(!fw) return;
 /* 节点：x,y,w,h,颜色,图标,标题,副标题,对应 DATA.stages 下标 */
 const N={
  S0:[550,46,200,76,"#22d3ee","🎯","S0 主控","dlf-lead · 派工/终审/入库/复盘",6],
  S1:[40,280,170,76,"#38bdf8","🗺️","S1 规划查重","dlf-planner",0],
  S3:[302,280,170,76,"#fbbf24","⌨️","S3 编码","dlf-builder",2],
  S4:[564,280,170,76,"#f87171","🚦","S4 编译闸","dlf-gatekeeper",3],
  S5:[826,280,170,76,"#a78bfa","🔍","S5 审校去重","dlf-inspector",4],
  AR:[1088,280,170,76,"#34d399","📦","S0 注册入库","registry·JSONL·ROADMAP",6],
  S2:[302,470,170,76,"#34d399","🕸️","S2 供料 · 按需","dlf-sourcer",1],
  S6:[826,470,170,76,"#fb923c","🔧","S6 定点修复","dlf-fixer",5]
 };
 /* 边：d 路径 / c 颜色 / dash 虚线 / l 标注 / lx,ly 标注坐标 / la 对齐 */
 const E=[
  {d:"M600,122 V180 H135 V278", c:"#22d3ee", l:"派工 40 件配额（复杂≤12 / 简单≥28）", lx:345, ly:172},
  {d:"M212,318 H300", c:"#38bdf8", l:"计划表 ROUND_PLAN", lx:256, ly:272},
  {d:"M387,468 V358", c:"#34d399", dash:1, l:"候选队列 · 按需", lx:397, ly:412, la:"start"},
  {d:"M474,318 H562", c:"#38bdf8", l:"40 件待裁", lx:518, ly:272},
  {d:"M736,318 H824", c:"#4ade80", l:"PASS 件", lx:780, ly:272},
  {d:"M996,318 H1086", c:"#4ade80", l:"PASS 授权入库", lx:1042, ly:272},
  {d:"M660,356 V402 H762 V508 H822", c:"#f87171", l:"FAIL 单 · 回派 S6", lx:700, ly:392},
  {d:"M911,356 V468", c:"#fbbf24", l:"MAJOR 单", lx:921, ly:414, la:"start"},
  {d:"M911,546 V588 H600 V358", c:"#fb923c", dash:1, l:"修后 --no-cache 复裁（唯一回环）", lx:756, ly:578}
 ];
 const cols=[...new Set(E.map(e=>e.c))];
 let defs='<defs>'+cols.map((c,i)=>'<marker id="fa'+i+'" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="'+c+'"/></marker>').join('')+'</defs>';
 const edges=E.map(e=>{
  const mi=cols.indexOf(e.c);
  return '<path d="'+e.d+'" fill="none" stroke="'+e.c+'" stroke-width="1.9" stroke-linecap="round"'
   +(e.dash?' stroke-dasharray="6 5"':'')+' marker-end="url(#fa'+mi+')" opacity=".92"/>'
   +'<text x="'+e.lx+'" y="'+e.ly+'" text-anchor="'+(e.la||"middle")+'" font-size="10.5" fill="'+e.c+'" font-family="system-ui,sans-serif">'+e.l+'</text>';
 }).join('');
 const nodes=Object.entries(N).map(([k,v])=>{
  const x=v[0],y=v[1],w=v[2],h=v[3],c=v[4],ic=v[5],ti=v[6],sb=v[7],si=v[8],cx=x+w/2;
  return '<g class="fnode" data-si="'+si+'" style="cursor:pointer">'
   +'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" rx="14" fill="'+c+'16" stroke="'+c+'" stroke-width="1.4" stroke-opacity=".65"/>'
   +'<text x="'+cx+'" y="'+(y+24)+'" text-anchor="middle" font-size="16">'+ic+'</text>'
   +'<text x="'+cx+'" y="'+(y+45)+'" text-anchor="middle" font-size="13" font-weight="600" fill="#e8f2ff">'+ti+'</text>'
   +'<text x="'+cx+'" y="'+(y+63)+'" text-anchor="middle" font-size="9.5" fill="#8ba0c4" font-family="Consolas,monospace">'+sb+'</text>'
   +'</g>';
 }).join('');
 const notes='<text x="772" y="62" font-size="11" fill="#7f93b8">主控只做四件事：派工 · 终审 · 入库 · 复盘</text>'
  +'<text x="772" y="80" font-size="11" fill="#f87171">不写业务码（S3 写）· 不改业务码（S6 改）· 不裁编译（S4 裁）</text>'
  +'<text x="772" y="98" font-size="11" fill="#7f93b8">S0 与执行席之间无反向连线，越权通道在图上就不存在</text>'
  +'<text x="302" y="150" font-size="10.5" fill="#5f739a">↓ 40 件目标下发后，件沿主链单向流动</text>'
  +'<text x="40" y="600" font-size="10.5" fill="#5f739a">读法：横向 = 件的一次流转；向上 = 供料；向下 = 回派；最下方长弧 = 修复后唯一合法回环</text>';
 const svg='<svg viewBox="0 0 1300 620" width="100%" style="min-width:980px;display:block" xmlns="http://www.w3.org/2000/svg">'
  +defs+'<g>'+edges+'</g><g>'+notes+'</g><g>'+nodes+'</g></svg>';
 fw.innerHTML=svg;
 fw.querySelectorAll('.fnode').forEach(g=>{
  g.addEventListener('click',()=>{const s=DATA.stages[+g.dataset.si]; if(s) showStage(s);});
 });
})();

/* ═════════ 九道工序 chips ═════════ */
const pipe=document.getElementById('pipe');
DATA.stages.forEach((s)=>{
 const d=document.createElement('div');d.className='fchip';
 d.innerHTML='<b>'+s.nm+'</b><span>'+s.ag.split('（')[0]+'</span>';
 d.onclick=()=>showStage(s);pipe.appendChild(d);
});"""
rep(OLD_JS, NEW_JS, "管线渲染→流程图渲染")

# ── 4. 专家卡补「上游/下游」────────────────────────────────────
OLD_EXP = """d.innerHTML=`<div class="avatar" style="background:${e.col}18;color:${e.col}">${e.ic}</div>
  <div class="nm" style="color:var(--txt)">${e.name}</div><div class="rl">${e.role}</div>
  <div class="mt">${e.ledger.split('·')[0].trim()}</div><div class="pill">● 在线 · 原生召唤</div>`;"""
NEW_EXP = """d.innerHTML=`<div class="avatar" style="background:${e.col}18;color:${e.col}">${e.ic}</div>
  <div class="nm" style="color:var(--txt)">${e.name}</div><div class="rl">${e.role}</div>
  <div class="mt" style="color:${e.col};opacity:.9">${e.io||''}</div>
  <div class="mt">${e.ledger.split('·')[0].trim()}</div><div class="pill">● 在线 · 原生召唤</div>`;"""
rep(OLD_EXP, NEW_EXP, "专家卡加上下游")

OLD_MODAL = """ <p>${e.desc}</p><div class="sec"><h4>进化账本</h4><p>${e.ledger}</p><h4 style="margin-top:10px">最近状态</h4><p>${e.stats}</p></div>"""
NEW_MODAL = """ <p>${e.desc}</p><div class="sec"><h4>交互关系</h4><p>${e.io||''}</p><h4 style="margin-top:10px">进化账本</h4><p>${e.ledger}</p><h4 style="margin-top:10px">最近状态</h4><p>${e.stats}</p></div>"""
rep(OLD_MODAL, NEW_MODAL, "详情弹窗加交互关系")

# ── 5. 给每个专家对象注入 io 字段 ───────────────────────────────
IO = {
    "dlf-lead": "↑ 收：S4/S5 裁决 + 六席回报　↓ 发：S1 配额、registry 入库、战报",
    "dlf-planner": "↑ 收：S0 配额与当日进度　↓ 发：S3（ROUND_PLAN 是 S3 唯一输入）",
    "dlf-sourcer": "↑ 收：S1/S3 缺料信号　↓ 发：S3 候选队列（按需，虚线支线）",
    "dlf-builder": "↑ 收：S1 计划表 + S2 候选队列　↓ 发：S4（40 件待裁）",
    "dlf-gatekeeper": "↑ 收：S3 待裁件 + S6 修复件　↓ 发：S5（PASS）/ S6（FAIL 单）",
    "dlf-inspector": "↑ 收：S4 PASS 件　↓ 发：S0 入库授权（PASS）/ S6（MAJOR 单）",
    "dlf-fixer": "↑ 收：S4 FAIL 单 + S5 MAJOR 单　↓ 回：S4 复裁 → S5 复查",
}


def inject(m):
    head, role = m.group(1), m.group(2)
    key = None
    for k in IO:
        if k in head:
            key = k
            break
    if not key:
        return m.group(0)
    if ",io:" in m.group(0):
        return m.group(0)
    return head + role + ',io:"' + IO[key] + '"'


cnt = 0
for k, v in IO.items():
    pat = re.compile(r'(\{name:"[^"]*' + k + r'[^"]*"[^\n]*?role:")([^"]*)"')
    t2, n = pat.subn(lambda m, v=v: m.group(1) + m.group(2) + '",io:"' + v + '"', t, count=1)
    if n:
        t = t2
        cnt += 1
done.append("io 注入 %d/%d" % (cnt, len(IO)))
if cnt != len(IO):
    raise SystemExit("❌ 有专家未注入 io，检查 DATA.experts 文本")

io.open(P, "w", encoding="utf-8").write(t)
print("长度:", orig, "->", len(t))
for d in done:
    print("  ✔", d)
print("pnid 锚点:", len(re.findall(r"<!--pnid:", t)), "| data-page-node-id:", len(re.findall(r"data-page-node-id=", t)))
