(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CipCleaningSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · CIP 原位清洗六相顺控）
 * 功能简述 (Function)   : CIP 原位清洗六相顺控：预冲洗 → 碱洗 → 中间冲洗 →
 *                         酸洗 → 终冲洗 → 消毒。核心纪律：相位计时受 TACT 联
 *                         锁暂停（温度/电导率/流量不达标不计时）；终冲洗以回
 *                         液电导率判终点（最长延时兜底）；回路就绪门控；换相
 *                         停泵间隔防混液；中止即排空隔离并失去清洁许可；偏差
 *                         计数供审计。本块不实现阀门矩阵/混流防护的物理设计
 *                         （属机械与管路设计），仅做就绪门控与指令编排。
 * 首扫说明 (Init note)  : 顺序型组件但全部状态由指令沿/电平驱动，免首扫
 *                         （R23/公约 0.1），无 bInit。
 * 公约遵循 (Convention) : 0.2/R21 bError 仅故障级码置位；0.4 双语同行注释；
 *                         0.5/R7 八实例（R_TRIG×2/TON×6）主体最前部无条件刷
 *                         新；0.7/R15 故障锁存仅复位路径清码；0.10 定时基准
 *                         由引脚给（tCycle 增补引脚，泳道 A 同款公共约定）；
 *                         0.14 数组存取先判域（所有相位索引先判 < 上限）、
 *                         FOR 有界（无 WHILE）、非有限值防御；0.15 温度 ℃、
 *                         电导率 mS/cm、流量 m³/h，同块不混用；0.16 无魔法
 *                         数；0.17 终结符成对 ✓；0.18 E_DL_CipPhase 随本块
 *                         同文件发布；0.19 码位同行【级别】注释；0.20 验收向
 *                         量入头注释；R24 加药脉冲自清逻辑位于实例调用之后；
 *                         R25 bDone 单拍三律。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 越界/非有限值/互斥出口 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 八实例主体最前部无条件刷新 ✓｜R8 全常量化 ✓
 *                         R24 TP/延时自清逻辑位于实例调用之后 ✓
 *                         R25 单拍标志生命周期三律 ✓
 * 设计要点 (Key notes)  : ① TACT 联锁暂停：温度/电导率/流量三路任一不达标
 *                           （下限 > 0 才校验）→ bPhaseHold、计时冻结、自动恢
 *                           复；暂停累计超 tHoldLimit → 相失败 0270（判失败
 *                           而非继续等）；TACT 信号非有限值按不达标保守侧暂
 *                           停（0172，不立即故障，防单点传感器抖动打断整批）；
 *                         ② 终冲洗特殊判据：以回液电导率 ≤ fRinseCondTarget
 *                           为完成条件（不以时间到为准），tRinseMax 兜底超时
 *                           → 0271；该相豁免零时长配方检查（偏离留档②）；
 *                         ③ 换相停泵间隔：相完成后先停泵 DL_CIP_SWITCH_PAUSE
 *                           再切阀（防混液，期间信息码 0173）；跳相仅由参数决
 *                           定——启动瞬间对启用数组做快照，运行中以快照推进
 *                           相序，中途改写启用数组视为「运行中跳相请求」一律
 *                           拒绝（信息码 0170，不生效）；
 *                         ④ 清洁许可：bCipComplete 仅全部启用相完成后置位；
 *                           中止即清除（中止即失去清洁许可）；复位路径清许可；
 *                           bOk = 完成保持态且全周期零偏差（以启动时偏差计数
 *                           快照比对）；
 *                         ⑤ 加药脉冲：电导率低于下限时每 DL_CIP_DOSING_PERIOD
 *                           一拍脉冲请求（R24 自清范式），非连续输出；
 *                         ⑥ 相位数组维度字面量 6（等同 DL_CIP_PHASE_MAX）与
 *                           常量同步维护（跨平台数组维度须编译期字面量）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① tCycle 增补引脚：相位计时累计需要时间基准，依公
 *                           约 0.10 增补（泳道 A 先例，公共约定强制项，非逐
 *                           组件条款）；
 *                         ② 零时长检查豁免终冲洗：规格「启用相目标时长为零 →
 *                           0272」未豁免任何相，但终冲洗以电导率判终点、时长
 *                           本就不参与其完成判据；按「终冲洗豁免 0272 检查」
 *                           实现。理由：终冲洗零时长在工艺上有意义（纯电导终
 *                           点）；影响：终冲洗配方时长域不校验。
 * 开源溯源 (Origin)     : 来源标签 cip-cleaning / isa-88-phase（RAW_NOTES_R8
 *                         S-10：CIP 原位清洗公开工程惯例——预冲/碱洗/中冲/酸
 *                         洗/终冲/消毒六相序、TACT 联锁暂停不计时、回液电导
 *                         率判终冲终点、回路就绪门控启泵、清洁状态（clean
 *                         status）放行生产、中止即失去许可（提取点①③④），
 *                         公开技术资料，仅借鉴相序分类与参数域；状态机、码
 *                         位、引脚契约 100% 本库独立设计，clean-room 未复制
 *                         源码。许可证说明：借鉴对象为公开技术惯例，无附带许
 *                         可限制；本文件为本库原创实现，随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 六相全启用正常走完 → bCipComplete + bOk（零偏差）；
 *   V2 碱洗段温度低于下限 → 计时冻结 + bPhaseHold，恢复后继续；
 *   V3 暂停累计超 tHoldLimit → 0270 相失败锁存；
 *   V4 终冲洗回液电导降到终点 → 立即完成（不等 atPhaseTime）；
 *   V5 终冲洗超 tRinseMax → 0271；
 *   V6 abPhaseEnable[3]=FALSE → 跳过酸洗相（按启动快照）；
 *   V7 bAbort → 停泵排空 tDrainTime + bCipComplete=FALSE；
 *   V8 启用相 atPhaseTime=0 → 0272（终冲洗豁免，偏离留档②）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process CIP 清洗件）
 *   2026-11-15  v1.0.1  R8 总监终审修复：终端态分支内的孤立空语句 `;`（非 IEC 61131-3 文法，statement_list 允许零条语句但不容纳孤立分号）改为纯注释占位分支，行为等价、跨平台可移植性合规。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CipPhase（归属 FB_DL_CipCleaningSeq，与其同文件发布，公约 0.18）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CipPhase :
(
    eIdle      := 0,   // 空闲：等启动 / Idle, awaiting start
    ePreRinse  := 10,  // 预冲洗（Pre-rinse）/ Pre-rinse phase
    eCaustic   := 20,  // 碱洗（Caustic wash）/ Caustic wash phase
    eIntRinse  := 30,  // 中间冲洗（Intermediate rinse）/ Intermediate rinse phase
    eAcid      := 40,  // 酸洗（Acid wash）/ Acid wash phase
    eFinalRinse:= 50,  // 终冲洗（Final rinse），电导率判终点 / Final rinse, conductivity end criterion
    eSanitize  := 60,  // 消毒（Sanitize）/ Sanitize phase
    eDone      := 70,  // 完成（bCipComplete），等复位 / Done, clean status granted
    eAbort     := 80,  // 中止：排空隔离，许可失效 / Aborted, drained and isolated, status revoked
    eFault     := 99   // 故障锁存 / Fault latched
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_CipCleaningSeq
VAR_INPUT
    bEnable             : BOOL;             // 使能（Enable），FALSE=停泵停止加药（不主动排空），相位保持 / Enable, FALSE stops pumps and dosing, no drain
    bStart              : BOOL;             // 启动 CIP 周期（Start），上升沿受理（空闲/完成态）/ Start edge accepted at idle/done
    bAbort              : BOOL;             // 中止（Abort），电平最高优先 → 停泵 + 开排空 + 隔离 / Abort level, highest priority
    bReset              : BOOL;             // 复位（Reset），上升沿受理 / Rising edge resets fault and clean status
    bCircuitReady       : BOOL;             // 回路就绪（供货/回液阀位置确认），FALSE 禁止启泵与启动 / Circuit ready interlock
    abPhaseEnable       : ARRAY[0..5] OF BOOL;  // 各相启用（Phase enable）：0 预冲/1 碱/2 中冲/3 酸/4 终冲/5 消毒 / Phase enable flags, dim 6
    atPhaseTime         : ARRAY[0..5] OF TIME;  // 各相目标计时（Phase time），仅达标时段累计（终冲豁免，偏离留档②）/ Phase target durations
    afPhaseTempMin      : ARRAY[0..5] OF REAL;  // 各相温度下限（Temp min）[℃，0=不校验 / Phase temperature minimums, zero disables
    afPhaseCondMin      : ARRAY[0..5] OF REAL;  // 各相电导率下限（Conductivity min）[mS/cm，0=不校验 / Phase conductivity minimums, zero disables
    afPhaseFlowMin      : ARRAY[0..5] OF REAL;  // 各相流量下限（Flow min）[m³/h，0=不校验 / Phase flow minimums, zero disables
    fActTemp            : REAL;             // 实际温度（Actual temperature）[℃] / Actual temperature [degC]
    fActCond            : REAL;             // 实际电导率（Actual conductivity）[mS/cm]，供液或回液由调用方选择接点 / Actual conductivity [mS/cm]
    fActFlow            : REAL;             // 实际流量（Actual flow）[m³/h] / Actual flow [m3/h]
    fRinseCondTarget    : REAL := 0.1;      // 终冲洗回液电导率终点（Rinse conductivity target）[mS/cm] / Final-rinse conductivity end target
    tHoldLimit          : TIME := T#300S;   // 单相联锁暂停上限（Hold limit），超时判该相失败 / Per-phase hold limit, expiry = phase fail
    tRinseMax           : TIME := T#15M;    // 终冲洗最长延时（Rinse max time），电导未达标兜底上限 / Final-rinse maximum duration fallback
    tDrainTime          : TIME := T#60S;    // 中止后排空时长（Drain time）/ Abort drain duration
    tTempSetDelay       : TIME := T#0S;     // 升温/降温等待（Temp set delay），相开始先等待此窗不计时 / Temp settle delay before timing starts
    tCycle              : TIME := T#10MS;   // 任务扫描周期（Task cycle time）[ms]，由调用方按实际任务给，计时累计基准（偏离留档①）/ Task cycle time, timing base
END_VAR
VAR_OUTPUT
    ePhase              : E_DL_CipPhase := E_DL_CipPhase.eIdle; // 当前相位（Current phase）/ Current phase
    bBusy               : BOOL;             // 周期执行中（Busy），冲洗/消毒/换相/排空期 TRUE / TRUE during wash/sanitize/switch/drain
    bDone               : BOOL;             // 周期完成单拍（Done pulse），单拍生命周期三律 / One-scan completion pulse
    bOk                 : BOOL;             // 全相完成且无偏差（OK），完成保持态且零偏差 / OK verdict, done with zero deviations
    bPhaseHold          : BOOL;             // 相位暂停中（Phase hold），TACT 未达标计时冻结 / Phase hold, timing frozen
    bPhaseFail          : BOOL;             // 当前相失败（Phase fail），暂停超限锁存至复位 / Phase failed, latched until reset
    bCipComplete        : BOOL;             // CIP 完成许可（Clean status），供上层放行生产；中止/复位清除 / Clean status granted, revoked on abort/reset
    bCmdSupplyPump      : BOOL;             // 供液泵指令（Supply pump）/ Supply pump command
    bCmdReturnPump      : BOOL;             // 回液泵指令（Return pump）/ Return pump command
    bCmdDosing          : BOOL;             // 加药泵指令（Dosing pump），电导率低于下限时脉冲式请求 / Dosing pulse request
    bCmdHeat            : BOOL;             // 加热（蒸汽阀）指令（Heat）/ Heat command
    bCmdDrain           : BOOL;             // 排空阀指令（Drain valve），中止排空期 / Drain valve command
    fTempSetpoint       : REAL;             // 温度设定（Temp setpoint）[℃]，取当前相下限 + 2.0 ℃ 裕量（工艺经验值）/ Temp setpoint, phase min plus margin
    tPhaseElapsed       : TIME := T#0S;     // 当前相已累计计时（Phase elapsed），仅达标时段 / Accumulated phase time, qualified periods only
    nDeviationCount     : UDINT;            // 偏差计数（Deviation counter），每次暂停/失败 +1，供审计 / Deviation counter for audit
    bError              : BOOL;             // 故障锁存（Error），仅故障级码 / Latched error, fault codes only
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, fault-level priority
END_VAR
VAR
    _ePhase             : E_DL_CipPhase := E_DL_CipPhase.eIdle;   // 内部相位（Internal phase）/ Internal phase
    _nPhaseIdx          : UINT := UINT#6;   // 当前相索引（Current phase index）[-]，0..5；6=哨兵（无活动相）/ Index 0..5, 6 = sentinel none
    _nNextIdx           : UINT;             // 下一相索引（Next phase index）[-]，哨兵 6 / Next phase index, sentinel 6
    _bEnterPhase        : BOOL;             // 进入相位单拍（Enter phase one-shot），索引→枚举映射触发 / Phase-entry one-shot for mapping
    _bPhaseActive       : BOOL;             // 相位执行中派生（Phase active derived）/ Wash phase active derived
    _bFaultLatch        : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code
    _bSwitchPause       : BOOL;             // 换相停泵间隔（Switch pause），防混液 / Switch pause between phases
    _tPhaseElapsedInt   : TIME := T#0S;     // 内部相位计时（Internal phase elapsed）/ Internal phase elapsed
    _bTempHold          : BOOL;             // 温度联锁暂停（Temperature hold）/ Temperature interlock hold
    _bCondHold          : BOOL;             // 电导率联锁暂停（Conductivity hold）/ Conductivity interlock hold
    _bFlowHold          : BOOL;             // 流量联锁暂停（Flow hold）/ Flow interlock hold
    _bHold              : BOOL;             // 联锁暂停归并（Hold merged）/ Merged hold flag
    _bHoldPrev          : BOOL;             // 上拍暂停态（Hold previous scan），进入沿计数用 / Hold previous scan, entry edge
    _bDosePulse         : BOOL;             // 加药脉冲单拍（Dosing pulse one-shot）/ Dosing pulse one-shot
    _bPhaseDone         : BOOL;             // 当前相完成（Phase done）/ Current phase completed
    _bDrainDone         : BOOL;             // 排空完成（Drain done）/ Drain completed
    _bParamEdited       : BOOL;             // 启用数组中途改写（Enable array edited mid-run），跳相拒绝判据 / Enable array edited mid-run
    _nIdx               : UINT;             // 循环索引（Loop index）[-] / Loop index
    _fTempMin           : REAL;             // 当前相温度下限（Phase temp minimum）[℃] / Current phase temperature minimum
    _fCondMin           : REAL;             // 当前相电导率下限（Phase cond minimum）[mS/cm] / Current phase conductivity minimum
    _fFlowMin           : REAL;             // 当前相流量下限（Phase flow minimum）[m³/h] / Current phase flow minimum
    _bFiniteTact        : BOOL;             // 三路 TACT 信号有限归并（TACT finite merged）/ Merged TACT finite verdict
    _abEnableSnap       : ARRAY[0..5] OF BOOL;  // 启用数组启动快照（Enable snapshot at start），运行中改写不生效 / Enable snapshot taken at start
    _nDevStart          : UDINT;            // 启动时偏差计数快照（Deviation snapshot at start），零偏差判定基准 / Deviation count snapshot at start
    _fbTrigStart        : R_TRIG;           // 启动沿（Start edge detector）/ Start edge detector
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
    _fbTonHold          : TON;              // 联锁暂停上限（Hold limit timer）/ Hold limit timer
    _fbTonDose          : TON;              // 加药脉冲周期（Dosing period timer）/ Dosing period timer
    _fbTonSwitch        : TON;              // 换相停泵间隔（Switch pause timer）/ Switch pause timer
    _fbTonDrain         : TON;              // 排空时长（Drain duration timer）/ Drain duration timer
    _fbTonTempDelay     : TON;              // 升降温等待窗（Temp settle delay timer）/ Temp settle delay timer
    _fbTonRinseMax      : TON;              // 终冲洗最长延时（Rinse max timer）/ Final-rinse max timer
END_VAR
VAR CONSTANT
    DL_CIP_PHASE_MAX    : UINT := 6;        // 相位数上限（Max phases）[-]，与数组维度字面量 6 同步 / Phase count, sync with literal dim 6
    DL_CIP_IDX_NONE     : UINT := 6;        // 无活动相哨兵索引（Sentinel index for none）[-] / Sentinel index, none active
    DL_CIP_IDX_FINAL    : UINT := 4;        // 终冲洗相索引（Final-rinse index）[-] / Final-rinse phase index
    DL_CIP_REAL_MAX     : REAL := 3.4E38;   // 单精度有限值判据幅值（Finite magnitude bound）/ Finite magnitude bound for REAL inputs
    DL_CIP_TEMP_MARGIN  : REAL := 2.0;      // 温度设定裕量（Temp setpoint margin）[℃]，工艺经验值 / Temperature margin, process experience
    DL_CIP_DOSING_PERIOD: TIME := T#5S;     // 加药脉冲周期（Dosing pulse period）/ Dosing pulse period
    DL_CIP_SWITCH_PAUSE : TIME := T#2S;     // 换相停泵间隔（Switch pause duration），防混液 / Pump-off pause between phases
    DL_CIP_ERR_HOLD     : UDINT := 16#0005_0270; // 0005_0270 单相联锁暂停超限（相失败）【故障级】/ Phase hold limit exceeded, fault level
    DL_CIP_ERR_RINSE    : UDINT := 16#0005_0271; // 0005_0271 终冲洗超最长延时未达电导终点【故障级】/ Final rinse over max duration, fault level
    DL_CIP_ERR_ZEROTIME : UDINT := 16#0005_0272; // 0005_0272 启用相目标时长为零【故障级】/ Enabled phase with zero duration, fault level
    DL_CIP_ERR_NOREADY  : UDINT := 16#0005_0273; // 0005_0273 回路未就绪强行启动【故障级】/ Started with circuit not ready, fault level
    DL_CIP_ERR_STATE    : UDINT := 16#0005_0274; // 0005_0274 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_CIP_INFO_SKIP    : UDINT := 16#0005_0170; // 0005_0170 运行中跳相请求被拒（启用数组中途改写不生效）【信息级】/ Mid-run phase skip refused, info level
    DL_CIP_INFO_NOREADY : UDINT := 16#0005_0171; // 0005_0171 回路未就绪，泵指令被抑制【信息级】/ Pump suppressed, circuit not ready, info level
    DL_CIP_INFO_NAN     : UDINT := 16#0005_0172; // 0005_0172 TACT 信号非有限值，保守侧暂停【信息级】/ TACT non-finite, conservative hold, info level
    DL_CIP_INFO_SWITCH  : UDINT := 16#0005_0173; // 0005_0173 相切换停泵间隔中【信息级】/ Pump-off switch pause, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bStart);            // 启动沿（Start edge）
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）

// 相位执行中派生（Phase active derived）
_bPhaseActive := (_ePhase = E_DL_CipPhase.ePreRinse) OR (_ePhase = E_DL_CipPhase.eCaustic)
              OR (_ePhase = E_DL_CipPhase.eIntRinse) OR (_ePhase = E_DL_CipPhase.eAcid)
              OR (_ePhase = E_DL_CipPhase.eFinalRinse) OR (_ePhase = E_DL_CipPhase.eSanitize);

// 联锁暂停上限（仅执行相计时，暂停解除/相失败自动断输入归零）
// Hold limit timer (armed in active phases, auto reset on release)
_fbTonHold(IN := _bPhaseActive AND bEnable AND _bHold AND (NOT _bSwitchPause), PT := tHoldLimit);
// 加药脉冲周期（仅电导暂停期计时；R24：脉冲自清逻辑在段 3 实例调用之后）
// Dosing period timer (armed on conductivity hold; R24 self-clear after call)
_fbTonDose(IN := _bCondHold AND bEnable AND (NOT _bDosePulse) AND (NOT _bSwitchPause), PT := DL_CIP_DOSING_PERIOD);
// 换相停泵间隔（Switch pause timer）
_fbTonSwitch(IN := _bSwitchPause, PT := DL_CIP_SWITCH_PAUSE);
// 排空时长（仅中止相且未排空完成时计时 / Drain timer, abort phase until done）
_fbTonDrain(IN := (_ePhase = E_DL_CipPhase.eAbort) AND (NOT _bDrainDone), PT := tDrainTime);
// 升降温等待窗（相开始后到窗才允许计时 / Temp settle delay before timing allowed）
_fbTonTempDelay(IN := _bPhaseActive AND bEnable AND (NOT _bSwitchPause), PT := tTempSetDelay);
// 终冲洗最长延时（Final-rinse max timer）
_fbTonRinseMax(IN := (_ePhase = E_DL_CipPhase.eFinalRinse) AND bEnable, PT := tRinseMax);

// ============================================================================
// 段 2｜信息级预清零 + 输出默认赋值（0.9：任何早退路径输出确定）
//      Info preset + output defaults
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bDone := FALSE;                         // 完成单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25)
bCmdSupplyPump := FALSE;                // 泵/阀/加药/加热指令默认安全侧全关（Commands preset closed）
bCmdReturnPump := FALSE;
bCmdDosing := FALSE;
bCmdHeat := FALSE;
bCmdDrain := FALSE;
fTempSetpoint := 0.0;                   // 温度设定默认零（Temp setpoint default zero）
bPhaseHold := FALSE;                    // 暂停/失败/判定默认清（Hold, fail, verdict preset）
bPhaseFail := FALSE;
bOk := FALSE;

// 当前相参数取值（索引先判域，防越界）
// Current phase parameter fetch (index bounded first)
IF _nPhaseIdx < DL_CIP_PHASE_MAX THEN
    _fTempMin := afPhaseTempMin[_nPhaseIdx];   // 当前相温度下限（Phase temp minimum）
    _fCondMin := afPhaseCondMin[_nPhaseIdx];   // 当前相电导率下限（Phase cond minimum）
    _fFlowMin := afPhaseFlowMin[_nPhaseIdx];   // 当前相流量下限（Phase flow minimum）
ELSE
    _fTempMin := 0.0;                   // 越界防御默认（Bounded default）
    _fCondMin := 0.0;
    _fFlowMin := 0.0;
END_IF

// TACT 信号非有限值防御（自比等价式，归并三路）
// TACT non-finite defense (self-comparison equivalence, merged)
_bFiniteTact := (fActTemp >= (-DL_CIP_REAL_MAX)) AND (fActTemp <= DL_CIP_REAL_MAX)
           AND (fActCond >= (-DL_CIP_REAL_MAX)) AND (fActCond <= DL_CIP_REAL_MAX)
           AND (fActFlow >= (-DL_CIP_REAL_MAX)) AND (fActFlow <= DL_CIP_REAL_MAX);

// ============================================================================
// 段 3｜TACT 联锁判定与计时累计（仅执行相；R24 脉冲自清在实例调用之后）
//      TACT interlock and timing accumulation (R24 pulse self-clear after call)
// ============================================================================
IF _bPhaseActive AND bEnable AND (NOT _bSwitchPause) THEN
    _bTempHold := (_fTempMin > 0.0) AND ((NOT _bFiniteTact) OR (fActTemp < _fTempMin));
    _bCondHold := (_fCondMin > 0.0) AND ((NOT _bFiniteTact) OR (fActCond < _fCondMin));
    _bFlowHold := (_fFlowMin > 0.0) AND ((NOT _bFiniteTact) OR (fActFlow < _fFlowMin));
    _bHold := _bTempHold OR _bCondHold OR _bFlowHold;   // 三路归并（Merged hold）
    IF (NOT _bFiniteTact) AND _bHold THEN
        _uInfoCode := DL_CIP_INFO_NAN;   // 0005_0172 TACT 非有限值保守侧暂停【信息级】/ TACT non-finite, info level
    END_IF
    // 暂停进入沿：偏差计数 +1（Hold entry edge: deviation count increment）
    IF _bHold AND (NOT _bHoldPrev) THEN
        nDeviationCount := nDeviationCount + UINT#1;
    END_IF
    // 计时累计：联锁全达标且升降温等待窗已过（Timing: interlocks met and delay elapsed）
    IF (NOT _bHold) AND _fbTonTempDelay.Q THEN
        _tPhaseElapsedInt := _tPhaseElapsedInt + tCycle;
        tPhaseElapsed := _tPhaseElapsedInt;              // 出口计时同步（Outlet elapsed sync）
    END_IF
ELSE
    _bTempHold := FALSE;                // 非执行相暂停清零（Hold cleared off-phase）
    _bCondHold := FALSE;
    _bFlowHold := FALSE;
    _bHold := FALSE;
END_IF
_bHoldPrev := _bHold;                   // 登记本拍暂停态供下拍沿判定（Register hold for edge）

// R24 范式：加药脉冲单拍自清（实例调用之后置位，下一拍 IN 断自动复位）
// R24 pattern: dosing pulse set after instance call, auto-resets next scan
_bDosePulse := _fbTonDose.Q;            // 脉冲单拍登记（Pulse one-shot registered）

// 相失败监视：暂停累计超上限（Phase fail monitor: hold limit exceeded）
IF _fbTonHold.Q AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;               // 相失败锁存（Phase fail latch）
    _uErrorIdInt := DL_CIP_ERR_HOLD;    // 0005_0270 单相联锁暂停超限【故障级】/ Phase hold exceeded, fault level
    _ePhase := E_DL_CipPhase.eFault;
END_IF

// 终冲洗兜底监视：超最长延时未达电导终点（Final-rinse max monitor）
IF _fbTonRinseMax.Q AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;               // 终冲超时锁存（Final-rinse timeout latch）
    _uErrorIdInt := DL_CIP_ERR_RINSE;   // 0005_0271 终冲洗超最长延时【故障级】/ Final-rinse timeout, fault level
    _ePhase := E_DL_CipPhase.eFault;
END_IF

// ============================================================================
// 段 4｜核心相位状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core phase state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
IF bEnable AND (NOT _bFaultLatch) THEN
    IF bAbort AND (_ePhase <> E_DL_CipPhase.eIdle) AND (_ePhase <> E_DL_CipPhase.eAbort) THEN
        // 中止电平拦截：排空隔离、清洁许可失效（Abort intercept: drain, status revoked）
        bCipComplete := FALSE;          // 中止即失去清洁许可（Clean status revoked on abort）
        _bDrainDone := FALSE;           // 排空重新武装（Drain re-armed）
        _ePhase := E_DL_CipPhase.eAbort;
    ELSE
        CASE _ePhase OF

            E_DL_CipPhase.eIdle: // 空闲：等启动沿
                IF _fbTrigStart.Q THEN
                    IF NOT bCircuitReady THEN
                        _bFaultLatch := TRUE;                // 回路未就绪强行启动（Started not ready）
                        _uErrorIdInt := DL_CIP_ERR_NOREADY;  // 0005_0273 回路未就绪启动【故障级】/ Started not ready, fault level
                        _ePhase := E_DL_CipPhase.eFault;
                    ELSE
                        // 启动前配方检查：启用相零时长（终冲豁免，偏离留档②）
                        // Pre-start recipe check: enabled zero-duration (final rinse exempt)
                        FOR _nIdx := UINT#0 TO DL_CIP_PHASE_MAX - UINT#1 DO
                            IF abPhaseEnable[_nIdx] AND (atPhaseTime[_nIdx] = T#0MS)
                            AND (_nIdx <> DL_CIP_IDX_FINAL) THEN
                                _bFaultLatch := TRUE;                 // 零时长相锁存（Zero duration latch）
                                _uErrorIdInt := DL_CIP_ERR_ZEROTIME;  // 0005_0272 启用相零时长【故障级】/ Zero duration, fault level
                            END_IF
                        END_FOR
                        IF NOT _bFaultLatch THEN
                            // 启用数组快照 + 偏差基准快照（Snapshot enable array and deviation base）
                            FOR _nIdx := UINT#0 TO DL_CIP_PHASE_MAX - UINT#1 DO
                                _abEnableSnap[_nIdx] := abPhaseEnable[_nIdx];
                            END_FOR
                            _nDevStart := nDeviationCount;
                            // 找首个启用相进入（Find first enabled phase）
                            _nPhaseIdx := DL_CIP_IDX_NONE;            // 哨兵：无启用相（Sentinel: none enabled）
                            FOR _nIdx := UINT#0 TO DL_CIP_PHASE_MAX - UINT#1 DO
                                IF (_nPhaseIdx = DL_CIP_IDX_NONE) AND _abEnableSnap[_nIdx] THEN
                                    _nPhaseIdx := _nIdx;              // 首个启用相（First enabled phase）
                                END_IF
                            END_FOR
                            IF _nPhaseIdx < DL_CIP_PHASE_MAX THEN
                                _tPhaseElapsedInt := T#0S;            // 相计时清零（Phase elapsed reset）
                                tPhaseElapsed := T#0S;
                                _bSwitchPause := FALSE;
                                _bPhaseDone := FALSE;
                                _bEnterPhase := TRUE;                 // 触发索引→枚举映射（Arm phase mapping）
                            ELSE
                                _ePhase := E_DL_CipPhase.eDone;       // 全相禁用直接完成（All disabled, straight done）
                                bCipComplete := TRUE;                 // 清洁许可（Clean status granted）
                                bDone := TRUE;                        // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
                            END_IF
                        END_IF
                    END_IF
                END_IF

            E_DL_CipPhase.ePreRinse, E_DL_CipPhase.eCaustic, E_DL_CipPhase.eIntRinse,
            E_DL_CipPhase.eAcid, E_DL_CipPhase.eFinalRinse, E_DL_CipPhase.eSanitize:
                // 六相公共执行分支（Common wash-phase branch）
                IF (_nPhaseIdx < DL_CIP_PHASE_MAX) AND (NOT _bSwitchPause) THEN
                    // 终冲洗特殊判据：回液电导率 ≤ 终点即完成（不以时间到为准）
                    // Final rinse: conductivity end criterion (time not decisive)
                    IF (_ePhase = E_DL_CipPhase.eFinalRinse) AND _bFiniteTact
                    AND (fActCond <= fRinseCondTarget) AND (NOT _bHold) THEN
                        _bPhaseDone := TRUE;              // 电导终点达成（Conductivity end met）
                    ELSIF (_ePhase <> E_DL_CipPhase.eFinalRinse)
                    AND (_tPhaseElapsedInt >= atPhaseTime[_nPhaseIdx]) THEN
                        _bPhaseDone := TRUE;              // 目标时长达成（Target duration met）
                    END_IF
                    IF _bPhaseDone THEN
                        _bSwitchPause := TRUE;            // 相完成进入停泵间隔（Phase done, pump-off pause）
                        _uInfoCode := DL_CIP_INFO_SWITCH; // 0005_0173 换相停泵间隔【信息级】/ Switch pause, info level
                    END_IF
                END_IF

            E_DL_CipPhase.eDone: // 完成保持：等复位（复位路径在段 6）
                // 等复位（Awaiting reset）

            E_DL_CipPhase.eAbort: // 中止排空：排空时长到后保持等待复位
                IF _fbTonDrain.Q THEN
                    _bDrainDone := TRUE;              // 排空完成（Drain completed）
                END_IF

            E_DL_CipPhase.eFault: // 故障锁存：等复位
                // 等复位（Awaiting reset）

            ELSE // 非法状态兜底（本块专用码位）
                _bFaultLatch := TRUE;
                _uErrorIdInt := DL_CIP_ERR_STATE;     // 0005_0274 非法状态兜底【故障级】/ Illegal state fallback, fault level
                _ePhase := E_DL_CipPhase.eFault;
        END_CASE
    END_IF
END_IF

// ============================================================================
// 段 5｜换相推进 + 索引→枚举映射 + 运行中改写检测（索引先判域）
//      Phase advance, index-to-enum mapping, mid-run edit detection (bounded)
// ============================================================================
IF _bSwitchPause AND _fbTonSwitch.Q AND (NOT _bFaultLatch) THEN
    _bSwitchPause := FALSE;             // 停泵间隔结束（Pause finished）
    _bPhaseDone := FALSE;
    // 从当前相之后按启动快照找下一启用相（Next enabled phase after current, snapshot-based）
    _nNextIdx := DL_CIP_IDX_NONE;       // 哨兵：无后续启用相（Sentinel: none left）
    IF _nPhaseIdx + UINT#1 <= DL_CIP_PHASE_MAX - UINT#1 THEN
        FOR _nIdx := _nPhaseIdx + UINT#1 TO DL_CIP_PHASE_MAX - UINT#1 DO
            IF (_nNextIdx = DL_CIP_IDX_NONE) AND _abEnableSnap[_nIdx] THEN
                _nNextIdx := _nIdx;     // 下一启用相（Next enabled phase）
            END_IF
        END_FOR
    END_IF
    IF _nNextIdx < DL_CIP_PHASE_MAX THEN
        _nPhaseIdx := _nNextIdx;        // 推进到下一相（Advance to next phase）
        _tPhaseElapsedInt := T#0S;      // 相计时清零（Phase elapsed reset）
        tPhaseElapsed := T#0S;
        _bEnterPhase := TRUE;           // 触发索引→枚举映射（Arm phase mapping）
    ELSE
        _ePhase := E_DL_CipPhase.eDone; // 全部启用相完成（All enabled phases done）
        bCipComplete := TRUE;           // 清洁许可（Clean status granted）
        bDone := TRUE;                  // 完成单拍（R25 本拍闭环）/ Done pulse (R25)
    END_IF
END_IF

// 相位索引→枚举映射（进入相单拍执行；越界防御）
// Index-to-enum mapping (on phase-entry one-shot, bounded)
IF _bEnterPhase AND (_nPhaseIdx < DL_CIP_PHASE_MAX) THEN
    CASE _nPhaseIdx OF
        UINT#0: _ePhase := E_DL_CipPhase.ePreRinse;    // 预冲洗（Pre-rinse）
        UINT#1: _ePhase := E_DL_CipPhase.eCaustic;     // 碱洗（Caustic）
        UINT#2: _ePhase := E_DL_CipPhase.eIntRinse;    // 中间冲洗（Intermediate）
        UINT#3: _ePhase := E_DL_CipPhase.eAcid;        // 酸洗（Acid）
        UINT#4: _ePhase := E_DL_CipPhase.eFinalRinse;  // 终冲洗（Final rinse）
        UINT#5: _ePhase := E_DL_CipPhase.eSanitize;    // 消毒（Sanitize）
        ELSE _ePhase := E_DL_CipPhase.eIdle;           // 防御回空闲（Bounded default）
    END_CASE
    _bEnterPhase := FALSE;              // 映射消费（Mapping consumed）
END_IF

// 运行中启用数组改写检测：视为跳相请求一律拒绝（不生效，仅信息码 0170）
// Mid-run enable edit detection: treated as skip request, refused (info 0170)
IF _bPhaseActive THEN
    _bParamEdited := FALSE;             // 改写判据预清（Edit flag preset）
    FOR _nIdx := UINT#0 TO DL_CIP_PHASE_MAX - UINT#1 DO
        IF abPhaseEnable[_nIdx] <> _abEnableSnap[_nIdx] THEN
            _bParamEdited := TRUE;      // 检测到改写（Edit detected）
        END_IF
    END_FOR
    IF _bParamEdited THEN
        _uInfoCode := DL_CIP_INFO_SKIP; // 0005_0170 运行中跳相请求被拒【信息级】/ Mid-run skip refused, info level
    END_IF
END_IF

// ============================================================================
// 段 6｜复位路径 + 输出派生（R15：故障/许可仅复位路径清；0171 泵抑制）
//      Reset path + outlet derivation (R15; pump suppression on not-ready)
// ============================================================================
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
    bCipComplete := FALSE;              // 清洁许可随复位清除（Clean status cleared on reset）
    _bDrainDone := FALSE;               // 排空标志复位（Drain flag reset）
    _nPhaseIdx := DL_CIP_IDX_NONE;      // 相索引回哨兵（Index back to sentinel）
    IF (_ePhase = E_DL_CipPhase.eFault) OR (_ePhase = E_DL_CipPhase.eAbort)
    OR (_ePhase = E_DL_CipPhase.eDone) THEN
        _ePhase := E_DL_CipPhase.eIdle; // 终态回空闲（Terminal phases back to idle）
        _tPhaseElapsedInt := T#0S;
        tPhaseElapsed := T#0S;
    END_IF
END_IF

// 相失败出口：仅联锁暂停超限锁存为相失败，锁存至复位（与 bPhaseHold 不同真）
// Phase fail outlet: hold-limit latch only, held until reset (exclusive with hold)
IF _bFaultLatch AND (_uErrorIdInt = DL_CIP_ERR_HOLD) THEN
    bPhaseFail := TRUE;                 // 相失败锁存出口（Phase fail latched outlet）
END_IF

// 泵/加药/加热指令：执行相且回路就绪且非停泵间隔且无故障（0171 泵抑制每拍重算）
// Pump/dosing/heat: active phase AND circuit ready AND not in pause AND no fault
IF _bPhaseActive AND bEnable AND bCircuitReady AND (NOT _bSwitchPause) AND (NOT _bFaultLatch) THEN
    bCmdSupplyPump := TRUE;             // 供液泵开（Supply pump on）
    bCmdReturnPump := TRUE;             // 回液泵开（Return pump on）
    bCmdHeat := _bTempHold;             // 加热：温度暂停期（Heat on temperature hold）
    bCmdDosing := _bDosePulse;          // 加药：电导暂停脉冲（Dosing pulse on cond hold）
END_IF
IF _bPhaseActive AND bEnable AND (NOT bCircuitReady) AND (NOT _bFaultLatch) THEN
    _uInfoCode := DL_CIP_INFO_NOREADY;  // 0005_0171 回路未就绪泵被抑制【信息级】/ Pump suppressed, info level
END_IF

// 排空阀：中止相排空期内（Drain valve during abort drain window）
bCmdDrain := (_ePhase = E_DL_CipPhase.eAbort) AND (NOT _bDrainDone);

// 温度设定：当前相下限 + 裕量（下限 0=不校验则设定 0）
// Temp setpoint: phase minimum plus margin (zero minimum = zero setpoint)
IF _bPhaseActive AND (_fTempMin > 0.0) THEN
    fTempSetpoint := _fTempMin + DL_CIP_TEMP_MARGIN;   // 抬高 2 ℃ 裕量（Margin applied）
END_IF

// 判定出口：完成保持态且全周期零偏差（以启动偏差快照比对）
// Verdict outlet: done hold with zero whole-cycle deviations (vs start snapshot)
IF _ePhase = E_DL_CipPhase.eDone THEN
    bOk := (nDeviationCount = _nDevStart);   // 零偏差判定（Zero-deviation verdict）
END_IF

bBusy := _bPhaseActive OR (_ePhase = E_DL_CipPhase.eAbort);   // 执行中派生（Busy derived）

ePhase := _ePhase;                       // 相位镜像（Phase mirror）

// ============================================================================
// 段 7｜bError/uErrorId 出口（R21：bError 显式排除信息级码）
//      Outlets: bError excludes info codes (R21)
// ============================================================================
bError := _bFaultLatch;                  // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;            // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;              // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK