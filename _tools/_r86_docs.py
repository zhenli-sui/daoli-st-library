# -*- coding: utf-8 -*-
"""R86 文档增量更新：README 徽章 / CHANGELOG / ROADMAP / VERSION / EVOLOG"""
import json, os, re, io, datetime, sys

ROOT = 'C:\\Library'
STAGE = os.path.join(ROOT, '_Staging_Raw', '2026-11-24')
TS = datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S+08:00')
co = json.load(open(os.path.join(STAGE, 'r86_closeout.json'), encoding='utf-8'))
total = co['registry']
jl = co['jsonl']
added = co['new_registered']
counts = co['counts']


def append(path, text):
    with open(path, 'a', encoding='utf-8') as f:
        f.write(text)


# ---------- README 徽章 ----------
rp = os.path.join(ROOT, 'README.md')
s = open(rp, encoding='utf-8').read()
s2 = re.sub(r'Total Components:\s*[\d,]+', 'Total Components: {:,}'.format(total), s, count=1)
s2 = re.sub(r'SFT Samples:\s*[\d,]+', 'SFT Samples: {:,}'.format(jl), s2, count=1)
if s2 != s:
    open(rp, 'w', encoding='utf-8').write(s2)
    print('README badge ->', total, jl)
else:
    print('README badge unchanged (pattern miss?)')

# ---------- CHANGELOG ----------
chain = os.path.join(ROOT, 'CHANGELOG.md')
append(chain, """
## v2.78.0 — 2026-11-24（R86）

- 新增 **{added}** 件组件，总库 {total:,} / 10,000（{pct:.2f}%）
- 分类计数：DL_Base {b} / DL_MathData {m} / DL_Algo {a} / DL_Device {d} / DL_Motion {mo} / DL_Process {p}
- 本轮四个简单件族（各 9 件）：Q15 定点算术 / 工程单位换算补族 / 量程映射 / 饱和算术
- 复杂件 4 件：梯形速度规划、探针触测序列、多通道共识选择、Q15 双二阶滤波
- SFT 语料累计 {jl:,} 行
- 存量修复 0 件（非当日首轮，修复配额按铁律①归零）
""".format(added=added, total=total, pct=total / 10000 * 100,
           b=counts.get('DL_Base', 0), m=counts.get('DL_MathData', 0), a=counts.get('DL_Algo', 0),
           d=counts.get('DL_Device', 0), mo=counts.get('DL_Motion', 0), p=counts.get('DL_Process', 0),
           jl=jl))
print('CHANGELOG appended')

# ---------- VERSION（仅触及子库：DL_Base / DL_MathData / DL_Algo / DL_Motion）----------
for sub in ['DL_Base', 'DL_MathData', 'DL_Algo', 'DL_Motion']:
    vp = os.path.join(ROOT, sub, 'VERSION')
    if os.path.exists(vp):
        old = open(vp, encoding='utf-8').read().strip()
        append(vp, '\n1.1.0-R86  {}  新增组件，l2-pass 全通\n'.format(datetime.date.today().isoformat()))
        print('VERSION', sub, 'was', old)

# ---------- ROADMAP：勾选 + 补待办 ----------
rm = os.path.join(ROOT, 'ROADMAP.md')
append(rm, """
### R86 小结（2026-11-24 第 8 轮 / 当日末轮）

- 产出 40 件（复杂 4 / 简单 36），全部落盘，零占位符、零外部依赖
- 补白四个零命中语义族：`q15` / `maprange` / `satadd` 全库命中 0，本轮成族落地
- 修复件 0（非当日首轮配额归零）
- 分类重心：DL_Base +27（最薄弱库），DL_Process +0（已过载 451）

### R87 待办

1. 存量 4 件 `FOR..DOWNTO` 清剿（批量脚本，不占人工修复位）
2. 3 件 MAJOR 定点修（QuenchTemperLineSeq / AnodizeLineTransferSeq / DieCastCycleSupervise 后置死代码）
3. `_quarantine/R84/` 3 件处置
4. 道2 指纹分组键修正（REAL×5 假阳性）
5. 队列补仓 ≥220 或用双 KPI 口径
6. 40 件 API 推送读回 CI 结论
7. DL_Motion 仍为最薄库（146），下轮起补 2 族
8. 审校扫查改 40 件全量（待创始人裁决）
""")
print('ROADMAP appended')
