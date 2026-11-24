# -*- coding: utf-8 -*-
"""R86 云端看板数据区刷新（只改 work_dir/index.html，不碰本地权威外副本）"""
import json, re, sys, io

W = r'C:\Users\Administrator\AppData\Local\Temp\1\workbuddy-page-edit-uxvfxekf\index.html'
reg = json.load(open(r'C:\Library\INDEX_REGISTRY.json', encoding='utf-8'))
counts = reg['counts']
import collections
cc = collections.Counter(c['complexity'] for c in reg['components'])
today = len([c for c in reg['components'] if c.get('registered_at', '') >= '2026-11-24'])
total = len(reg['components'])
assert total == sum(counts.values())

s = open(W, encoding='utf-8').read()
orig = s
changes = []


def rep(old, new, tag):
    global s
    if old not in s:
        print('MISS:', tag, '|', old[:70])
        return False
    s = s.replace(old, new, 1)
    changes.append(tag)
    return True


# 1) cats 计数
for k in ['DL_MathData', 'DL_Process', 'DL_Device', 'DL_Base', 'DL_Algo', 'DL_Motion']:
    m = re.search(r'\{k:"%s", n:"[^"]*", c:(\d+)' % k, s)
    if m:
        s = s[:m.start(1)] + str(counts[k]) + s[m.end(1):]
        changes.append('cats.' + k)

# 2) cmplx
def fix_cmplx():
    global s
    for lvl in range(1, 10):
        m = re.search(r'\["C%d",\d+,' % lvl, s)
        if m:
            s = s[:m.start()] + '["C%d",%d,' % (lvl, cc.get(lvl, 0)) + s[m.end():]
    changes.append('cmplx')
fix_cmplx()

# 3) rounds 追加 R81~R86
rounds = [['R81', 40], ['R82', 40], ['R83', 39], ['R84', 37], ['R85', 40], ['R86', 39]]
m = re.search(r'\["R80",37,"11-24"\]', s)
if m:
    add = ''.join(',["%s",%d,"11-24"]' % (a, b) for a, b in rounds)
    s = s[:m.end()] + add + s[m.end():]
    changes.append('rounds+6')

# 4) stages 实际状态
rep('stt:"R80 落盘 T+4′"', 'stt:"R86 落盘 T+2′"', 'stages.1.stt')
rep('ag:"daoli-oss-hunter",st:"ok",stt:"真跑采集 ✔"',
    'ag:"dlf-oss-hunter",st:"ok",stt:"225 条（绿163/黄62/红0）"', 'stages.2.ag')
rep('ag:"plc-programming-expert",st:"ok",stt:"37 件批量写盘"',
    'ag:"plc-programming-expert（原名回退）",st:"ok",stt:"40 件 / 8′ 单次写盘"', 'stages.3.ag')
rep('ag:"daoli-compile-verifier",st:"ok",stt:"终裁 100% · 零豁免"',
    'ag:"daoli-compile-verifier（原名回退）",st:"ok",stt:"40/40 PASS · 零豁免"', 'stages.4.ag')
rep('ag:"daoli-qa-dedup",st:"ok",stt:"12 项扫查全过"',
    'ag:"daoli-qa-dedup（原名回退）",st:"ok",stt:"全量 40 件 · 拒收 1"', 'stages.5.ag')
rep('stt:"三数一致 diff 0"', 'stt:"1,725 / 1,764 / 1,725"', 'stages.6.stt')

