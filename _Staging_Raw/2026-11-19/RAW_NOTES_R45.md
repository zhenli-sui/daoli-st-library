# RAW_NOTES_R45（第 45 轮 · 2026-11-19）

> 本轮 **零检索（WebSearch 0/3）**，无新增外部源抓取。交付 = **2 件 P0 返修（PATCH，先做）+ 20 件新件（4 批 × 5）**。
> 落盘规则：新件 v1.0.0；返修件 v1.0.0 → v1.0.1（**引脚契约零变更**）；行尾 CRLF；UTF-8 无 BOM。

## 1 源使用台账（20 件新件）

| 序号 | 组件 | 分类 | 来源标签 | 源类型 | 许可证 / 合规口径 | 提取点（仅行为定义 / 分类事实 / 参数域） |
|---|---|---|---|---|---|---|
| 1 | FB_DL_Vote2oo3 | DL_Base | 道莅自研 clean-room | 自研（零外部抓取） | 无外部源 | 2oo3 表决结构惯例、降级 1oo2 处置语义 |
| 2 | FB_DL_EdgeOrderCheck | DL_Base | 道莅自研 clean-room | 自研 | 无外部源 | 现场 A→B 时序联锁惯例、间隔确认窗 |
| 3 | FB_DL_AlarmFloodLimiter | DL_Base | 道莅自研 clean-room | 自研 | ISA-18.2 公开标准语义（只借分类） | 报警泛滥抑制窗、安全关键报警恒放行 |
| 4 | FC_DL_CubicBezierEval | DL_MathData | 道莅自研 clean-room（t2-1-lgf 数学子族） | 自研 | 公开数学定义（Bernstein / De Casteljau） | 三次贝塞尔求值与一阶导数定义式 |
| 5 | FB_DL_KalmanFilter1D | DL_Algo | 道莅自研 clean-room | 自研 | 公开算法式（标量卡尔曼） | 预测-校正递推、增益分母防零 |
| 6 | FB_DL_TensionObserver | DL_Algo | 道莅自研 clean-room | 自研 | 公开力学式（静态平衡） | 卷绕张力静态平衡观测、方向滞环 |
| 7 | FB_DL_StictionCompensator | DL_Algo | 道莅自研 clean-room | 自研 | 公开参数域（dither） | 黏滞死区补偿与脉动相位惯例 |
| 8 | FB_DL_LoopPerfIndex | DL_Algo | 道莅自研 clean-room | 自研 | 公开控制指标定义（IAE/ISE/超调） | 回路性能指标定义式与自动/手动分域 |
| 9 | FB_DL_ThermalRampPredict | DL_Algo | 道莅自研 clean-room | 自研 | 公开一阶热模型 | 一阶惯性升温预测、无趋势哨兵 |
| 10 | FB_DL_AxisDualFeedbackGuard | DL_Motion | 道莅自研 clean-room | 自研 | 无外部源 | 双反馈交叉校核、极性判别先于幅值分级 |
| 11 | FB_DL_AxisSs1StopSeq | DL_Motion | 道莅自研 clean-room | 自研 | IEC 60204-1 公开停止类别语义（只借语义） | SS1 停止时序（减速→零速→STO 请求） |
| 12 | FB_DL_AxisTeachOffset | DL_Motion | 道莅自研 clean-room | 自研 | 无外部源 | 示教点 + 配方偏移的候选位先判后写 |
| 13 | FB_DL_AxisInertiaIdent | DL_Motion | 道莅自研 clean-room | 自研 | 公开算法式（最小二乘闭式解） | 惯量辨识闭式解、病态保持上次结果 |
| 14 | FB_DL_AxisRotaryShortPath | DL_Motion | 道莅自研 clean-room | 自研 | 公开算法（角度归约 / 最短路径） | 旋转轴最短路径与圈号守卫 |
| 15 | FB_DL_SafetyRelayFeedback | DL_Device | 道莅自研 clean-room | 自研 | ISA-18.2 / NE107 公开分类（只借分类） | 双通道反馈一致性、同步窗四结局归因 |
| 16 | FB_DL_ContactorWeldDetect | DL_Device | 道莅自研 clean-room | 自研 | 无外部源 | 设备级熔焊 / 不吸合检测粒度 |
| 17 | FB_DL_FlowSwitchResponseCheck | DL_Device | 道莅自研 clean-room | 自研 | 无外部源 | 命令-监视-判定三段式响应时间校核 |
| 18 | FB_DL_SlurryMixingSeq | DL_Process | 道莅自研 clean-room | 自研 | 无外部源 | 锂电前段浆料制备四相（加料-分散-脱泡-出料） |
| 19 | FB_DL_FrameSealDispenseSeq | DL_Process | 道莅自研 clean-room | 自研 | 无外部源 | 光伏装框打胶轨迹分段与断胶急停 |
| 20 | FB_DL_BoilerBlowdownSeq | DL_Process | 道莅自研 clean-room | 自研 | 无外部源 | 锅炉排污周期-时长-低水位中止语义 |

