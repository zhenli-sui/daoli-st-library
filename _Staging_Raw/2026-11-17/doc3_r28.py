# -*- coding: utf-8 -*-
import io, re

def rd(p): return io.open(p, encoding='utf-8').read()
def wr(p, s): io.open(p, 'w', encoding='utf-8', newline='\n').write(s)

# --- ROADMAP：补勾 FanLawRootCalc（改名注记） ---
s = rd('ROADMAP.md')
m = re.search(r"^- \[ \] `FC_DL_FanLawRootCalc`", s, re.M)
if m:
    s = s[:m.start()] + "- [x] `FC_DL_FanLawRootCalc`" + s[m.end():]
    # 在该行行尾追加改名注记
    e = s.find("\n", m.start())
    s = s[:e] + "  ✔ R28 入库（撞名另立名：`FC_DL_FanLawMultiExpCalc`，跨子库同名编译阻断级）" + s[e:]
wr('ROADMAP.md', s)

# --- SOURCE_HUNTING_MATRIX：第 5 节表格行状态回写 ---
s = rd('SOURCE_HUNTING_MATRIX.md')
a = s.find("## 5 "); b = s.find("## 6 ")
head, sec, tail = s[:a], s[a:b], s[b:]
tags = ["T1-1", "T1-2", "T1-6", "T1-8", "T2-1", "T2-2", "T2-4", "T2-6", "T2-7", "T2-8"]
lines = sec.split("\n"); touched = []
for k, ln in enumerate(lines):
    if not ln.startswith("| ") or ln.count("|") < 4:
        continue
    cells = ln.split("|")
    src, st = cells[1], cells[2].strip()
    if not any(t in src for t in tags):
        continue
    if st not in ("☐", "◐"):
        continue
    if "R28" in ln:
        continue
    cells[2] = " ◐ " if st == "☐" else " ◐ "
    cells[-2] = cells[-2] + " ｜**R28 回写：本轮触及（件已入库，子族未满）**"
    lines[k] = "|".join(cells)
    touched.append(src.strip()[:38])
wr('SOURCE_HUNTING_MATRIX.md', head + "\n".join(lines) + tail)
print("matrix touched:", len(touched))
for t in touched: print("  ", t)
