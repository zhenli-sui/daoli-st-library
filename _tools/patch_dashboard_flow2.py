# -*- coding: utf-8 -*-
"""流程图第二轮微调：去掉 emoji（渲染成方块）改为色条徽标；修正三处标注压线。"""
import io
import sys

P = sys.argv[1]
t = io.open(P, encoding="utf-8").read()
done = []


def rep(a, b, name):
    global t
    if a not in t:
        raise SystemExit("❌ 未命中：" + name)
    t = t.replace(a, b, 1)
    done.append(name)


# 1) 节点模板：去 emoji，改色条 + 标题上行
OLD = """  return '<g class="fnode" data-si="'+si+'" style="cursor:pointer">'
   +'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" rx="14" fill="'+c+'16" stroke="'+c+'" stroke-width="1.4" stroke-opacity=".65"/>'
   +'<text x="'+cx+'" y="'+(y+24)+'" text-anchor="middle" font-size="16">'+ic+'</text>'
   +'<text x="'+cx+'" y="'+(y+45)+'" text-anchor="middle" font-size="13" font-weight="600" fill="#e8f2ff">'+ti+'</text>'
   +'<text x="'+cx+'" y="'+(y+63)+'" text-anchor="middle" font-size="9.5" fill="#8ba0c4" font-family="Consolas,monospace">'+sb+'</text>'
   +'</g>';"""
NEW = """  return '<g class="fnode" data-si="'+si+'" style="cursor:pointer">'
   +'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" rx="14" fill="'+c+'16" stroke="'+c+'" stroke-width="1.4" stroke-opacity=".65"/>'
   +'<rect x="'+x+'" y="'+(y+13)+'" width="3.5" height="'+(h-26)+'" rx="2" fill="'+c+'" opacity=".9"/>'
   +'<text x="'+cx+'" y="'+(y+33)+'" text-anchor="middle" font-size="13.5" font-weight="600" fill="#e8f2ff">'+ti+'</text>'
   +'<text x="'+cx+'" y="'+(y+53)+'" text-anchor="middle" font-size="9.5" fill="#8ba0c4" font-family="Consolas,monospace">'+sb+'</text>'
   +'</g>';"""
rep(OLD, NEW, "节点去 emoji 改色条")

# 2) 标注位置修正
rep("""'<text x="302" y="150" font-size="10.5" fill="#5f739a">↓ 40 件目标下发后，件沿主链单向流动</text>'""",
    """'<text x="40" y="150" font-size="10.5" fill="#5f739a">↓ 40 件目标下发后，件沿主链单向流动，每段交接都有唯一方向</text>'""",
    "注记左移")

rep('l:"派工 40 件配额（复杂≤12 / 简单≥28）", lx:345, ly:172',
    'l:"派工 40 件配额（复杂≤12 / 简单≥28）", lx:352, ly:169',
    "派工标注微调")

rep('l:"FAIL 单 · 回派 S6", lx:700, ly:392',
    'l:"FAIL 单 · 回派 S6", lx:672, ly:386',
    "FAIL 标注避线")

# 3) 节点定义去掉图标字段影响（保留数组结构，图标位不再使用）
rep("""  S0:[550,46,200,76,"#22d3ee","🎯","S0 主控","dlf-lead · 派工/终审/入库/复盘",6],
  S1:[40,280,170,76,"#38bdf8","🗺️","S1 规划查重","dlf-planner",0],
  S3:[302,280,170,76,"#fbbf24","⌨️","S3 编码","dlf-builder",2],
  S4:[564,280,170,76,"#f87171","🚦","S4 编译闸","dlf-gatekeeper",3],
  S5:[826,280,170,76,"#a78bfa","🔍","S5 审校去重","dlf-inspector",4],
  AR:[1088,280,170,76,"#34d399","📦","S0 注册入库","registry·JSONL·ROADMAP",6],
  S2:[302,470,170,76,"#34d399","🕸️","S2 供料 · 按需","dlf-sourcer",1],
  S6:[826,470,170,76,"#fb923c","🔧","S6 定点修复","dlf-fixer",5]""",
    """  S0:[550,46,200,76,"#22d3ee","","S0 主控 · 派工与终审","dlf-lead · 入库 / 文档 / 复盘",6],
  S1:[40,280,170,76,"#38bdf8","","S1 规划查重","dlf-planner",0],
  S3:[302,280,170,76,"#fbbf24","","S3 编码","dlf-builder",2],
  S4:[564,280,170,76,"#f87171","","S4 编译闸 · 一票否决","dlf-gatekeeper",3],
  S5:[826,280,170,76,"#a78bfa","","S5 审校去重","dlf-inspector",4],
  AR:[1088,280,170,76,"#34d399","","S0 注册入库","registry·JSONL·ROADMAP",6],
  S2:[302,470,170,76,"#34d399","","S2 供料 · 按需","dlf-sourcer",1],
  S6:[826,470,170,76,"#fb923c","","S6 定点修复","dlf-fixer",5]""",
    "节点标题加长去图标")

io.open(P, "w", encoding="utf-8").write(t)
print("长度 ->", len(t))
for d in done:
    print("  ✔", d)
