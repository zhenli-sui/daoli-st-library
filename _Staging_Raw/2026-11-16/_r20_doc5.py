# -*- coding: utf-8 -*-
"""R20 收口校正：码位口径表述 + 台账卫生待办合并"""

OLD_M = '> 全库码位跨文件重叠 = 0（终审脚本求差断言复跑）；**`16#0001_` 段游标推进至：信息级 `0434` / 故障级 `036C`**（与 `DL_Base` 共用同一游标）。'
NEW_M = ('> **R20 批次 100 槽（20 件 × 5 槽）跨文件零重叠**，终审求差断言复跑通过；`16#0001_` 段游标推进至 **信息级 `0434` / 故障级 `036C`**（与 `DL_Base` 共用同一游标）。\n'
         '> **口径说明（R20 诚实更正）**：全库并非绝对零重叠——`DL_Algo` 自 R3~R4 起存在 `16#0002_00xx` **公共码子带**（参数越界已钳位等通用语义，被多件刻意共享），与 `0001_` 段的专用码体系不冲突，但「全库零重叠」这一表述在该子带上不成立。已在 `ROADMAP.md §23.1` 挂账审计。')

for p in ('DL_MathData/VERSION.md', 'DL_Base/VERSION.md'):
    s = open(p, encoding='utf-8').read()
    assert OLD_M in s, p
    s = s.replace(OLD_M, NEW_M, 1)
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('fixed', p)

# BATTLE_REPORT 校验行
p = '_Staging_Raw/2026-11-16/BATTLE_REPORT_R20.md'
s = open(p, encoding='utf-8').read()
s = s.replace('| 码位游标 | 信息级 **0434** / 故障级 **036C**（全库求差断言零重叠） |',
              '| 码位游标 | 信息级 **0434** / 故障级 **036C**（R20 批 100 槽零重叠；全库另有 `DL_Algo 0002_00xx` 公共码子带为刻意共享，已挂账审计） |')
s = s.replace('3. 语料重注入：2 行按「定位 → 替换 output → 复核 thought → sha 复验 → registry 同步」五步执行；**342/344 字节级 MATCH + 2 条 CRLF 遗留（内容归一化后一致）**。',
              '3. 语料重注入：2 行按「定位 → 替换 output → 复核 thought → sha 复验 → registry 同步」五步执行；**342/344 字节级 MATCH + 2 条 CRLF 遗留（内容归一化后一致）**。\n'
              '4. 元数据债（如实登记，不在本轮动）：`line_count` 全库存在两种历史口径（102 条物理行 / 56 条含尾空行，R20 批内亦不一致）；`DL_Algo 0002_00xx` 公共码子带使「全库码位零重叠」表述不成立。两项均进 `ROADMAP §23.1`。')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('battle report fixed')

# ROADMAP：合并台账卫生两项到既有 P0 条目，保持新增 ≤10 条
p = 'ROADMAP.md'
s = open(p, encoding='utf-8').read()
old = '- [ ] **子库计数与注册表断言脚本化**：把 R86 的 Step 1 断言做成 `_verify_counts.py`（六库 VERSION 组件数 vs registry counts），每轮开轮即跑，杜绝 107/130 这类两处事实源漂移。'
new = ('- [ ] **台账卫生断言脚本化（R86 + 两项元数据债）**：产出 `_verify_counts.py`，一次跑三项断言——① 六库 VERSION 组件数 vs `registry.counts`（杜绝 107/130 这类漂移）；'
       '② `registry.line_count` 口径统一（全库现存两种历史口径：102 条物理行 / 56 条含尾空行，R20 批内亦不一致，统一为物理行并回写）；'
       '③ 码位唯一性按「专用码零重叠 + 公共码子带白名单」双规则判（`DL_Algo 16#0002_00xx` 为 R3~R4 遗留公共码，需建白名单而非改码，改码会破坏已发布契约）。')
assert old in s
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('roadmap merged')
