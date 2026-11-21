# -*- coding: utf-8 -*-
"""R40 文档增量：README 徽章 / CHANGELOG 顶部节 / 两个 VERSION.md 追加 / 矩阵 R40 行 / 进化账本 R40 节"""
import io, os, glob

LIB = "C:/Library"
NEW_MATH = ["FC_DL_MaxNanEx", "FC_DL_MinNanEx", "FC_DL_RealEqTolEx", "FC_DL_RangeCheckEx",
            "FC_DL_RealToDintSat", "FC_DL_RealToRealSat", "FC_DL_RoundBankEx", "FC_DL_DegToRadEx",
            "FC_DL_RadToDegEx", "FC_DL_MuxIntEx", "FC_DL_StringToLowerEx", "FC_DL_StringToUdintEx",
            "FC_DL_IndexClampEx"]
NEW_BASE = ["FB_DL_SrEx", "FB_DL_RsEx"]

def rd(p):
    return io.open(p, encoding="utf-8").read()

def wr(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)

# 1. README.md
p = os.path.join(LIB, "README.md")
s = rd(p)
newlines = sum(len(rd(os.path.join(LIB, c, n + ".st")).splitlines())
               for c, ns in (("DL_MathData", NEW_MATH), ("DL_Base", NEW_BASE)) for n in ns)
s = s.replace("Total%20Components-690", "Total%20Components-705")
s = s.replace("SFT%20Corpus-690", "SFT%20Corpus-705")
s = s.replace("**Total Components: 690 / 10,000**", "**Total Components: 705 / 10,000**")
s = s.replace("**Version: v2.31.0**", "**Version: v2.32.0**")
s = s.replace("**SFT 语料: 690 条**", "**SFT 语料: 705 条**")
s = s.replace("全库约 151,479 行", "全库约 %s 行" % format(151479 + newlines, ","))
wr(p, s)
print("README ok, +%d lines -> %s" % (newlines, format(151479 + newlines, ",")))

# 2. CHANGELOG.md 顶部追加
p = os.path.join(LIB, "CHANGELOG.md")
s = rd(p)
sec = """## v2.32.0 — 2026-11-19（R40 / T0 防御包装轮）

### Added（15 新件，20 目标中 5 个与在册件重复被剔除，如实少报）
- DL_MathData（+13）：FC_DL_MaxNanEx / FC_DL_MinNanEx / FC_DL_RealEqTolEx / FC_DL_RangeCheckEx / FC_DL_RealToDintSat / FC_DL_RealToRealSat / FC_DL_RoundBankEx / FC_DL_DegToRadEx / FC_DL_RadToDegEx / FC_DL_MuxIntEx / FC_DL_StringToLowerEx / FC_DL_StringToUdintEx / FC_DL_IndexClampEx
- DL_Base（+2）：FB_DL_SrEx / FB_DL_RsEx
- 全部为 T0 iec-std-wrapper 防御包装（委托内建/平台语义，不自研内核）；剔除明细：FC_DL_LimitEx / FC_DL_TimeAddSat / FC_DL_TimeScaleSat / FB_DL_EdgeDivider / FB_DL_TpEx 与在册件同名。

### Changed
- INDEX_REGISTRY.json v2.31.0 → v2.32.0，total 705；JSONL 语料 690 → 705 条（新增 15 行 output 与磁盘源码逐字节一致）。
- 机检 15/15 PASS（禁 GVL/VAR_EXTERNAL、禁 %I/%Q、ENUM 冒号、CASE 缺 ELSE、注释嵌套、VAR_OUTPUT、TON/R_TRIG 条件分支刷新、CRLF、码位重复）。

"""
s = s.replace("## v2.31.0 — 2026-11-19（R39 / 20 新件 + 3 返修轮）", sec + "## v2.31.0 — 2026-11-19（R39 / 20 新件 + 3 返修轮）", 1)
wr(p, s)
print("CHANGELOG ok")

# 3. 两个 VERSION.md 追加
for cat, ns in (("DL_MathData", NEW_MATH), ("DL_Base", NEW_BASE)):
    p = os.path.join(LIB, cat, "VERSION.md")
    s = rd(p)
    if not s.endswith("\n"):
        s += "\n"
    s += "\n## R40（2026-11-19）— +%d（%s）\n\n- 本轮增量已入册（registry v2.32.0），机检全 PASS；详见 CHANGELOG v2.32.0。\n" % (
        len(ns), " / ".join(ns))
    wr(p, s)
    print(cat + "/VERSION.md ok")

# 4. SOURCE_HUNTING_MATRIX.md 追加 R40 行
p = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
s = rd(p)
if not s.endswith("\n"):
    s += "\n"
s += "| R40 | T0 零检索轮（15 新 + 5 重复剔除） | 消耗 T0 iec-std-wrapper 余量 15 件（零 WebSearch/零仓库抓取）；剔除 5 目标：FC_DL_LimitEx / FC_DL_TimeAddSat / FC_DL_TimeScaleSat / FB_DL_EdgeDivider / FB_DL_TpEx 与在册件同名 | 15 件（MaxNanEx / MinNanEx / RealEqTolEx / RangeCheckEx / RealToDintSat / RealToRealSat / RoundBankEx / DegToRadEx / RadToDegEx / MuxIntEx / StringToLowerEx / StringToUdintEx / SrEx / RsEx / IndexClampEx）——T0 组 ☐→✔ 推进，T0 余量清账；机检 15/15 PASS |\n"
wr(p, s)
print("MATRIX ok")

# 5. AGENT_EVOLUTION_LOG.md 追加 R40 节
p = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
s = rd(p)
if not s.endswith("\n"):
    s += "\n"
s += """
## R40 专家能力增量（2026-11-19）
- 新增规则 10 条（总监 R240~R244 / PLC R245~R249），游标 R250；未固化轮次累计 4 轮（未达固化阈值）。
- 总监线：R240 T0 选题先查在册同名件，重复目标派单前剔除（本轮 5 件即此闸拦下）；R241 码位段由派单单预分配、专家按文件头落位，收口代理只读不重排；R242 组件分类以落盘物理路径为准，清单口径与磁盘不一致时磁盘优先；R243 收口轮文档只做增量（追加/改数字），严禁重写既有章节；R244 战报挂账必须逐条续转，不得轮间静默清账。
- PLC 线：R245 非有限判定统一自不等/差值自减口径，禁近似幅值阈值；R242 转换类包装溢出必须饱和钳位不得抛错；R247 字符串转换先过字符域闸再走数值解析；R248 S/R 双稳态同拍置复按优先级裁决并置信息级码；R249 索引类包装越界饱和到合法域并在头注声明缺省值。
- 能力边界：本轮 15 件全部 T0 防御包装，机检零 FAIL，零返修；ROADMAP 中 15 件名零匹配，T0 包装线不占既有待办、不补写。
"""
wr(p, s)
print("EVO ok")
