# -*- coding: utf-8 -*-
"""R80 收尾后补记：语料漂移事件（登记后源码被重写）"""
import json, os, datetime

BASE = r"C:\Library"
STG = os.path.join(BASE, "_Staging_Raw", "2026-11-24")

ADD = """
## 11. 收尾后补记（06:06 追加）—— 语料漂移事件与处置

**事件**：复杂件编码席在 06:05:15~06:05:38 对 4 个复杂件做**收尾自检后重写**，晚于本批登记时刻（06:02:52）。后果是 JSONL 语料快照停留在重写前版本（4/4 漂移：MultiTank −23 字节、Conveyor −929、Dryer −226、Defrost −999），磁盘件与语料件已非同一份。

**处置（已全部完成）**：
1. 复核两处闸建议最小修仍在盘（MultiTank L240 含 `NOT bAbort`；Defrost L142 为「应转未转」单向窗）——**未被覆盖**；
2. 对重写后版本**复跑 L2**：`PASS=4 FAIL=0`，结论仍成立；
3. 按 `meta.name` 重同步 4 行语料 `output`，复验 4/4 `SAME`，语料总行数不变（1,529）。

**性质判定**：非质量事故（编译与逻辑结论均未变），属**写盘时序竞态 + 语料快照未加校验**。根因是「登记读文件」与「编码席继续写文件」之间没有互斥约束。

**新规则（R504）**：**登记后禁止再改源码**。若确需修改，必须 ① 重跑 L2 闸 ② 重同步该件 JSONL `output` ③ 在战报记一行。语料同步应由「登记时读一次」升级为「收尾时按 name 全量比对一次」，机检锚点 = `jsonl.output != file_read(name)` 即告警。
"""

p = os.path.join(STG, "BATTLE_REPORT_R80.md")
t = open(p, encoding="utf-8").read().rstrip()
open(p, "w", encoding="utf-8").write(t + "\n" + ADD)
print("battle report appended")

# CHANGELOG known issue
cp = os.path.join(BASE, "CHANGELOG.md")
s = open(cp, encoding="utf-8").read()
old = "- MatIEC-CI 第 12 轮顺延"
new = ("- **语料漂移已修复**：4 个复杂件在 06:05 被编码席收尾自检重写（晚于 06:02:52 登记），"
       "JSONL 快照落后一版；已复跑 L2（4/4 PASS）并按 name 重同步 `output`，复验 4/4 一致。"
       "新规则 R504：登记后禁止改源码，改则必复闸 + 重同步语料。\n"
       "- MatIEC-CI 第 12 轮顺延")
if old in s and "语料漂移已修复" not in s:
    s = s.replace(old, new, 1)
    open(cp, "w", encoding="utf-8").write(s)
    print("changelog appended")

# EVOLOG rule R504
ep = os.path.join(BASE, "_EXPERT_EVOLUTION", "DIRECTOR_EVOLUTION.md")
t = open(ep, encoding="utf-8").read().rstrip()
t += ("\n- `[R80]` **R504** 流程 | 复杂件编码席收尾自检在 06:05 重写 4 件，晚于 06:02:52 登记 → JSONL 语料快照落后一版"
      "（4/4 漂移，累计 −2,177 字节），磁盘与语料已非同一份；复跑 L2 仍 4/4 PASS，重同步后修复 | "
      "**登记后禁止再改源码**；确需修改必须复跑 L2 + 重同步语料 `output` + 战报记一行。"
      "语料同步从「登记时读一次」升级为「收尾时按 name 全量比对」，机检锚点 = `jsonl.output != file_read(name)` | R504\n")
open(ep, "w", encoding="utf-8").write(t)
print("evolog R504 appended")

open(os.path.join(BASE, "_EXPERT_EVOLUTION", "_cursor.txt"), "w", encoding="utf-8").write(
    "R504\n# 全局规则编号游标：下一个可分配 = R505（R80 尾）；五席不得自行起编（R483）\n")
print("cursor -> R504")
