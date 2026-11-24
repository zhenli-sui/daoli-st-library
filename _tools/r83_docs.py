# -*- coding: utf-8 -*-
"""R83 文档增量：README 徽章 / CHANGELOG / VERSION / ROADMAP / EVOLOG（全追加式）"""
import json, os, re, datetime

LIB = r'C:\Library'
reg = json.load(open(os.path.join(LIB, 'INDEX_REGISTRY.json'), encoding='utf-8'))
comps = reg['components']
N = len(comps)
CNT = reg['counts']
jsonl = sum(1 for _ in open(os.path.join(LIB, '_AI_Training_Dataset', 'daoli_st_sft_dataset.jsonl'), encoding='utf-8'))
TODAY = 202
VER = 'v2.75.0'

# ---------- README ----------
p = os.path.join(LIB, 'README.md')
s = open(p, encoding='utf-8').read()
s2 = re.sub(r'(Total Components:\s*)(\d+)(\s*/\s*10,000)', r'\g<1>%d\g<3>' % N, s)
s2 = s2.replace('v2.74.0', VER)
s2 = re.sub(r'(SFT[^0-9]{0,12})(\d{3,5})', r'\g<1>%d' % jsonl, s2, count=2)
open(p, 'w', encoding='utf-8').write(s2)
print('README', 'changed' if s2 != s else 'nochange', N)

# ---------- CHANGELOG ----------
p = os.path.join(LIB, 'CHANGELOG.md')
add = """
## [%s] 2026-11-24 — R83 构建轮（下午轮 · 冲刺模式）

### Added
- 新增 %d 件（复杂 4 / 简单 36，五族模板派生）：印刷包装 8 / 纺织染整 8 / 表面处理电镀 7 / 输送分拣 7 / 仓储立库周边 6 + 复杂件 4（印刷套准自动调整、染批配方时序、电镀线行车转序、分拣分流握手恢复）。
- registry 总计 **%d**（DL_Base %d / DL_MathData %d / DL_Algo %d / DL_Device %d / DL_Motion %d / DL_Process %d）；SFT 语料 **%d** 行。

### Changed
- `dl_gate.py` 新增/校正静态锚点：`R509_FOR_DOWNTO` 存量审计口径（全库实测剩余 4 件，非 R82 估的 7 件）。

### Known Issues
- 4 件存量 `FOR..DOWNTO`（`FC_DL_DwordToHexString` / `FC_DL_LrealToFixedField` / `FC_DL_PolyEvalHorner` / `FB_DL_MarkPositionLatch`）仍待修，受「存量修复仅当日首轮 ≤4 件」配额约束顺延。
- R80 遗留 5 件逻辑 MAJOR 第 4 轮挂账。
""" % (VER, N - 1570, N, CNT['DL_Base'], CNT['DL_MathData'], CNT['DL_Algo'], CNT['DL_Device'], CNT['DL_Motion'], CNT['DL_Process'], jsonl)
open(p, 'a', encoding='utf-8').write(add)
print('CHANGELOG appended')

# ---------- VERSION ----------
for cat in ['DL_Process', 'DL_Algo', 'DL_Device', 'DL_MathData', 'DL_Motion']:
    vp = os.path.join(LIB, cat, 'VERSION')
    if os.path.exists(vp):
        with open(vp, 'a', encoding='utf-8') as f:
            f.write('%s | R83 | 2026-11-24 | +%d 件\n' % (VER, sum(1 for c in comps if c['category'] == cat and str(c.get('registered_at', ''))[:10] == '2026-11-24')))
print('VERSION appended')
