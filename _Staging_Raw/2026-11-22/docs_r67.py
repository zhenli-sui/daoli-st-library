# -*- coding: utf-8 -*-
"""R67 文档增量：README 徽章+摘要行 / CHANGELOG 节 / 3×VERSION / MATRIX 台账 / EVOLOG 节（全追加式）"""
import io, re

LIB = r"C:\Library"

def rd(p): return io.open(p, encoding="utf-8").read()
def wr(p, s): io.open(p, "w", encoding="utf-8", newline="").write(s)

# ---------- 1. README ----------
p = LIB + r"\README.md"
s = rd(p)
s = s.replace("Total%20Components-1155", "Total%20Components-1163")
s = s.replace("DL--Base-143", "DL--Base-145")
s = s.replace("DL--MathData-272", "DL--MathData-278")
s = s.replace("SFT%20Corpus-1179", "SFT%20Corpus-1190")
s = s.replace("**Total Components: 1,155 / 10,000 (11.55%)**", "**Total Components: 1,163 / 10,000 (11.63%)**")
s = s.replace("**Version: v2.58.0**", "**Version: v2.59.0**")
s = s.replace("**SFT 语料: 1,179 条**", "**SFT 语料: 1,190 条**")
r67_line = ("> **R67（2026-11-22）**：**11/12 如实少报**——3 件点修（QuadPolyFit v1.0.1 舒尔补主元闸 + 矩量溢出复核扩展 / "
 "LotMergeGate v1.0.1 eFault 死迁出删除 / TaktPaceMonitor v1.0.2 fExpectR 闸界 DINT 域对齐，R66 挂账清零）"
 "+ 8 新件（Base 2：LastGoodValueHold 失效值保持·ImpulseRelay 定宽脉冲｜MathData 6：CalcDistance2D·AngleDiffRad·NormTo01·SlewRateCalc·HexToStr·StrToHex，"
 "后两件 T0 防御性包装）；TriangleGenerator 撞名 R39 注册件裁定撤销（R327 三查失准教训）；"
 "总库 1,155→**1,163**（145/278/134/207/121/278），SFT **1,190**（+8 新 +3 返修重注入），机检 11/11 PASS，零检索轮。\n")
# 摘要行区：插在 R66 摘要行之后
m = re.search(r"> \*\*R66（2026-11-22）\*\*.*?\n", s)
assert m, "R66 summary line not found"
s = s[:m.end()] + r67_line + s[m.end():]
wr(p, s)
print("README OK")

# ---------- 2. CHANGELOG ----------
p = LIB + r"\CHANGELOG.md"
s = rd(p)
sec = """## v2.59.0 — 2026-11-22（R67 八件入册 + R66 挂账点修三件清零 ｜ 零检索轮）

### Added（8 件：DL_Base 2 / DL_MathData 6）
- DL_Base 2 件：`FB_DL_LastGoodValueHold`（传感器失效值保持：NE43 失效冻结最后有效值 + 陈旧超限置码，载体锁存/透传双轨不混用）｜`FB_DL_ImpulseRelay`（沿触发定宽脉冲输出，重触发重启全程脉宽）
- DL_MathData 6 件：`FC_DL_CalcDistance2D`（2D 距离，Hypot 缩放防溢出）｜`FC_DL_AngleDiffRad`（弧度角最短带符号差，跨 ±π 回绕）｜`FC_DL_NormTo01`（线性归一化 0..1，反向域/零域/钳位三码分立）｜`FC_DL_SlewRateCalc`（采样间变化率，dt 有效性前置闸）｜`FC_DL_HexToStr`（字节串→HEX 文本，T0 防御性包装，整字节截断）｜`FC_DL_StrToHex`（HEX 文本→字节串，三面错误码 + 失败零写入原子性，T0 防御性包装）

### Fixed（R66 挂账点修 3 件，当轮清零）
- `FC_DL_QuadPolyFit` v1.0.1：段 7 回代前补舒尔补主元闸（`ABS(aM[2,2]) < QPF_PIV_MIN` → 码 03，两相异 x 值正规方程秩 2，原除零 NaN/Inf 错归码 02）；段 4 ABS 溢出复核扩至 s1/s2/s3/t0/t1 全部矩量
- `FB_DL_LotMergeGate` v1.0.1：删除 eFault 分支死迁出式 `IF NOT _bFaultLatch → eIdle`（R323/R320 族：故障相出口只留复位沿）；L2 留档防御保留
- `FB_DL_TaktPaceMonitor` v1.0.2：fExpectR 闸界 4.294967295E9 → 2147483647（DINT 转换链域对齐，常量 `TPM_DINT_MAX` 显式声明）

### Changed
- 三角波发生器撞名裁定：`FB_DL_TriangleGenerator` 与 R39 注册件（DL_Algo 02_3_87）重名，撤销本轮目标、未覆盖入库（宁少勿滥，11/12 如实少报）；三查流程失准登记总监 R327
- SFT 语料返修重注入 3 条（上述点修件新版本源码），语料 1,179 → **1,190**（bad=0）
- 本轮零检索轮（WebSearch 0 次），取材复用源矩阵既有组：lgf-math / lgf-technology / ne43 / oscat-basic / iec-std-wrapper

"""
anchor = "## v2.58.0"
i = s.index(anchor)
s = s[:i] + sec + s[i:]
wr(p, s)
print("CHANGELOG OK")

