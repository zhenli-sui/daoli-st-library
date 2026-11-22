# ROUND_PLAN_R71 —— 第 R71 轮构建计划（阶段一盘点 + 阶段二锁定目标）

> 轮次：R71 ｜ 日期：2026-11-22 ｜ 轮型：零检索轮（WebSearch 0/3，取材全部来自既有 MATRIX 台账与内部族深化）
> 配额：**新件 8 件**（P0 点修 1 占额 + 新件 7），按 R371（R70 超 50 分钟硬顶 → 配额 13→8）执行，**严禁超编、宁少勿滥**。
> 本轮只做规划，不写任何 `.st` 代码；不修改 `.st` / `INDEX_REGISTRY.json` / JSONL / README / CHANGELOG / VERSION / ROADMAP / MATRIX。

---

## §1 盘点（数据源：`INDEX_REGISTRY.json` v2.62.0 实测提取，非记忆）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总库规模 | **1,199 / 10,000**（11.99%） | registry `total_components` 实测，counts：MathData 286 / Process 285 / Device 218 / Base 151 / Algo 135 / Motion 124 |
| 今日产出 | **64 / 200**（32%） | R70 收口后当日累计，本轮 +8 预计 72/200 |
| 500 冲刺里程碑 | **已超额**（1,199 ≫ 500，达成率 239.8%） | 500 计划早已超额完成，现处于万级冲刺 Phase 2；本轮后预计跨过 **1,200**（1,199+8=1,207，余 7 件缓冲） |
| JSONL 语料 | 1,231 条 | 本轮 8 件收口后 +8，不注水 |
| 源矩阵覆盖率 | 可判定组 27：**✔ 收口 9（33%）、◐ 深化 7、☐ 待挖 11** | R60 口径「☐ 组维持 11」、R68 确认「收口率仍 9/27 = 33%」；T0 八组 8/8 ✔ 余量 0（R278 维护模式，本轮 T0 = 1 族内补口，属允许区间 0~1） |
| ROADMAP 待办 | **55 条**（grep 实测 `^- \[ \]` = 55） | > 30 条阈值 → **本轮不补写 ROADMAP**（纪律：只在 <30 条时补写；本句仅记于本计划，不写入 ROADMAP） |
| 编译验证债 | 连欠 ≥5 轮（R195 硬闸挂账） | 本轮新件不含编解码/数学/转换类**高复杂度**件（FC_DL_TriangleSolveSSS / FC_DL_DurationFormat 均为 C1~C2 薄件，不触 R195 闸） |
| R70 挂账承接 | `FB_DL_ScaleRangeWatch` 量程零域复核（P0） | 本轮序号 1 点修，占 1 个配额 |

---

## §2 目标表（8 件，批次 1 = 序号 1~4，批次 2 = 序号 5~8）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_ScaleRangeWatch`（v1.0.0 → v1.0.1 点修） | DL_MathData | FB_DL_ | 量程零域复核：组态闸零量程路径对账 + 头注释披露级点修 | r70-plan（挂账承接） | 1（点修） | 1 |
| 2 | `FC_DL_AirSpecificVolume` | DL_MathData | FC_DL_ | 湿空气比容计算（m³/kg 干空气），焓湿图全参族补件 | t1-2-oscat-building | 2 | 1 |
| 3 | `FB_DL_AxisEncBatteryWatch` | DL_Device | FB_DL_ | 绝对值编码器备用电池欠压监视与预警（防断电丢参考点） | t2-6-rockwell-aoi（t2-8-ne107 次源） | 2 | 1 |
| 4 | `FC_DL_DurationFormat` | DL_Base | FC_DL_ | TIME 时长分解为 天/时/分/秒 四分量（HMI 显示用纯函数） | iec-std-wrapper（T0-2 族内补口，T0=1） | 2 | 1 |
| 5 | `FB_DL_FlyingShearSync` | DL_Motion | FB_DL_ | 飞剪同步控制器：产品测长 → 加速进入 → 线速同步跟踪 → 剪切触发 → 减速退出 | t1-6-plcopen | 3（本轮唯一 ≥250 行件） | 2 |
| 6 | `FB_DL_LaneDivertCtrl` | DL_Process | FB_DL_ | 输送线道岔分流控制器：到件 → 岔口动作 → 尾件确认 → 恢复直行 | s9-conv（t2-7-packml 次源） | 2 | 2 |
| 7 | `FC_DL_TriangleSolveSSS` | DL_MathData | FC_DL_ | SSS 三边解三角形（余弦定理三角度），机构几何/三点定位纯函数 | t2-1-lgf-math（三角方向待挖首件） | 2 | 2 |
| 8 | `FB_DL_PumpPrimingWatch` | DL_Device | FB_DL_ | 离心泵灌泵期监视：充水确认窗 + 起立判据 + 干转前预警 | t2-2-lbp（self 判据） | 2 | 2 |

