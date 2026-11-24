# -*- coding: utf-8 -*-
"""R80 文档增量更新 + 战报生成（读取 _r80_facts.json）"""
import json, os, re, datetime

BASE = r"C:\Library"
STG = os.path.join(BASE, "_Staging_Raw", "2026-11-24")
F = json.load(open(os.path.join(STG, "_r80_facts.json"), encoding="utf-8"))

TOTAL = F["total"]              # 入库后总库
SFT = F["sft"]
TODAY = F["today"]
TODAY_PCT = round(TODAY * 100.0 / 300.0, 1)
TOTAL_PCT = round(TOTAL * 100.0 / 10000.0, 2)
VER = F["version"]

# ---------- README ----------
rp = os.path.join(BASE, "README.md")
s = open(rp, encoding="utf-8").read()
s2 = re.sub(r"Total%20Components-\d+%20%2F%2010", "Total%%20Components-%d%%20%%2F%%2010" % TOTAL, s)
s2 = re.sub(r"SFT%20Corpus-\d+%20records", "SFT%%20Corpus-%d%%20records" % SFT, s2)
s2 = re.sub(r"\*\*Total Components: [\d,]+ / 10,000 \([\d.]+%\)\*\*",
            "**Total Components: %s / 10,000 (%s%%)**" % (format(TOTAL, ","), TOTAL_PCT), s2)
s2 = re.sub(r"\*\*Version: v[\d.]+\*\*", "**Version: v%s**" % VER, s2)
s2 = re.sub(r"\*\*SFT 语料: \d+ 条\*\*", "**SFT 语料: %d 条**" % SFT, s2)
# 逐级徽章按 registry counts 校正
for cat, level in (("DL_Base", "Level%200%20DL--Base"), ("DL_MathData", "Level%200%20DL--MathData"),
                   ("DL_Algo", "Level%201%20DL--Algo"), ("DL_Device", "Level%201%20DL--Device"),
                   ("DL_Motion", "Level%201%20DL--Motion"), ("DL_Process", "Level%202%20DL--Process")):
    n = F["counts"].get(cat, 0)
    s2 = re.sub(re.escape(level) + r"-\d+%20open", level + "-%d%%20open" % n, s2)

summary = (
 "> **R80（2026-11-24 凌晨轮）**：**%d 件入册（复杂 %d + 简单 %d，5 族模板派生）**——简单 %d：称重配料族 8"
 "（毛净换算/皮重漂移/公差带/补料状态机/多头组合/批产率/蠕变补偿/量程标定）·液压气动族 8（缸推力/流量/蓄能器/Cv/沿程压降/建压斜坡/泄漏率）"
 "·制冷冷媒族 7（COP/过热度/过冷度/饱和压力温度双向表/输气量/逼近温差）·统计离散族 6（极差/IQR/pooled 标准差/滚动方差/几何均值/离差平方和）"
 "·水处理族 7（膜通量/TMP/回收率/污泥龄/溶解氧偏差/混凝投加/LSI）；复杂 %d（MultiTankBlendSeq·ConveyorMergePrioritySeq·DryerZoneProfileSeq·RefDefrostCycleSeq）；"
 "总库 %s→**%s**，v%s，SFT **%d**。**L2 闸：批 A %s + 批 B %s，终裁通过率 %s%%%s**；审校去重待回。"
)
line = summary % (F["n_new"], F["n_complex"], F["n_simple"], F["n_simple"],
                  F["n_complex"], format(F["total_before"], ","), format(TOTAL, ","), VER, SFT,
                  F["gate_a_str"], F["gate_b_str"], F["gate_rate"], F["gate_note"])
anchor = "> **R78（2026-11-23 夜间轮）**"
if anchor in s2:
    s2 = s2.replace(anchor, line + "\n\n" + anchor, 1)
else:
    s2 = s2.rstrip() + "\n\n" + line + "\n"
open(rp, "w", encoding="utf-8").write(s2)
print("README updated")