# ---------- 3. VERSION files ----------
def append_version(cat, ver, lines):
    p = LIB + "\\" + cat + r"\VERSION.md"
    s = rd(p)
    s += "\n## %s — 2026-11-22（R67 追加）\n\n" % ver
    for ln in lines:
        s += "- " + ln + "\n"
    wr(p, s)
    print("VERSION OK:", cat)

append_version("DL_Base", "v1.38", [
    "新增 2 件：`FB_DL_LastGoodValueHold`（失效值保持 + 陈旧置码，ne43 族）｜`FB_DL_ImpulseRelay`（沿触发定宽脉冲，oscat-basic 借鉴 clean-room）。",
    "子库累计 145 件。",
])
append_version("DL_MathData", "v1.38", [
    "新增 4 件纯函数：`FC_DL_CalcDistance2D`（Hypot 缩放防溢出）/ `FC_DL_AngleDiffRad`（跨 ±π 最短角差）/ `FC_DL_NormTo01`（三码分立归一化）/ `FC_DL_SlewRateCalc`（变化率诊断测量，lgf-technology）。",
    "新增 2 件 T0 防御性包装：`FC_DL_HexToStr` / `FC_DL_StrToHex`（HEX 互转，委托平台字符串内建，IEC 标准语义溯源标注，iec-std-wrapper）。",
    "点修 `FC_DL_QuadPolyFit` → v1.0.1（舒尔补主元闸 + 矩量溢出复核扩展，R66 挂账）。",
    "子库累计 278 件。",
])
append_version("DL_Process", "v1.35", [
    "点修 2 件：`FB_DL_LotMergeGate` → v1.0.1（删除 eFault 死迁出式，故障相出口只留复位沿）｜`FB_DL_TaktPaceMonitor` → v1.0.2（fExpectR 闸界 DINT 域对齐 2147483647）。R66 挂账清零。",
    "子库组件数不变（278 件）。",
])

# ---------- 4. MATRIX ledger ----------
p = LIB + r"\SOURCE_HUNTING_MATRIX.md"
s = rd(p)
m67 = ("> **R67 一行（2026-11-22，零检索轮）**：WebSearch **0 次**。本轮 5 组取材——lgf-math ◐→◐（+3 CalcDistance2D/AngleDiffRad/NormTo01）、"
 "lgf-technology ◐→◐（+1 SlewRateCalc）、ne43 ◐→◐（+1 LastGoodValueHold，进侧信号族反演）、oscat-basic ◐→◐（+1 ImpulseRelay）、"
 "iec-std-wrapper ✔（+2 HexToStr/StrToHex，T0 防御性包装收口）。无 ☐→◐ 开组；TriangleGenerator 撞名 R39 注册件撤销（lgf-signalgen 组该行不动）；"
 "三查流程失准登记 R327（判重必须对 registry 实时精确匹配并留痕）。\n")
anchor = "> **R66 一行（2026-11-22，零检索轮）**"
i = s.index(anchor)
j = s.index("\n", s.index("。\n", i)) if False else None
# 插到 R66 行末尾（R66 行是单行）
e = s.index("\n", i) + 1
s = s[:e] + m67 + s[e:]
wr(p, s)
print("MATRIX OK")

# ---------- 5. EVOLOG ----------
p = LIB + r"\AGENT_EVOLUTION_LOG.md"
s = rd(p)
sec = """

## R67（2026-11-22 · 挂账清零 + 撞名裁定轮，游标 R324 → R328）
**构成**：3 点修（QuadPolyFit v1.0.1 / LotMergeGate v1.0.1 / TaktPaceMonitor v1.0.2，R66 挂账全数当轮清零）+ 8 新件（Base 2 / MathData 6，含 T0 包装 2 件）；TriangleGenerator 撞名 R39 注册件 → 裁定撤销，11/12 如实少报。机检 11/11 PASS，零检索轮。

**四条新规（详见双账本 R325~R328）**：①HEX 字符判别禁 STRING_TO_BYTE 字母歧义解析，一律 MID 查表（R325）；②定宽输出截断按完整编码单元取整，禁半单元残尾（R326）；③撞名三查必须对 registry 实时精确匹配留痕，禁规划期记忆判重（R327）；④挂账点修占配额首位，新件按余额裁减，点修清零是配额回调前置（R328）。

**固化窗口**：FB-51 后第 7 轮，新增 4 条 <10 → 不固化，下窗口 R70 或增量 ≥10。
"""
s += sec
wr(p, s)
print("EVOLOG OK")
print("ALL DOCS DONE")