**分类分布**：MathData 2（含点修）/ Device 2 / Process 1 / Base 1 / Motion 1 / Algo 0 —— 覆盖 5 个子库，MathData/Device/Process 为主（5/7），Base/Motion 补口；Algo 为 R60 拒单重灾族，本轮继续避让（R267）。复杂度 7×C2 + 1×C3，无高复杂度转换/编解码件（R195 闸合规）。

### §2.2 撞名三查记录（对 `INDEX_REGISTRY.json` v2.62.0 实时精确匹配 + 词根邻件扫描，R327 口径）

判重方法：python 提取 registry 全部 1,199 个 `name` 落临时名单 → 候选名做大小写不敏感**精确匹配** → 再按词根做同义邻件扫描。以下 **9 条候选被拒**：

| # | 被拒候选 | 拒绝理由 |
|---|---|---|
| 1 | `FC_DL_StringEditDistance`（Data Handling 字符串编辑距离方向） | **精确同名已注册**（R65 立项落地，registry 在册），重复提案 |
| 2 | `FB_DL_EStopDualChannel`（急停双通道监视候选） | **精确同名已注册**，急停安全域已收口 |
| 3 | `FB_DL_MotorPhaseImbalance`（电机三相不平衡候选） | 同义邻件三家在册：`FB_DL_PhaseNeutralImbalance` / `FB_DL_PhaseLossGuard` / `FB_DL_VfdOutputImbalance`，判据面已被覆盖 |
| 4 | `FB_DL_SafetyMuteSeq`（光幕消隐时序候选） | 同义邻件 `FB_DL_SafetyMuteZone` 在册，静默/消隐域已有属主 |
| 5 | `FB_DL_HeaterBreakDiag`（加热管断丝候选） | 近邻 `FB_DL_HeaterBreakDetect` 在册，同名根同语义，属重复立项 |
| 6 | `FB_DL_TurntableSeq`（转台顺控候选） | 同义邻件 `FB_DL_RotaryIndexTable` / `FB_DL_RotaryIndexModulo` 在册（R10/R29 分度族），语义重叠 |
| 7 | `FC_DL_TriangleSolve`（无后缀泛名） | 与 `FB_DL_TriangleGenerator`（R39 信号发生器）共享「Triangle」词根，同根异义高风险命名 → **改名收窄为 `FC_DL_TriangleSolveSSS`** 并在头注释写命名说明（R28-4 三处记账：头注释命名说明 + 本计划 §2.2 + 战报撞名段） |
| 8 | `FB_DL_RolloverCounterInt` / `FB_DL_BidirectionalCounterInt`（T0-3 计数器 INT 变体候选） | 位宽/类型姊妹件，**凑数变体**，按 R62 口径拒（拆件即凑数） |
| 9 | `FC_DL_AirDensityAlt`（空气密度 LREAL 姊妹件候选） | `FC_DL_AirDensity` 在册且同为 LREAL 主线，同算法变体属凑数 |

正选 8 件均通过精确匹配（零同名命中）+ 同义邻件逐件核对（分工边界见 §3 各件「分工声明」行）。

---

## §3 每件功能规格 + 边界安全条件（供编码专家直接照做）

### 序号 1｜`FB_DL_ScaleRangeWatch` v1.0.1（点修，不新增引脚契约）

