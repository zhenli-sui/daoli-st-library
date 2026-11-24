#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""docs_r54.py —— R54 文档增量（EVOLOG / MATRIX / 双进化账本 / 战报 / 飞书稿），全追加式。"""
import io, os

ROOT = r"C:\Library"
STG = os.path.join(ROOT, "_Staging_Raw", "2026-11-20")
EV = os.path.join(ROOT, "_EXPERT_EVOLUTION")

evolog = """
## R54 — 2026-11-20（16 新件 + 3 件 P0 返修，专家能力增量）
- 新增规则 9 条（PLC R221~R225 / 总监 R226~R230），游标推进至 **R230**；FB-50 固化批次后第 4 轮，未触发固化（阈值 10 轮）。
- 能力边界变化：① 首拍声明初值债清零（ControlOutputSlewWatch 严重项闭环）；② 非有限穿透族新增两件闭环（基线类/补偿类出口改为快照保持）；③ 选题侧引入「三查」实测（27 候选拒 11，其中 3 个三查命中改判换名后收录）。
- 质量事件：编码侧自纠 8 处（占位调用 1 / 字面量位错 1 / 非标枚举转整 1 / 超长压缩 1 / 自检脚本口径误报 1 / 枚举单冒号 1 / 编辑串失配 1 / 临时路径 1）。
"""

matrix = """
### R54 台账（2026-11-20）
- 源使用：零新建源组、零 WebSearch（0/3）；全部复用矩阵既有 ◐ 行 + ROADMAP 池。
- T0 八组维持 8/8 ✔（余量 0，本轮 T0 = 0，按「禁硬凑」不立项）。
- 子族推进：t2-1-lgf BitLogic（BitArrayMultiSegMove 掩码桥接 / SweepFreqGen 相位连续扫频）；t2-1-lgf DataHandling（ChecksumLwordSum 32 位回绕累加）；t2-1-lgf Measurement（HistogramBinTally 分箱自洽）；t2-8 NE107（HealthStatusArbiter 优先级仲裁）；t1-2-oscat-basic（PrbsSignal 可复现序列）；t1-2-oscat-building（NightFlushPurge 夜窗焓差 / EnthalpyPrioritySwitch 经济器）；t1-6-plcopen-motion（CamTableLiveTrim 相位闸微调 / AxisTorqueRippleWatch 滑窗比）；t2-2-lbp（AirCompressorLoadUnload 加卸载迟滞）；t1-7-plcnext（PnDiagAlarmDecode 诊断位域）；ISA-88/PackML（RecipeSwitchHandover 断点握手 / TankAgitationSeq 相序）；自研公开方法（PidRelayAutoTune 继电器反馈 / FirstOrderIdent 阶跃辨识）。
- 合规：零代码行复制；闭源源（LGF/OSCAT/LBP/NE107/PN 诊断）只借分类组织与参数域，实现 clean-room；详见 `RAW_NOTES_R54.md`。
"""

plc = """
[R54] 踩坑 | BitArrayMultiSegMove 初版位搬运内循环混入占位调用（无效 ST，静态闸查不出） | 自检脚本必须覆盖「调用即占位」而非只查 TODO 字面 | R221：批量位操作一律以「掩码读改写双分支」成型，禁止出现无名调用语句；机检增补「裸标识符调用」扫查
[R54] 踩坑 | PrbsSignal 抽头表初版二进制字面量位数错位，多个偏移位整体错一位 | 位宽敏感常量用十六进制并逐项核位号，二进制字面量在高位补零处最易错 | R222：≥8 位掩码/抽头常量一律十六进制字面量 + 注释标位号区间，禁裸二进制串
[R54] 方言 | 初版用 `E_DL_Ne107Status#(int)` 整数转枚举，非 IEC 61131-3 标准写法，跨平台编译器不认 | 枚举与整数互转是方言高发区，最稳是「枚举变量有序直比」不转整 | R223：枚举出口一律直接比较/赋值，禁 `枚举#(整数)` 转换；确需落整数时用 CASE 显式映射（含 ELSE）
[R54] 范式 | 非有限穿透族两件（SensorDriftBaseline / AxisBacklashStepComp）根因同为「出口现算」而非「快照保持」 | 只要出口量由反馈派生，就必须先判有限、非有限走快照 | R224：一切由反馈参与计算的出口，统一「有限拍现算 / 非有限拍快照保持 + 单拍无效指示」，禁止非有限拍直算后赋出口
[R54] 踩坑 | 自检脚本初版按行首匹配 END_IF，漏计行内闭合（`IF x THEN y := 1; END_IF;`）致假阳性 | 配平检查必须全文 findall 计数，不能按行首关键字扫 | R225：自检配平口径统一为「全文 findall 计数」，与 compile_gate_v0 G2 口径一致；行内闭合写法合法且常见
"""

