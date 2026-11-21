# -*- coding: utf-8 -*-
"""R45 文档增量：README / CHANGELOG / 六子库 VERSION / 源矩阵 / 双专家账本 / AGENT_LOG / 战报 / 飞书稿。
全部追加式或定点改数字，不重写既有章节。
"""
import os, io, datetime

L = r"C:\Library" + "\\"
def rd(p):  return open(p, encoding="utf-8", newline="").read()
def wr(p, s): open(p, "w", encoding="utf-8", newline="").write(s)
def app(p, s):
    t = rd(p)
    if not t.endswith("\n"): t += "\n"
    wr(p, t + s)

# ---------------- README：仅改数字 ----------------
p = L + "README.md"; r = rd(p)
r = r.replace("Total%20Components-785%20%2F%2010%2C000-blue", "Total%20Components-805%20%2F%2010%2C000-blue")
r = r.replace("SFT%20Corpus-786%20records", "SFT%20Corpus-806%20records")
r = r.replace("**Total Components: 785 / 10,000**", "**Total Components: 805 / 10,000**")
r = r.replace("**Version: v2.36.0**", "**Version: v2.37.0**")
r = r.replace("**SFT 语料: 786 条**", "**SFT 语料: 806 条**")
wr(p, r)
print("README", "805" in r, "2.37.0" in r)

# ---------------- CHANGELOG：头部插入 v2.37.0 ----------------
p = L + "CHANGELOG.md"; c = rd(p)
anchor = "## v2.36.0 — 2026-11-19"
sec = """## v2.37.0 — 2026-11-19（R45 / 零检索轮 20 新件 + 2 返修）

### Added（20 新件：DL_Algo +5 / DL_Motion +5 / DL_Base +3 / DL_Device +3 / DL_Process +3 / DL_MathData +1）
- DL_Base（+3）：FB_DL_Vote2oo3 / FB_DL_EdgeOrderCheck / FB_DL_AlarmFloodLimiter
- DL_MathData（+1）：FC_DL_CubicBezierEval（De Casteljau 求值与一阶导，纯函数零状态）
- DL_Algo（+5）：FB_DL_KalmanFilter1D / FB_DL_TensionObserver / FB_DL_StictionCompensator / FB_DL_LoopPerfIndex / FB_DL_ThermalRampPredict
- DL_Motion（+5）：FB_DL_AxisDualFeedbackGuard / FB_DL_AxisSs1StopSeq / FB_DL_AxisTeachOffset / FB_DL_AxisInertiaIdent / FB_DL_AxisRotaryShortPath
- DL_Device（+3）：FB_DL_SafetyRelayFeedback / FB_DL_ContactorWeldDetect / FB_DL_FlowSwitchResponseCheck（故障级新开 07xx 子带 0701~0703）
- DL_Process（+3）：FB_DL_SlurryMixingSeq / FB_DL_FrameSealDispenseSeq / FB_DL_BoilerBlowdownSeq

### Fixed（2 返修，PATCH 引脚契约零变更）
- FB_DL_CalenderRollPress v1.0.0 → v1.0.1：双侧同步判据加相位窗 `_bSyncWin`，消除 eIdle/eRelease 误锁 039F 与 eDone 不可达；5 个组态实数补 NaN 自反判；5 处故障分支补 bError 配对。
- FB_DL_IvCurveScan v1.0.0 → v1.0.1：复位沿按相分域；FF 计算上移段 0 单次求解 `_fFfPu`，删除同一 FC 同参双调用；eEval 改双出口，消除相位无迁出与 eDone 相 FF 恒 0。

### Verified（机检 + 收口）
- 机检 22/22 PASS，fail=0；码位全库实扫（783 件存量）零冲突；本轮交付 5,391 行。
- registry 785 → 805（v2.36.0 → v2.37.0）；counts：Base 87 / MathData 199 / Algo 87 / Motion 82 / Device 155 / Process 195。
- JSONL 786 → 806 条，badjson=0，新增 20/20 MATCH，2 返修件原地重注入 MATCH。

### Notes
- 零检索轮（WebSearch 0/3），全部复用源矩阵既有 ◐ 行，无新开组、无 ◐→✔ 收口。
- 编译验证债连续 42 轮挂账；ROADMAP 三向一致专项（空勾与 registry 差额）转下轮。
"""
assert anchor in c
c = c.replace(anchor, sec + "\n" + anchor, 1)
wr(p, c)
print("CHANGELOG", "v2.37.0" in c)