- **缺陷假设 H1（文档-源码口径漂移）**：R70 战报挂账称「组态闸仅判 `rawMax-rawMin`」，但 v1.0.0 源码为**增益/偏置形态**（`fGain`/`fOffset`），无 rawMax/rawMin 引脚、无除法面（头注释已声明）。按 R58「源码唯一事实源」先对账：挂账描述与实现不符，点修第一步是**以源码实测为准的复核记录**。
- **缺陷假设 H2（零量程路径推演）**：`fHighLim == fLowLim` 时段 4 组态闸 `fHighLim <= fLowLim` 判真 → 段 6 首次成因锁存 16#0002_0121 → 段 7 `_bRun = FALSE` → **段 8 换算段结构性不可达**，无除零/NaN 泄漏面；且 `fHyst >= (fHighLim - fLowLim)`（差为 0）对任意合法 `fHyst ≥ 0` 恒真，**双闸冗余覆盖**零量程。极端幅值（±1E30）下带宽差 ≤2E30 < LREAL 域，无溢出面。
- **缺陷假设 H3（残余风险点）**：① 复位解除当拍：段 3 先清锁存、段 6 同拍重判组态，组态仍非法则同拍重锁存 —— 属 R189 口径一致行为，非缺陷，**在头注释披露即可**；② 非有限换算分支（段 8 就地锁存 0121）与段 4 逐拍重算的 `_bCfgBad` 不含「增益×原始值溢出」项 —— 归因为组态域外合理，声明即可。
- **修法判据**：若复核确认零域已全覆盖（预期结论）→ v1.0.1 为**披露级点修**：头注释补「量程零域拦截路径」两道判据披露 + 复位当拍重锁存语义声明 + 修订记录登记；**不改行为、不动码位、不动引脚**。若实推演构造出可进入换算段的零域反例向量（预期为空）→ 段 7 运行许可并联「带宽 > 0」结构早退，码沿用 16#0002_0121，并跑「锁存首拍 + 解除当拍」两条向量复验后升 v1.0.1。
- **边界安全条件**：终审两式自查——锁存解除式（bReset 上升沿，段 3）可达性复验；整数/浮点进位点：`fHyst >= 带宽` 在「带宽恰为 0」与「fHyst 恰等于带宽」两点各推一条向量。

### 序号 2｜`FC_DL_AirSpecificVolume`（DL_MathData，纯函数）

- **输入输出语义**：输入 fTempC [℃]、fRelHum [%]、fPressPa [Pa]；输出 fSpecVol [m³/kg 干空气]（湿空气比容）+ bValid [标志] + nInfoCode（信息级）。公式链取公开湿空气学（理想气体分压 + Magnus-Tetens 饱和分压，常数属主 `FC_DL_VaporPressureSat` 复用调用不复制）。
- **分工声明**：`FC_DL_AirDensity` 输出湿空气密度（kg/m³ 湿空气）、`FC_DL_HumidityRatioCalc` 输出含湿量 —— 本件输出**每 kg 干空气的容积**，三者互引边界。
- **判据链**：域闸（fTempC ∈ [−20, 80]℃ 承诺段、fPressPa ≥ 10 kPa、fRelHum ∈ [0, 100] 钳位照算）→ 饱和水汽压 → 比容式分母 `p − φ·p_sat·(1−Ra/Rv)` 有效性闸（**分母 ≤ 0 即过饱和/低压非法**，早退出信息码、输出 0.0）→ 结果非有限闸 → 钳位下界。
- **边界安全条件**：**除零面在分母**（φ=100% 且 p_sat 接近总压的高湿低压组合），必须先判后除；NaN/Inf 用 `x<>x` + `(x−x)<>0` 精确判据（R79）；禁 `=` 判等浮点（红线 5）。

### 序号 3｜`FB_DL_AxisEncBatteryWatch`（DL_Device）