**零 T0 件**：本轮 20 件中 `iec-std-wrapper` 来源标签件 = 0，故「IEC 61131-3 标准语义的道莅防御性实现」短语仅作常设口径保留未使用；`FC_DL_CubicBezierEval` 属 **t2-1-lgf 数学子族**，按派单 §4.1 第 2 式书写。

## 2 码位分配台账（20 件）

| 段 | 子带 | 本件占用（故障级 / 信息级） | 分段理由（R192） |
|---|---|---|---|
| 0001 Base/MathData | 03xx / 04xx | 03EA~03ED / 04AD~04B0 | 源码实扫该槽为空，续接同子带已用最大值，未回填碎片孔洞 |
| 0002 Algo | 03xx / 04xx | 03AF~03B3 / 04B2~04B6 | 同上；连续 5 件按批内序号顺排 |
| 0003 Device | **新开 07xx** / 04xx | 0701~0703 / 0480~0482 | 03xx 段仅余 03C5~03C9 碎片，按实战规则 13「禁回填碎片孔洞」另起 07xx 子带；避开 0590~0599 |
| 0004 Motion | 03xx / 04xx | 03B4~03B8 / 04B4~04B8 | 源码实扫该槽为空，续接同子带已用最大值 |
| 0005 Process | 03xx / 04xx | 03A6~03A8 / 04CE~04D0 | 同上；与既有 039F/03A2 相邻不重叠 |

> 每件头注释均写明上述理由之一（R192 要求）；**加码反证句（R90）**：三件 Device 新件与三件 Process 新件的「现有输出组合不可观测」反证已逐件写入码表段。

## 3 P0 返修记录（2 件，PATCH，引脚契约零变更）