# ---------------- 六子库 VERSION ----------------
vers = [
 ("DL_Base", "v1.21.0", "R45：+3 新件（Vote2oo3 / EdgeOrderCheck / AlarmFloodLimiter）｜码位 16#0001_03EA~03ED / 04AD~04B0｜机检 3/3 PASS"),
 ("DL_MathData", "v1.24.0", "R45：+1 新件（FC_DL_CubicBezierEval）｜码位 16#0001_03ED / 04B0｜6 控制点+导数纯函数"),
 ("DL_Algo", "v1.19.0", "R45：+5 新件（KalmanFilter1D / TensionObserver / StictionCompensator / LoopPerfIndex / ThermalRampPredict）｜码位 16#0002_03AF~03B3 / 04B2~04B6"),
 ("DL_Motion", "v1.17.0", "R45：+5 新件（AxisDualFeedbackGuard / AxisSs1StopSeq / AxisTeachOffset / AxisInertiaIdent / AxisRotaryShortPath）｜码位 16#0004_03B4~03B8 / 04B4~04B8"),
 ("DL_Device", "v1.18.0", "R45：+3 新件（SafetyRelayFeedback / ContactorWeldDetect / FlowSwitchResponseCheck）｜故障级新开 07xx 子带 16#0003_0701~0703 / 信息 0480~0482"),
 ("DL_Process", "v1.20.0", "R45：+3 新件（SlurryMixingSeq / FrameSealDispenseSeq / BoilerBlowdownSeq）+ 2 返修 v1.0.1（CalenderRollPress / IvCurveScan，引脚契约零变更）｜码位 16#0005_03A6~03A8 / 04CE~04D0"),
]
for sub, v, note in vers:
    p = L + sub + "\\VERSION.md"
    app(p, "\n## %s — 2026-11-19（R45）\n\n- %s\n" % (v, note))
    print("VERSION", sub, v)

# ---------------- SOURCE_HUNTING_MATRIX：仅追加 R45 行 ----------------
p = L + "SOURCE_HUNTING_MATRIX.md"
row = ("| R45 | 零检索轮（WebSearch 0/3，20 新 + 2 返修） | 全部复用既有 ◐ 行：t2-8-isa182（报警抑制 / 安全回路一致性）+ "
       "t2-1-lgf-math/technology + t2-5-modpid + t1-6-plcopen + t2-4-s7-motion + t2-6-rockwell-aoi + t2-2-lbp + "
       "t1-2-oscat-building + 自研线/自研行业池（锂电前段·光伏组件）；无 ☐→◐ 开组、无 ◐→✔ 收口 | "
       "20 件（Vote2oo3 / EdgeOrderCheck / AlarmFloodLimiter / CubicBezierEval / KalmanFilter1D / TensionObserver / "
       "StictionCompensator / LoopPerfIndex / ThermalRampPredict / AxisDualFeedbackGuard / AxisSs1StopSeq / AxisTeachOffset / "
       "AxisInertiaIdent / AxisRotaryShortPath / SafetyRelayFeedback / ContactorWeldDetect / FlowSwitchResponseCheck / "
       "SlurryMixingSeq / FrameSealDispenseSeq / BoilerBlowdownSeq）+ 2 返修（CalenderRollPress / IvCurveScan v1.0.1）◐ 深化；"
       "零 T0 件，Device 故障级新开 07xx 子带 |\n")
app(p, "\n" + row)
print("MATRIX appended")

# ---------------- PLC 专家账本 ----------------
p = L + "_EXPERT_EVOLUTION\\PLC_EXPERT_EVOLUTION.md"
plc = """## R45（2026-11-19 · 编码自纠 11 条提炼 5 条，游标 R284 起）
- [R284] 代码踩坑 | FB_DL_BoilerBlowdownSeq 在 CASE 相内直接调用 `tonInterval`（R228A 违规）→ 删除调用，改段 0 无条件刷新 + 相位派生 IN | CASE 内实例调用会让 TON 的 IN 跨相断拍，计时不可预测 | 新规则：CASE 内禁止出现 TON/R_TRIG 实例调用，只允许读 Q/ET 与写 IN 派生量；机检对「CASE 段内实例名(」直接 FAIL
- [R285] 防御范式 | FB_DL_AxisDualFeedbackGuard / AxisSs1StopSeq 出口量在相内自赋值驻留（本拍不写即保留上拍值）→ 改显式双出口，每拍全路径赋值 | 驻留式出口把「相位未覆盖」变成隐式状态，复位后可能带出旧值 | 新规则：相内出口变量必须每拍显式赋值；IF/ELSIF 链必须带 ELSE 兜底，禁「不写即驻留」
- [R286] 逻辑缺陷 | FB_DL_AxisRotaryShortPath 解除式写成单因子且恒假（R152 反例）→ 拆 `_bSolved ∨ 目标角本身在软限内` 双分支 | 解除式与锁存条件同源取反时，锁存态永远无法解除 | 新规则：解除式每个因子须给出可满足场景并写自证句；禁把锁存判据直接取反当解除条件
- [R287] 接口缺陷 | FB_DL_LoopPerfIndex 内核调用 OUT 实参留空 → 补声明 `_bConvErr`/`_bConvValid` 接收 | 留空 OUT 实参在部分平台告警、在另一些平台静默丢弃错误位，转换失败不可观测 | 新规则：实例调用的每个 OUT 实参必须落变量，未使用的输出也须显式接收并注释「不使用原因」
- [R288] 模板残留 | FB_DL_KalmanFilter1D 首写含占位符（整件覆写）；FB_DL_ThermalRampPredict 隐式转换写反（LREAL_TO_REAL → REAL_TO_LREAL） | 占位符与转换方向是复制模板的两类高频残留，机检只能兜住前者 | 新规则：落盘前全文扫 TODO/占位/「同上」；REAL↔LREAL 转换逐处核对目标类型，禁凭记忆写函数名
"""
app(p, "\n" + plc)
print("PLC_EVO appended")