- **输入输出语义**：输入 fBattV [V]（引脚注入，绝对值编码器电池电压）、tConfirm [ms]（欠压确认延时）、fWarnV/fFaultV [V]（预警/故障阈值，默认域注释标注）、bEn/bReset；输出 bWarn / bFault / bReplaceSoon（估算剩余判据链）+ bError + nErrCode + NE107 健康枚举出口（次源语义）。
- **状态机/判据链**：单相监视（无 CASE 状态机，同 ScaleRangeWatch 口径）：电压非有限闸 → 幅值域闸（0~5 V 编码器电池典型域，越域信息级）→ 双阈值迟滞判定（warn/fault 两线各带回差，防止临界抖振）→ TON 连续确认 → 预警锁存 + 健康出口（fault → eMaintenanceReq，warn → eOutOfSpec）。
- **边界安全条件**：非有限电压（断线/ADC 故障）→ **直接置 bFault 并锁存**（电池状态不明比欠压更危险，安全侧收紧）；失能不清锁存（R303 口径，bReset 上升沿唯一解除）；TON 无条件周期调用；阈值倒置（fWarnV ≤ fFaultV）→ 组态锁存码。
- **分工声明**：`FB_DL_BrakeWearAccum`（磨损累计）、`FB_DL_SpindleWarmupSeq` 等运动健康件互不相干；本件只做编码器电池，不消费轴状态（R31 家族高危区纪律）。

### 序号 4｜`FC_DL_DurationFormat`（DL_Base，纯函数，T0-2 族内补口）

- **输入输出语义**：输入 tDur [TIME]；输出 uDays/uHours/uMins/uSecs [UDINT] 四分量（HMI 显示分解）+ bValid + bTruncated（TIME 容器上界截断标志）。
- **判据链**：一次换算到 UDINT 秒（先判 TIME 容器上界防溢出）→ 整除分解 d/h/m/s（**除法除子全为常量 86400/3600/60，无变量除零面**）→ 余数级联 → 分量出口。
- **边界安全条件**：负 TIME 不可表示（TIME 无符号语义），输入域闸声明；uDays 上界声明（TIME 容器毫秒上限 ÷ 86400）；**与既有 `TimeToDintMs` / `TimeToLrealSec` 分工**：那些是单一数值换算，本件是日历分量分解（多出口语义，非变体）——头注释写明。
- **R195 核对**：C2 薄件、无平台内建链依赖（纯算术），不触编译闸。

### 序号 5｜`FB_DL_FlyingShearSync`（DL_Motion，C3，本轮唯一 ≥250 行件）

- **输入输出语义**：输入 fProductVel [mm/s]（产品线速，引脚注入）、fShearLen [mm]（切长）、fSyncWinLen [mm]（同步窗长）、fAccel/fDecel [mm/s²]、fSyncTol [mm/s]（速度匹配容差）、bCutReq [标志]（切剪请求）、bEn/bReset；输出 fKnifeVelCmd [mm/s]（刀轴速度指令）、bCutTrig [标志]（单拍剪切脉冲）、eState [E_DL_ 枚举] + bError + nErrCode。
- **状态机要点**（ENUM + CASE + ELSE 兜底）：`eIdle → eAccel（斜坡加速至线速匹配）→ eSyncTrack（速度同步 + 位置窗跟踪）→ eCutFire（bCutTrig 单拍脉冲，R24 口径）→ eDecel（斜坡退窗）→ eIdle`；超时监控（进入/退出各相带 TON，段内断输入，R40 口径）；切剪请求在 eSyncTrack 才受理，其余相拒收并计数（信息级）。
- **边界安全条件**：fProductVel 非有限/负值 → 拒绝并保持 eIdle（不发指令）；切长 < 同步窗长 → 组态锁存码；同步窗未到而刀轴仍在窗内（状态残留）→ 迁相前强制 eDecel 清窗（**同拍竞态闸**：bCutReq 与 eState 判定同拍完成，禁跨拍双判）；失能 → 速度指令斜坡归零 + 状态回 eIdle + 剪切输出清零（停机相输出清零，R57 家族规则）；斜坡积分用上一拍锁存副本（R38 口径）。
- **分工声明**：`FB_DL_LabelApplySync`（贴标同步）、`FB_DL_RotaryIndexModulo`（分度回转）为同族邻件 —— 飞剪的「加速-同步-剪切-退出」四段与「切长积分触发」为独立语义，头注释互引分工。
- **来源边界**：PLCopen 应用语义（飞剪/飞锯属 MC 同步应用公开分类），只借「同步窗 + 速度匹配」组织方式；同步区插补数学 100% clean-room，不自造轴状态枚举（R31），轴状态归运动层。