| 件 | 版本 | 缺陷定性 | 改动点（内部判据 / 注释） | 引脚影响 |
|---|---|---|---|---|
| FB_DL_CalenderRollPress | 1.0.0 → **1.0.1** | R281：双侧同步判据缺相位因子，`eIdle` 上电即报 039F、`eRelease` 每次收尾误锁、`eDone` 永不可达 | ① VAR 增 `_bSyncWin`；② 段 0 新增相位窗赋值（`bStart AND (eGapSet ∨ eBarPress ∨ eRun)`）；③ 段 3 同步判据加窗；④ 段 4 解除式**保持四因子**并写「终审两式 1」自证与「不加 NOT _bSyncWin」反证；⑤ 头注释边界③改写、接口段补 `tonRun` 复用 `tGapTmo` 说明；⑥ 组态闸补 5 个组态实数的 NaN 自反判（原 NaN 使闸静默失效）；⑦ 5 处故障分支补 `bError := TRUE`（R45 配对）；⑧ 修订历史 +1 行 | **零变更**（无引脚增删改） |
| FB_DL_IvCurveScan | 1.0.0 → **1.0.1** | R283：复位沿作用域越界（非故障相也清窗内极值与采样计数，与 `tonScan` 不重装矛盾）＋ `eDone` 相 FF 输出恒 0 | ① 段 2 复位按相分域：仅 `eFault` 相净重装四量并回 `eIdle`；② 新增 `_fFfPu` 并上移段 0 单次求解；③ 段 3 判据改读 `_fFfPu`，删除同一 FC 同参**双调用**；④ `eEval` 只读当拍量，改双出口（`_bFault → eFault` / 否则 `eDone`）；⑤ 段 6 `fFfPu := _fFfPu`，故障相仍强制 0（不输出哨兵）；⑥ 去掉 `>= 0.0` 前置闸避免 `eEval` 无迁出（哨兵 −1.0 归入 `eEfLow` 安全侧）；⑦ 组态闸补 `fFfMinPu`/`fVmaxV` 的 NaN 自反判；⑧ 边界新增⑦⑧、修订历史 +1 行 | **零变更** |

**返修验收向量落点**（终审必推，已逐条对码）

- CRP：V1 `eIdle`+偏差 0.5mm → 无 039F（`_bSyncWin` 假）；V2 `eGapSet`+偏差超限 → 039F/`eGapSync`/`bError`；V3 `eRelease`+`tonRun.Q` → 无 039F、`eDone`+04C7 单拍；V4 V2 后复位 → `bError=FALSE`、`eState=eIdle`、**次拍不复锁**。
- IVS：V1 `eScan` 中复位 → 相位仍 `eScan`、`nSampleCount` 不回退、`tonScan` 不重装、无新码；V2 非有限锁存后复位 → `eIdle`、四量清零、`bError=FALSE`；V3 `eDone` → `fFfPu` = 有效值（≠0）、`bCycleDone`、04CA 单拍；V4 `eFault` 中复位 → 解除可达（`tonScan.IN` 恒假 → `Q` 恒假）。

## 4 机检记账表（`件名 | PASS/FAIL | 失败项号`，22 件全量复跑）

| # | 件名 | 结果 | 失败项号 |
|---|---|---|---|
| 1 | FB_DL_Vote2oo3 | PASS | — |
| 2 | FB_DL_EdgeOrderCheck | PASS | — |
| 3 | FB_DL_AlarmFloodLimiter | PASS | — |
| 4 | FC_DL_CubicBezierEval | PASS | — |
| 5 | FB_DL_KalmanFilter1D | PASS | — |
| 6 | FB_DL_TensionObserver | PASS | — |
| 7 | FB_DL_StictionCompensator | PASS | — |
| 8 | FB_DL_LoopPerfIndex | PASS | — |
| 9 | FB_DL_ThermalRampPredict | PASS | — |
| 10 | FB_DL_AxisDualFeedbackGuard | PASS | — |
| 11 | FB_DL_AxisSs1StopSeq | PASS | — |
| 12 | FB_DL_AxisTeachOffset | PASS | — |
| 13 | FB_DL_AxisInertiaIdent | PASS | — |
| 14 | FB_DL_AxisRotaryShortPath | PASS | — |
| 15 | FB_DL_SafetyRelayFeedback | PASS | — |
| 16 | FB_DL_ContactorWeldDetect | PASS | — |
| 17 | FB_DL_FlowSwitchResponseCheck | PASS | — |
| 18 | FB_DL_SlurryMixingSeq | PASS | — |
| 19 | FB_DL_FrameSealDispenseSeq | PASS | — |
| 20 | FB_DL_BoilerBlowdownSeq | PASS | — |
| 21 | FB_DL_CalenderRollPress（v1.0.1 返修） | PASS | — |
| 22 | FB_DL_IvCurveScan（v1.0.1 返修） | PASS | — |