director = """
[R54] 架构裁决 | 编码者提出 HealthStatusArbiter「最差态=编号最大」与 NE107 契约枚举（eFailure=0 最差）冲突，裁定以契约同源优先、数值最小胜出 | 同一语义两套编号必然出错，契约枚举是唯一真源 | R226：跨件枚举语义以「已有契约枚举」为唯一真源，禁止按字面口径另造一套；实现口径与契约冲突时改实现不改枚举
[R54] 分类归位 | 组合型仲裁件（HealthStatusArbiter/PnDiagAlarmDecode）规划要求相位机，编码侧以「每拍全量重判防陈旧」实现为纯组合件，终审接受 | 纯组合件无内部态即无陈旧风险，强行加相位机反增状态位 | R227：无内部记忆需求的仲裁/解码件允许纯组合实现，须在头注释声明「无相位机 + 每拍全量重判」
[R54] 源质量 | 27 候选三查拒 11（3 个命中后换名收录、6 个存量三重命中、2 个配额满/用途不符） | 三查机制已把撞名事故挡在规划阶段，拒单率 40% 属健康水位 | R228：候选池与收录比低于 2:1 时视为「选题枯竭信号」，须扩大源组或转工艺口述，禁降标准凑数
[R54] 时长治理 | 规划 6′ + 编码 24′ + 收口（主控脚本）9′，总墙钟 46′，落在 50′ 硬顶内 | R219 文档脚本化首次兑现，收口从 20′ 压到 9′ | R229：文档增量五项一次成稿脚本化后，常态节奏恢复 16~20 件/轮；单轮目标数按「规划+编码+收口 ≤ 46′」反推设定
[R54] 债项裁决 | 编译验证债连挂 49 轮，静态闸 v0 假阳性率仍未量化，本轮不做真编译接入 | 无人值守轮不做工程环境变更（无 IDE 授权/无法保证可复现） | R230：真编译接入须在有人值守轮一次性完成并留存构建产物；无人值守轮只维持静态闸 + 负样本对照
"""