### 序号 6｜`FB_DL_LaneDivertCtrl`（DL_Process）

- **输入输出语义**：输入 bPartArrive [标志]（到件传感）、bLaneFree [标志]（分流道空闲，上位注入）、bActDone/bActHome [标志]（岔口动作器到位/回位反馈）、tActTimeout [ms]、bEn/bReset；输出 bDivertCmd [标志]（岔口动作命令）、bRelease [标志]（放行）、uDivertCount/uRejectCount [UDINT] + eState + bError + nErrCode。
- **状态机要点**：`eIdle →（到件 ∧ 道岔回位）eActuate →（bActDone）ePassing →（尾件越过 = 到件信号下降沿，R_TRIG 无条件刷新）eRestore →（bActHome）eIdle`；ELSE 兜底 eFault 并锁存。
- **边界安全条件**：到件时岔口未回位 → **拒放 + 拒收计数**（不排队，防积压误分）；动作反馈超时 → 故障锁存 + 放行撤销（放行必须能在 uErrCode 找到对应码，R45 口径）；失能/故障相 → bDivertCmd/bRelease 全清零（停机相输出清零）；R_TRIG/TON 段 9 无条件刷新；连续来件最小间隔由到件信号本身承载，本件不造额外节拍参数（无魔法数）。
- **分工声明**：`FB_DL_PalletZoneMerge`（合流）、`FB_DL_ConveyorJamDetect`（堵塞诊断）——本件只管「分流道岔命令-反馈-确认」三段，不做合流汇入与堵塞判级，头注释互引。

### 序号 7｜`FC_DL_TriangleSolveSSS`（DL_MathData，纯函数）

- **输入输出语义**：输入 fA/fB/fC [mm]（三边长，对边对应角 A/B/C）；输出 fAngA/fAngB/fAngC [rad] + bValid + nInfoCode（信息级）。余弦定理三式公开数学，clean-room。
- **判据链**：三边非有限/非正闸 → **三角形不等式闸**（任意两边之和 > 第三边，严格不等；恰等号 = 共线退化 → 拒并出信息码）→ 余弦定理逐角求解 → 反余弦入参域钳位 [−1, 1]（浮点舍入防 ASIN/ACOS 域外 NaN，R45 口径）→ 三角和复验（|Σ−π| < 1E-6 [rad] 才置 bValid）。
- **边界安全条件**：**除零面在余弦定理分母 2·b·c**（三边非正闸已前置拦截，先判后除）；ACOS 入参钳位必做（浮点舍入可致 >1）；禁浮点判等（三角形不等式用严格 > 与容差双口径声明）。
- **命名说明（R28-4）**：泛名 `FC_DL_TriangleSolve` 因与信号发生器 `FB_DL_TriangleGenerator` 同根异义被拒（§2.2 #7），收窄为 `FC_DL_TriangleSolveSSS`，头注释写明命名理由与「SSS 专属、SAS/ASA 不立（拆件即凑数）」边界。

### 序号 8｜`FB_DL_PumpPrimingWatch`（DL_Device）

- **输入输出语义**：输入 bStartCmd [标志]（启泵命令）、bFlowOK/bPressOK [标志]（流量/压力起立反馈，引脚注入）、tPrimeWin [ms]（灌泵确认窗）、bEn/bReset；输出 bPriming [标志]、bPrimed [标志]（灌泵完成放行）、bPrimeFail [标志] + eState + bError + nErrCode。
- **状态机要点**：`eIdle →（bStartCmd）ePriming（灌泵确认窗计时）→（流量 ∧ 压力 双判据同拍持续 tConfirm）ePrimed →（命令撤销）eIdle`；窗满仍无起立 → ePrimeFail + 锁存码（干转前预警）；ELSE 兜底。
- **边界安全条件**：灌泵窗内反馈信号非「先判后信」——起立判据须**本拍复验数据源**（R42 口径）；窗满迁移判据不得只看计时（R41：须反馈仍无效才判失败，反馈迟到临界的同拍竞态用「窗满拍复验一次」收敛）；失能 → 输出清零但锁存保留（R303）；TON 无条件刷新；最小驻留参数提为输入（无魔法数）。
- **分工声明**：`FB_DL_PumpDryRunProtect`（运行期干转）、`FB_DL_PumpCavitationGuard`（运行期汽蚀）、`FB_DL_PumpAlternationLead`（轮值）——本件专管**灌泵期**（启动前充水确认），运行期判据归既有三件，头注释互引分工边界表。