# 5) bottles 刷新
old_b = re.search(r'bottles:\[.*?\],\s*todos:\[', s, re.S)
if old_b:
    new_b = ('bottles:[\n'
             '    ["R86","逻辑正确性收口占 38%（规划 8/编码 28/闸 26/审校+复核 38/收口 18）","审校 BLOCK 必附源码原文行，一轮把误判率 25% → 0%"],\n'
             '    ["R86","日目标 300 与 3h/轮结构不匹配（第 10 次提出）","实际达成靠「每日 8 轮」堆叠，需创始人裁决降目标或加密轮次"],\n'
             '    ["R86","DL_Motion 仍为最薄库（146），本轮仅 +2","R87 起对 Motion 补 2 族 ×9 件"]\n'
             '  ],\n  todos:[')
    s = s[:old_b.start()] + new_b + s[old_b.end():]
    # 替换 todos 内容
    m2 = re.search(r'todos:\[.*?\],\s*today:', s, re.S)
    new_t = ('todos:[\n'
             '    ["P0","存量 4 件 FOR..DOWNTO 清剿（批处理脚本，不占修复位）"],\n'
             '    ["P0","3 件 MAJOR 定点修：QuenchTemperLineSeq / AnodizeLineTransferSeq / DieCastCycleSupervise 后置死代码"],\n'
             '    ["P1","_quarantine/R84 3 件 + R86 1 件（SatSubDint 真重复）处置"],\n'
             '    ["P1","道2 指纹分组键修正（REAL×5 假阳性）"],\n'
             '    ["P1","团队包三席未注册：重启 WorkBuddy 使 dlf-plc-coder / dlf-compile-verifier / dlf-qa-dedup 生效"],\n'
             '    ["P2","审校扫查 13 件抽样 → 40 件全量（待创始人裁决）"]\n'
             '  ],\n  today:[')
    s = s[:m2.start()] + new_t + s[m2.end():]
    changes.append('bottles+todos')

# 6) today 追加 R86
m = re.search(r'\["R80",37,"05:41 → 06:08","27′","[^"]*"\]', s)
if m:
    s = s[:m.end()] + ',["R86",39,"21:16 → 21:42","26′","简单 36 + 复杂 4 · 拒收 1（真重复）· L2 100% · 当日 317/300"]' + s[m.end():]
    changes.append('today+R86')

# 7) ticker
m = re.search(r'ticker:\[[^\]]*\]', s)
if m:
    new_tk = ('ticker:["FB_DL_TrapezoidProfilePlanner · 梯形/三角速度规划（R86）",'
              '"FB_DL_AxisProbeTouchOffSeq · 探针触测序列（R86）",'
              '"FB_DL_SensorConsensusSelector · 多通道共识选择（R86）",'
              '"FB_DL_Q15BiquadFilter · Q15 定点双二阶（R86）",'
              '"FC_DL_Q15MulSat · Q15 乘法饱和（R86）",'
              '"FC_DL_MapRangeClamped · 量程映射钳位（R86）",'
              '"FC_DL_SatAddDint · DINT 加法饱和（R86）"]')
    s = s[:m.start()] + new_tk + s[m.end():]
    changes.append('ticker')

# 8) 页脚（一致性铁律：页脚 = cats 合计 = registry）
m = re.search(r'<footer[^>]*>.*?</footer>', s, re.S)
if m:
    old_f = m.group(0)
    pnid = re.search(r'<!--pnid:([A-Za-z0-9]+)-->', old_f)
    keep = '<!--pnid:%s-->' % pnid.group(1) if pnid else ''
    tag = re.match(r'<footer[^>]*>', old_f).group(0)
    new_f = ('%s道莅工业代码库工厂 · 云端权威版（唯一维护入口，本地副本仅作草稿）· '
             '数据截至 2026-11-24 21:42 · 数据源 INDEX_REGISTRY.json（%s 件 / 今日 %d）· '
             'R86 已完成（当日 317/300，105.7%%）· SFT 语料 1,764 行</footer>'
             % (tag + keep, format(total, ','), today))
    s = s[:m.start()] + new_f + s[m.end():]
    changes.append('footer')

open(W, 'w', encoding='utf-8').write(s)
print('changed:', len(changes), changes)
print('size', len(orig), '->', len(s))
print('total=%d today=%d' % (total, today))