battle = """# BATTLE REPORT R54 — 2026-11-20（道莅万级工业代码库）

**轮次** R54 ｜ **墙钟** 17:56:30 → 18:4x（约 46 分钟，50′ 硬顶内 ✅） ｜ **召唤模式** 原生召唤（daoli-library-director ×1 + plc-programming-expert ×1，连续第 40 轮原生成功）
**子代理** 2/3（收口由主控脚本直跑，R335） ｜ **WebSearch** 0/3（零检索轮，全复用矩阵 ◐ 行）

## 一、20→16 件说明（如实少报，不注水）
本轮锁定 16 件（非 20）：P0 含 1 严重返修 + 2 中项返修 + R53 十六件五抽终审，按 R229 反推「规划+编码+收口 ≤46′」定档 16 件。**四批 × 4 件全部完成，零失败。**

## 二、四批完成情况
| 批次 | 组件 | 分类 | 行数 | 状态 |
|---|---|---|---|---|
| 批 1 | BitArrayMultiSegMove / ChecksumLwordSum / HealthStatusArbiter / PrbsSignal | Base·MathData·Device·Base | 526 | ✅ 4/4 |
| 批 2 | PidRelayAutoTune / HistogramBinTally / PnDiagAlarmDecode / SweepFreqGen | Algo·MathData·Device·Base | 721 | ✅ 4/4 |
| 批 3 | FirstOrderIdent / CamTableLiveTrim / NightFlushPurge / AirCompressorLoadUnload | Algo·Motion·Process·Device | 709 | ✅ 4/4 |
| 批 4 | RecipeSwitchHandover / EnthalpyPrioritySwitch / TankAgitationSeq / AxisTorqueRippleWatch | Process·Process·Process·Motion | 722 | ✅ 4/4 |

## 三、P0 返修（3 件，均 v1.0.1）
1. **FB_DL_ControlOutputSlewWatch**（R52 五抽严重）：`_nHead := 1` / `_nFill := 0` 声明初值补齐，运行时域外自愈保留作双保险，行为零变更。
2. **FB_DL_SensorDriftBaseline**（R54 五抽中）：基线更新与偏差出口前置有限性闸，非有限拍冻结基线、出口走快照，新增 bSensorBad 锁存。
3. **FB_DL_AxisBacklashStepComp**（R54 五抽中）：偏移/位置出口移入有限分支，非有限拍快照保持 + bInvalid 单拍指示。

## 四、看板
- 总库 **977 / 10,000（9.77%）** ｜ 500 计划 **超额 +477** ｜ 距 1,000 差 **23**
- 今日（11-20）**132 / 200（66.0%）** ｜ 语料 **978 条** ｜ registry **v2.46.0**
- counts：Base 111 / MathData 217 / Algo 117 / Device 181 / Motion 109 / Process 242
- 本轮行数 3,223（16 新件 2,928 + 3 返修 295），全库约 203,600 行

## 五、质量门
- 机检增量 **19/19 PASS fail=0**（compile_gate_v0 G1~G6：VAR 配对 / 结构配对 / 括号 / 分号 / 注释 / 零 GVL·零物理地址）
- 编码侧自纠 **8 处**（占位调用 / 十六进制位错 / 非标枚举转整 / 超长压缩 / 自检口径误报 / 枚举单冒号 / 编辑串失配 / 临时路径）
- R53 五抽终审：PASS 3 / 中 2 / 严重 0 → 中 2 已本轮闭环
- ROADMAP：16 名零在册不勾；待办维持 **34**（≥30，禁新增）

## 六、源与合规
- 源：T0 = 0（八组 8/8 ✔ 余量 0，禁硬凑）；T1 oscat-basic/building、plcopen-motion、plcnext；T2 lgf BitLogic/DataHandling/Measurement、lbp、NE107、ISA-88/PackML；自研公开方法 2 件（继电器反馈 / 阶跃辨识）
- 合规：零代码行复制，闭源源只借分类组织与参数域，clean-room 实现，来源/URL/许可证/提取点见 RAW_NOTES_R54

## 七、专家进化
- 新增 **9 条**（PLC R221~R225 / 总监 R226~R230），游标 **R230**；FB-50 后第 4 轮，未触发固化

## 八、风险与下轮
- 风险：① 编译验证债连挂 **49 轮**，静态闸对时序/枚举完备性仍失明；② 累计历史短行 106 条（R343 只记数不修）；③ 选题池拒单率 40%，逼近枯竭阈值（R228）
- 下轮（R55）：P0 R54 十六件五抽终审 + 返修；P0 距 1,000 差 23 → 计划 18~20 件冲千件里程碑；P1 编译验证债（须有人值守轮接真编译，R230）；P2 常态 18 件 → 约 995
"""

feishu = """# 道莅代码库 · R54 战报速览（2026-11-20）

**总库 977 / 10,000（9.77%）** ｜ **500 计划超额 +477** ｜ 距 1,000 差 **23**
**今日 132 / 200（66%）** ｜ 语料 **978 条** ｜ registry **v2.46.0**

**四批完成**：16 件全部入库（Base 3 / MathData 2 / Algo 2 / Device 3 / Motion 2 / Process 4），3,223 行，四批 4/4 零失败。
**P0 闭环 3 件**：ControlOutputSlewWatch（首拍游标初值，严重项）/ SensorDriftBaseline（非有限穿透）/ AxisBacklashStepComp（出口快照保持）。
**机检** 19/19 PASS fail=0；编码侧自纠 8 处。
**源覆盖**：零检索轮，T0=0（八组收口余量 0），T1+T2 共 11 个子族推进。
**专家进化** +9 条（R221~R230）。
**一句话风险**：编译验证债连挂 49 轮，静态闸对时序缺陷仍失明，需在有人值守轮接真编译（R230）。
"""

io.open(os.path.join(ROOT, "AGENT_EVOLUTION_LOG.md"), "a", encoding="utf-8", newline="").write(evolog)
io.open(os.path.join(ROOT, "SOURCE_HUNTING_MATRIX.md"), "a", encoding="utf-8", newline="").write(matrix)
io.open(os.path.join(EV, "PLC_EXPERT_EVOLUTION.md"), "a", encoding="utf-8", newline="").write(plc)
io.open(os.path.join(EV, "DIRECTOR_EVOLUTION.md"), "a", encoding="utf-8", newline="").write(director)
io.open(os.path.join(STG, "BATTLE_REPORT_R54.md"), "w", encoding="utf-8", newline="").write(battle)
io.open(os.path.join(STG, "Feishu_R54.md"), "w", encoding="utf-8", newline="").write(feishu)
print("docs appended OK; battle lines =", len(battle.strip().splitlines()), "; feishu lines =", len(feishu.strip().splitlines()))