---

## §4 源与合规（逐件，铁律「只借骨不抄肉」全适用）

| 序号 | 来源标签 | 来源/URL 或内部族 | 许可证 | 借鉴点（clean-room 声明） |
|---|---|---|---|---|
| 1 | r70-plan | 内部挂账：`BATTLE_REPORT_R70.md` P0 项 + `FB_DL_ScaleRangeWatch.st` v1.0.0 源码实测 | 本库自有 MIT | 只做复核与披露级点修；判据链全自有 |
| 2 | t1-2-oscat-building | 内部台账 T1-2 行（OSCAT Building 焓湿图族， psychrometrics 公开物理公式链） | EPL-2.0（行为定义借鉴合规，R25 先例） | 只借「按行为定义逐件落地」组纪律与 MagnuS-Tetens 公开公式结构；实现/引脚名/码位 100% 自有；常数属主复用 `FC_DL_VaporPressureSat` 不复制 |
| 3 | t2-6-rockwell-aoi（+t2-8-ne107 次源） | 内部台账 T2-6 行（设备级 AOI 粒度族待挖：阀/电机/夹爪→伺服外围件）+ NE107 健康分级公开语义 | 闭源，按最严口径零代码行 | 只借「设备级粗粒度监视 + 双阈值分型」的组织方式与 NE107 分级公开条款；判据/阈值/码位 100% 自有 |
| 4 | iec-std-wrapper | IEC 61131-3 TIME 语义 + 内部 T0-2 族（Date and Timer → DL_Base 分类事实） | 标准语义，无版权文本 | T0=1 族内补口（允许区间 0~1）；分解语义与既有时间换算件职责分离为自有规格 |
| 5 | t1-6-plcopen | 内部台账 T1-6 行（同步/凸轮族深化方向：外部编码器/动态修调之外的应用侧补口） | 规范文档公开语义，只借分类组织 | 只借「飞剪属同步应用」的分类事实与「同步窗 + 速度匹配」参数域组织；轨迹数学/状态机/码位 100% 自有 |
| 6 | s9-conv（t2-7-packml 次源） | 内部自研线（S-9 输送线工程惯例，R7 先例）+ PackML 最小子集态命名语义 | 工程惯例公开 / ISA-TR88.00.02 公开条款 | 只借「最小子集 + 明确终止态」态组织；岔口三段判据 100% 自有 |
| 7 | t2-1-lgf-math | 内部台账 T2-1 Math 行（R64 订正遗留「三角方向仍待挖」） | 闭源，只借分类事实 | 只借「几何原子归 Math 组」分类事实；余弦定理为公开数学；无任何 LGF 数据结构/命名 |
| 8 | t2-2-lbp（self 判据） | 内部台账 T2-2 行（「命令-监视-判定」三段分层骨架，R11/R13 先例） | 闭源，只借骨架 | 只借三段分层骨架；灌泵窗口/双判据/码位 100% 自有 |

**合规总声明**：本轮 WebSearch 0 次，全部取材来自 `SOURCE_HUNTING_MATRIX.md` 既有台账组与内部族深化，无新开 ☐ 组、无整组收口（✔ 9/27 维持）；零 GPL/AGPL 接触；闭源源零代码行复制；逐件 `.st` 头注释须按铁律 3 写「原创实现（参考 XXX 分类与参数域）」口径。

## §5 收口备注

- 三向一致：收口后由 closeout 脚本合并落盘五件套（R219），INDEX_REGISTRY ∪ 文件树 ∪ 本计划 §2 表逐条对账（R192）。
- 终审按 FB-51 两段式：先对全部抽件跑模板定向扫查（闸覆盖/相迁移闸位/同拍竞态/冻结分支出口），其余快速通读；R333 口径——无人值守轮缺陷只挂账不改码。
- 预算可行动归因（R196）：本轮件数 8、复杂度 7×C2+1×C3、返修轮次待收口后实测，超时主因若出现只记可行动因子。