> 机检脚本：`_Staging_Raw\2026-11-19\selfcheck_r45.py`（7 红线 + 枚举 ⊆ CASE 标签 + CRLF/BOM + 禁用词 + R45 配对 + 实例调用点须在 CASE 之前 + NaN 自反豁免）。**TOTAL 22 files, FAIL 0**。

## 5 本轮自纠留痕（如实记账，不静默清账）

1. `FB_DL_KalmanFilter1D` 首写含占位符 → 立即整件覆写，并删去不可达 `ELSIF` 分支。
2. `FB_DL_EdgeOrderCheck` 漏声明 `_nReverseCount` → 补声明，改为内部锁存唯一写入点。
3. `FB_DL_AlarmFloodLimiter` 出口 `bPassThrough` 同拍双重赋值 → 合并单点 IF/ELSIF/ELSE。
4. `FB_DL_LoopPerfIndex` 内核调用 OUT 实参留空 → 补声明 `_bConvErr`/`_bConvValid`。
5. `FB_DL_ThermalRampPredict` 隐式转换写反（`LREAL_TO_REAL`）→ 改 `REAL_TO_LREAL`。
6. `FB_DL_AxisDualFeedbackGuard` / `FB_DL_AxisSs1StopSeq` 相内自赋值驻留 → 改显式双出口。
7. `FB_DL_AxisRotaryShortPath` 解除式单因子恒假（R152 反例）→ 拆双分支（`_bSolved` ∨ 目标角本身在软限内）。
8. `FB_DL_SafetyRelayFeedback` eSyncWait 出口 2 判据错位（恒非恒假）→ 改 `(NOT bCmd) AND (NOT _bDiff)`。
9. `FB_DL_BoilerBlowdownSeq` 在 CASE 内调用 `tonInterval`（R228A 违规）→ 删除调用，改注释说明自复位节拍。
10. 本轮 PATCH：`CalenderRollPress` 头注释原含物理地址写法（`%I %Q`）→ 改为「无直接物理地址访问」；5 处故障分支补 `bError := TRUE` 以满足 R45 配对机检。
11. 本轮 PATCH：`IvCurveScan` `eEval` 原 `>= 0.0` 前置闸会造成「分母非法且无故障」时**相位无迁出**（R228B 同类）→ 去掉前置闸，哨兵归入 `eEfLow` 安全侧双出口。

## 6 合规声明

- **零代码行复制**：全部 22 件实现、状态机、码位、引脚命名 100% 本库自有；外部仅提供「行为定义 / 分类事实 / 参数域」。
- **GPL/AGPL**：本轮未触及。
- **闭源源**（西门子 LGF / 罗克韦尔 AOI）：本轮零引用。
- **安全件声明**：`FB_DL_AxisSs1StopSeq`、`FB_DL_SafetyRelayFeedback` 头注释均含「**不实现任何安全认证功能**」；安全回路输出侧双保险仍需在 `PRG_IoMapping` 层落硬件切断。

## 7 未完成项 / 遗留债（如实留痕）

- **编译验证债**：连续 42 轮未开闸（三平台实编译），机检仅覆盖静态红线，语义正确性仍依赖终审两式推演。
- **索引登记**：本轮 22 件尚未写入 `INDEX_REGISTRY.json`（待 R45 收口脚本统一登记）。
- **`CalenderRollPress` 遗留**：`tonRun` 复用 `tGapTmo` 属引脚预算取舍，已在头注释声明为「非缺陷」；若现场需独立抬辊超时，须以 MINOR 版本增设 `tReleaseTmo` 引脚。
- **`IvCurveScan` 遗留**：`E_DL_IvsCause` 未新增「分母不可计算」独立成员（为守「引脚契约零变更」），该情形归因 `eEfLow`，头注释与段 3 注释已写明安全侧理由；若终审要求归因分离，须以 MINOR 版本扩展枚举。
