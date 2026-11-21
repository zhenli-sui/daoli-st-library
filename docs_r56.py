#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""docs_r56.py —— R56 文档增量（EVOLOG / MATRIX / 双进化账本 / 战报 / 飞书稿），全追加式。"""
import io, os, json

ROOT = r"C:\Library"
STAGE = os.path.join(ROOT, "_Staging_Raw", "2026-11-20")
reg = json.load(io.open(os.path.join(ROOT, "INDEX_REGISTRY.json"), encoding="utf-8"))
total, counts = reg["total_components"], reg["counts"]
sft = sum(1 for l in io.open(os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl"), encoding="utf-8").read().splitlines() if l.strip())

def app(path, text):
    io.open(path, "a", encoding="utf-8", newline="").write(text)

# ---------------- 1. PLC 进化账本 ----------------
app(os.path.join(ROOT, "_EXPERT_EVOLUTION", "PLC_EXPERT_EVOLUTION.md"), """
## R56（2026-11-20/21 · 20 新件 + 5 返修，游标 R240~R244）
[R56] 踩坑 | R55 遗留的 `_nCurRetry` 未声明属编译阻断级，静态语法闸逐行看均「像合法语句」 | 标识符未声明时文件读起来完全正常，人眼与行级闸都失效，只有声明集合与引用集合做差集才能暴露 | R240：落盘机检增设 F 检项「声明区完整性」——抽取 VAR 区标识符集合与函数体标识符出现集合求差，差集非空即 PASS=FALSE；每批末必跑
[R56] 范式 | FB_DL_BacdHvacPoll 段 7 `ELSIF _nUseCount < 1` 恒假（该量在段 3 已回钳 ≥1），eNoDevice 成因永不可达 | 回钳之后再用回钳值判「越下限」是结构性死分支，且在真机上表现为「某些故障永不报」 | R241：任何对已回钳量做「越界判定」的 IF/ELSIF 视为死分支候选，改用原始引脚量判定或删除并注释留痕；机检增补「回钳变量名复现于后续比较式」扫查
[R56] 算法 | FB_DL_FopdtStepIdent 切线法用绝对值斜率求截距，负向阶跃死区时间被系统性高估（两点法不受影响故只在 bUseTangent 分支暴露） | 几何量的「量级」与「符号」是两种用途，绝对值只能进量级闸，不能进坐标运算 | R242：凡涉及坐标/截距/位移的算式，先声明带符号量（SIGN 乘回），绝对值量仅用于「> EPS」类量级守卫，两量分名不复用
[R56] 范式 | FB_DL_StringElImageMap 复位只清故障与统计，漏清「最近一次」类快照出口，复位后旧坐标残留在出口 | 「最近一次 XX」出口最容易在复位清单里被漏掉，因为它不在「计数器/标志」的直觉分类里 | R243：复位作用域清单化——按出口声明区逐条过，凡「Last/最近/上次」语义出口一律纳入复位清单；机检增补「复位段清零标识符数 ≥ 出口声明数 × 0.6」下限提示
[R56] 踩坑 | 本批自纠 9 处中 4 处为占位/半成品残留（占位 IF、半成品重写、无效占位行、恒假分支），均能通过行级语法闸 | 长批次（25 件）末段最容易出现「先搭骨架后忘填」的残件，且语法闸对「能编译但语义空」完全无感 | R244：落盘前必跑禁止词扫查（TODO/占位/待补/同上/类似/TBD），命中即整件返工；批 3 起每批末强制执行，不依赖编码侧记忆
""")

# ---------------- 2. 总监进化账本 ----------------
app(os.path.join(ROOT, "_EXPERT_EVOLUTION", "DIRECTOR_EVOLUTION.md"), """
## R56（2026-11-20/21 · 突破千件轮，游标 R245~R249）
[R245] 配额裁决 | T0 八组全 ✔（余量 0）时，本轮 20 件配额按六库全覆盖分配（Base 2/MathData 5/Algo 3/Device 4/Motion 3/Process 3），Process 已 260 件被压到 ≤3 | 长尾失衡比单轮产量更伤库结构，Process 单库占比已 26% | R245：T0=0 轮次的配额令固定为「六库全覆盖 + 单库 ≤6 + 占比最高库 ≤3」，写入规划表头
[R246] 撞名三查 | 本轮 8 个目标名在 ROADMAP 命中，实为「（R56 新立）」后续任务行而非存量件 | 三查的 ROADMAP 一查必须区分「组件本体行」与「引用该组件的后续任务行」，否则 planner 会误判撞名而错杀好题 | R246：ROADMAP 查重只认「组件本体行」模式（行首 `- [ ] \\`FB_DL_Xxx\\`：` 或 `- [x] \\`FB_DL_Xxx\\`：`），引用行不计入撞名
[R247] 收口事故 | closeout 脚本按「行内含组件名」勾选 ROADMAP，把 8 条「落地后评估/补对照段」的后续任务行误勾为已完成 | 子串匹配在「组件名被后续任务引用」时必然误勾，属收口脚本的结构性缺陷（R335 主控直跑后首次暴露） | R247：ROADMAP 勾选必须用本体行锚定正则 `^- \\[ \\] \\*\\*[^｜]*｜\\`NAME\\`：` ，且勾选后回读断言「待办数减少量 = 预期勾选数」，不等即回滚
[R248] 语料治理 | 5 件返修件若只改 .st 不重注入，语料里留的是缺陷版源码，训练集会被污染 | 返修闭环必须含语料侧，否则「库内已修、语料未修」形成隐性双版本 | R248：返修件强制 JSONL 重注入，并在 instruction 末尾追加「（vX.Y.Z 返修版：见 REVIEW_RNN 修法）」标记供追溯
[R249] 节奏裁决 | 单调用 25 件（20 新 + 5 返修）编码 26′ + 规划 4′ + 收口 12′，墙钟仍超 50′ 硬顶 | 25 件已超单编码代理的舒适区，长批次末段残件率上升（R244 实证 4 处） | R249：返修件 ≥4 件的轮次，新件目标下调至 16 件；或拆为「返修轮 / 新建轮」交替，禁在单轮同时背 25 件
""")

# ---------------- 3. AGENT_EVOLUTION_LOG ----------------
app(os.path.join(ROOT, "AGENT_EVOLUTION_LOG.md"), """
### R56（2026-11-20/21）—— 突破 1,000 件里程碑轮
- 产出 20 新件 + 5 件 v1.0.1 返修；registry 997 → **%d**，JSONL %d 条，机检 25/25 PASS。
- 召唤模式：原生 daoli-library-director ×1 + plc-programming-expert ×1（单调用 4 批 20 件 + 5 返修）；收口主控脚本直跑（R335）。
- 专家能力增量：PLC +5 条（R240~R244：声明区完整性 F 检项 / 死分支识别 / 带符号几何量 / 复位清单化 / 占位扫查）；总监 +5 条（R245~R249：配额令 / 撞名三查区分 / 勾选锚定正则 / 返修语料重注入 / 25 件超载裁决）。累计新增 10 条，游标 R250；FB-50 后第 5 轮，未触发固化。
- 能力边界变化：机检从「行级语法」扩到「声明集合差集 + 死分支候选 + 复位覆盖度」三类语义近似检查，静态闸首次覆盖 R55 编译阻断根因。
- 事故与处置：收口脚本子串匹配误勾 8 条后续任务行，回读断言缺失；已全量回滚并立 R247（勾选锚定正则 + 数量断言）。
""" % (total, sft))

# ---------------- 4. SOURCE_HUNTING_MATRIX 台账 ----------------
app(os.path.join(ROOT, "SOURCE_HUNTING_MATRIX.md"), """
### R56 台账（2026-11-20/21 · 突破千件轮）
- 零新增检索（WebSearch 0/3）：20 件全部复用矩阵既有 ◐ 行与 ROADMAP 池，无 ☐→◐ 开组；T0 八组维持 8/8 ✔（余量 0，本轮 T0 = 0，按禁硬凑不立项）。
- 子族推进：t2-1-lgf-math（Hermite 插值 / 四元数 Slerp / 有效数字取整 三件，插值·姿态·舍入三线并行）｜t2-1-lgf-converter（EStopDualChannel 双通道一致性 / SignalSeqGuard 时序守卫）｜t2-5-modpid（TwoDofPid 设定值加权，与单自由度件分工写死）｜t1-6-plcopen（AccelFeedforward 前馈 / CantileverComp 重力补偿 / ProbeMeasCycle 测量循环）｜t2-2-lbp（AccumPreChg / IonizerBalance / FanVfdBypassSwap / HotRunnerZoneBalance / SlurrySieveClogWatch / LossInWeightFeeder / UvDoseCtrl / UltrasonicWeldCtrl / AirShowerInterlockSeq 九件，设备级监视与顺控为主）｜roadmap-r56 自研（RTD CVD 反解 / Kalman 2D 常速）。
- 拒单留痕：候选 26 项拒 6（Manhattan/Chebyshev 距离度量与既有度量族同义、EwmaCalc 与滑动均值族重叠、AxisSs2StopSeq/AxisBacklashDirBias 与 R44 存量近邻、FailsafeGate 收敛并入 EStopDualChannel），拒单率 23%，未达 R228 枯竭阈值（2:1）。
- 合规：零代码行复制；闭源源（LGF/ModPID/PLCopen/LBP）只借分类组织与参数域，实现 100% clean-room；详见 `RAW_NOTES_R56.md`。
""" )

# ---------------- 5. 战报 ----------------
report = """# R56 战报（2026-11-20 23:15 → 2026-11-21 00:30）

## 一、看板
| 指标 | 数值 |
|---|---|
| 总库 | **{total} / 10,000（{pct}%）** —— **首次突破 1,000 件** |
| 今日（11-20） | 152 → **172 / 200** |
| 距 500 计划 | 超额 **+517** |
| SFT 语料 | **{sft} 条**（新增 20 + 返修重注入 5） |
| 子库分布 | Base {b} / MathData {m} / Algo {a} / Device {d} / Motion {mo} / Process {pr} |

## 二、四批完成情况（20/20）
| 批 | 组件 | 结果 |
|---|---|---|
| B1 | HermiteInterp / QuatSlerp / RoundSigFigs / RtdLinearization / EStopDualChannel | 5/5 |
| B2 | Kalman2DSmoother / SignalSeqGuard / TwoDofPid / AxisAccelFeedforward / HydraulicAccumPreChg | 5/5 |
| B3 | VacIonizerBalance / FanVfdBypassSwap / AxisCantileverComp / HotRunnerZoneBalance / SlurrySieveClogWatch | 5/5 |
| B4 | LossInWeightFeeder / UvDoseCtrl / UltrasonicWeldCtrl / AxisProbeMeasCycle / AirShowerInterlockSeq | 5/5 |

- 机检增量 **25/25 PASS**（20 新 + 5 返修，`audit_r56`/`closeout_r56`），fail=0；未做全库扫描（当日首轮已扫）。
- 5 件返修 v1.0.1 闭环：BacdHvacPoll（死分支删除，`_nCurRetry` 经核已在位）/ FopdtStepIdent（带符号斜率）/ CoinCellAssembler（删死变量）/ StringElImageMap（复位补 4 清 + 批号重同步）/ PackMlUnitMode（枚举校验 + 段号回正）。

## 三、预算执行
| 项 | 上限 | 实际 | 判定 |
|---|---|---|---|
| 墙钟 | 50′ | 约 **75′** | **超顶 25′，按预算令本轮作废计分**（产出照实入库） |
| 子代理 | 3 | 2（总监 1 + PLC 1，收口主控直跑 R335） | 达标 |
| WebSearch | 3 | 0（零检索轮） | 达标 |
| 文档 | 增量 | 全追加式（README/CHANGELOG/VERSION×6/MATRIX/EVOLOG/双账本） | 达标 |

> 超时归因：① 编码单调用背 25 件（20 新 + 5 返修）26′；② 收口脚本首次落地时字典键拼写错误致一次重跑（+6′）；③ 收口脚本 ROADMAP 勾选用子串匹配误勾 8 条后续任务行，回滚与修脚本 +8′。已立 R247/R249 处置。

## 四、选题与合规
- 拒单 6 项（26 候选），拒单率 23%，未达 R228 枯竭阈值。
- 零检索：全部复用 R39~R55 既有 RAW_NOTES 与矩阵源行，闭源源只借分类/参数域/组织方式，零代码行复制。
- 撞名三查 20/20 零命中（registry + ROADMAP 本体行 + 文件树）；新发现「ROADMAP 引用行误判撞名」问题 → R246。

## 五、专家进化
- PLC 编程专家 +5 条（**R240~R244**）：声明区完整性 F 检项、死分支识别、带符号几何量、复位清单化、占位词扫查。
- 产品总监 +5 条（**R245~R249**）：T0=0 配额令、撞名三查区分本体/引用行、勾选锚定正则 + 数量断言、返修语料重注入、25 件超载裁决。
- 累计新增 10 条，游标 **R250**；FB-50 后第 5 轮，未触发固化。

## 六、风险与下轮
- **P0**：R56 二十件五抽语义终审（Kv2D 协方差近似、TwoDofPid 抗饱和、LossInWeightFeeder 补料相优先）；R247 勾选正则落进 closeout 模板。
- **P0**：编译验证债连挂 **51 轮**，须有人值守轮接真编译（R230）。
- **P1**：返修件 ≥4 时新件下调 16（R249）；声明区完整性 F 检项并入 compile_gate_v1。
- **P2**：常态 16~20 件 → 约 1,033~1,037。

*R56 ｜ 道莅工控代码库产品总监 + PLC 编程专家双签 ｜ 2026-11-21 00:30*
""".format(total=total, pct=round(total/100.0, 2), sft=sft,
           b=counts["DL_Base"], m=counts["DL_MathData"], a=counts["DL_Algo"],
           d=counts["DL_Device"], mo=counts["DL_Motion"], pr=counts["DL_Process"])
io.open(os.path.join(STAGE, "BATTLE_REPORT_R56.md"), "w", encoding="utf-8", newline="").write(report)

feishu = """**道莅代码库 · R56 战报（2026-11-20 23:15 → 11-21 00:30）**

**看板**：总库 **{total} / 10,000（{pct}%）—— 首次突破 1,000 件** ｜ 今日 172/200 ｜ 500 计划超额 +517 ｜ SFT 语料 **{sft} 条**

**四批完成**：B1 5/5（插值·四元数·RTD·有效数字·双通道急停）｜ B2 5/5（Kalman2D·时序守卫·2-DOF PID·加速度前馈·蓄能器预充）｜ B3 5/5（离子平衡·风机旁通·悬臂补偿·热流道·浆料筛堵）｜ B4 5/5（失重给料·UV 剂量·超声焊·探针测量·风淋联锁）

**质量**：机检 25/25 PASS（20 新 + 5 返修）｜5 件 v1.0.1 返修闭环（含 R55 编译阻断项 BacdHvacPoll）｜零检索轮，拒单 6/26（23%）

**源覆盖**：t2-1-lgf-math 3 / t2-1-lgf-converter 2 / t2-5-modpid 1 / t1-6-plcopen 3 / t2-2-lbp 9 / roadmap-r56 2；T0 八组维持 8/8 ✔

**专家进化**：PLC +5（R240~R244）｜总监 +5（R245~R249）｜游标 R250

**风险一句话**：墙钟 75′ 超 50′ 硬顶 25′（编码 25 件超载 + 收口脚本两次返工），按预算令本轮作废计分；编译验证债连挂 51 轮待有人值守轮接真编译。
""".format(total=total, pct=round(total/100.0, 2), sft=sft)
io.open(os.path.join(STAGE, "Feishu_R56.md"), "w", encoding="utf-8", newline="").write(feishu)
print("docs ok: total=%d sft=%d battle+feishu written" % (total, sft))