# ---------------- 总监账本 ----------------
p = L + "_EXPERT_EVOLUTION\\DIRECTOR_EVOLUTION.md"
dirs = """## R45（2026-11-19 · 规划侧 5 条，游标 R289 起）
- [R289] 选题纪律 | T0 七组全收口后，本轮 20 件全部转向 ROADMAP 真缺口与既有 ◐ 技术族，零 T0 件 | T0 清零不是选题终点，而是选题基线切换点：从「补标准包装」转为「补行业真缺口」 | 新规则：T0 收口后的选题基线 = ROADMAP 空勾 ∩ registry 未注册 ∩ 真实工况需求，三者同时成立才立项
- [R290] 反证机制 | 反证句三处比对（registry 精确名 ∪ 文件树 ∪ ROADMAP 文本）拦下 11 件候选，其中 6 件为「registry 已注册但 ROADMAP 仍空勾」 | 只查 ROADMAP 会把已交付件当缺口重复立项；只查 registry 会漏掉同义变体 | 新规则：反证必须三处比对，registry 命中即拒（ROADMAP 空勾不作为立项依据），同义邻件逐条留档
- [R291] 存量债 | ROADMAP 120 条空勾中 35 条已注册（三向不一致），本轮按「>30 条不补写」维持只读 | 空勾与 registry 的差额是账本口径债，不是选题缺口；批量回填风险高于收益 | 新规则：三向一致专项单独立轮（脚本对账 + 人工复核），专项轮不做编码；常态轮只读不写 ROADMAP 待办
- [R292] 流程前置 | 2 件返修件的终审记录只写缺陷与版本，未写物理分类；收口前须先按 file_path 核 `DL_Process` 再定批次与子库 VERSION | 返修件分类错位会导致 VERSION/JSONL/registry 三处记错库 | 新规则：返修派单与收口前先核 file_path 与 category 一致；终审记录必须带物理路径，禁只写组件名
- [R293] 源复用 | 零检索轮 20 件来源标签全部可回指既有 ◐ 行（isa182 / lgf / modpid / plcopen / s7-motion / aoi / lbp / oscat / 自研池），无新开组 | 零检索不等于零台账：复用行也须逐轮落矩阵，否则下一轮无法证明「未新开源」 | 新规则：零检索轮必须在 SOURCE_HUNTING_MATRIX 追加本轮行并列出复用 ◐ 行；连续两轮未落行即视为台账断链
"""
app(p, "\n" + dirs)
print("DIR_EVO appended")

# ---------------- AGENT_EVOLUTION_LOG ----------------
p = L + "AGENT_EVOLUTION_LOG.md"
log = """## R45（2026-11-19）专家能力增量
- 新增规则：10 条（PLC R284~R288 / 总监 R289~R293），累计游标 R294（下轮起）。
- 固化批次：未触发（累计 6 轮未固化，距 10 轮阈值尚差 4 轮）。
- 要点：T0 全收口后选题基线切换到 ROADMAP 真缺口（R289）；反证三处比对拦下 11 件（6 件为 ROADMAP 空勾但已注册，R290）；ROADMAP 三向一致差额 35 条转专项（R291）；返修件先核物理分类（R292）；零检索轮仍须落源矩阵行（R293）。PLC 侧：CASE 内禁实例调用（R284）、相内出口禁驻留（R285）、解除式禁同源取反（R286）、OUT 实参禁留空（R287）、占位符与转换方向逐处核（R288）。
- 能力边界：机检 22/22 PASS 且码位全库实扫零冲突；机检新增「CASE 内实例调用」红线后，本轮编码侧 1 处同类违规被自纠拦截。语义层残余（解除式可满足性、复位沿作用域）仍需终审两式推演。
- 本轮零检索（0/3）、零外部源码，合规无新增风险；编译验证债连续 42 轮未开闸。
"""
app(p, "\n" + log)
print("AGENT_LOG appended")