# ---------- CHANGELOG ----------
cp = os.path.join(BASE, "CHANGELOG.md")
cs = open(cp, encoding="utf-8").read()
head = "## v2.69.0 — 2026-11-23"
block = []
block.append("## v%s — 2026-11-24（R80 凌晨冲刺轮：%d 件入册 ｜ 5 族模板派生 ｜ L2 闸 %s）\n\n"
             % (VER, F["n_new"], F["gate_a_str"]))
block.append("### Added（%d 件：DL_Process %d / DL_Device %d / DL_MathData %d）\n"
             % (F["n_new"], F["counts_delta"]["DL_Process"], F["counts_delta"]["DL_Device"], F["counts_delta"]["DL_MathData"]))
block.append("- **复杂件 %d（C3~C4）**：%s\n" % (F["n_complex"], F["complex_list"]))
block.append("- **简单件 %d（C1~C2，5 族模板派生，单次调用批量写盘）**：%s\n\n" % (F["n_simple"], F["simple_list"]))
block.append("### Changed\n")
block.append("- 产能铁律四线执行：修复件 0（非当日首轮，配额归零）；简单件 %d/%d = %.0f%%；五族连号单次调用写盘；"
             "里程碑 T+1.5' 规划落盘 / T+%s 交付 %d 件 / T+%s 闸裁 / T+%s 收口。\n"
             % (F["n_simple"], F["n_new"], F["n_simple"] * 100.0 / F["n_new"],
                F["ms_coder"], F["n_simple"], F["ms_gate"], F["ms_close"]))
block.append("- 规划期族级词根穷举前置（R480/R79 教训）：40 个名称先做精确匹配，零撞名后才派单，规避 R79 的 22.8% 规划期损耗。\n")
block.append("- README 逐级徽章按 registry counts 校正（此前与 registry 存在系统性偏差）。\n\n")
if F.get("rejects"):
    block.append("### Rejected（%d 件，移入 `_quarantine/R80/`）\n" % len(F["rejects"]))
    for r in F["rejects"]:
        block.append("- `%s`：%s\n" % (r["name"], r["reason"]))
    block.append("\n")
if F.get("known_issues"):
    block.append("### Known Issues\n")
    for k in F["known_issues"]:
        block.append("- %s\n" % k)
    block.append("\n")
if head in cs:
    cs = cs.replace(head, "".join(block) + head, 1)
else:
    cs = cs.rstrip() + "\n\n" + "".join(block)
open(cp, "w", encoding="utf-8").write(cs)
print("CHANGELOG updated")

# ---------- VERSION files ----------
for cat in ("DL_Process", "DL_Device", "DL_MathData"):
    p = os.path.join(BASE, cat, "VERSION.md")
    if not os.path.exists(p):
        continue
    t = open(p, encoding="utf-8").read()
    t = t.rstrip() + "\n\n### R80（2026-11-24）\n- 新增 %d 件（%s），子库累计 %d 件。\n" % (
        F["counts_delta"][cat], F["cat_brief"][cat], F["counts"][cat])
    open(p, "w", encoding="utf-8").write(t)
print("VERSION updated")

# ---------- ROADMAP ----------
p = os.path.join(BASE, "ROADMAP.md")
t = open(p, encoding="utf-8").read()
t = t.rstrip() + "\n\n" + F["roadmap_block"] + "\n"
open(p, "w", encoding="utf-8").write(t)
print("ROADMAP updated")

# ---------- EVOLOG ----------
p = os.path.join(BASE, "AGENT_EVOLUTION_LOG.md")
t = open(p, encoding="utf-8").read()
t = t.rstrip() + "\n\n" + F["evolog_block"] + "\n"
open(p, "w", encoding="utf-8").write(t)
print("EVOLOG updated")

# ---------- BATTLE REPORT ----------
open(os.path.join(STG, "BATTLE_REPORT_R80.md"), "w", encoding="utf-8").write(F["battle"])
print("BATTLE_REPORT written")
open(os.path.join(STG, "Feishu_R80.md"), "w", encoding="utf-8").write(F["feishu"])
print("Feishu written")
