//==============================================================================
// 功能块：FB_DL_ChillerSeqMgr ｜ 中文名称：冷水机组群控调度
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：6 台冷水机组群控：按平滑后负荷率加减机（加/减各带独立延迟，双延迟防抖动）
//           + 主备轮值均衡（委托 FB_DL_DutyStandbyRotation，最短运行/最短停机时长逻辑
//           一律由该件承担，本件只把 tMinRun/tMinStop 转发，绝不重复实现）+ 故障切备
//           （故障台由轮值件跳过）+ 供水低温保护（强制减机，防冻管）。本件不内联机组建模
//           与机组自身控制（压缩机/冷却水阀/防冻判据归设备层），只出启停命令与调度诊断。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：温度[摄氏度] / 负荷率与阈值[百分数] / 延迟与最小时长[min] / 扫描间隔[ms] /
//         台数[台] / 机组号[号]
// 错误码表：16#0005_040C 信息级（加/减机延迟计时中，尚未动作，不置 bError）/
//           16#0005_040D 信息级（供水温度低限保护强制减机，信息级不锁故障但强制动作）/
//           16#0005_0354 故障级（无可用机组：全故障或全不就绪，工艺停机级，置 bError）/
//           16#0005_0355 故障级（负荷率/阈值组态非法：减机阈值 ≥ 加机阈值、阈值越
//           0~100、台数组态非法；兼轮值件参数冲突透传——轮值件 bError 透传复位且只在
//           故障相处置，R115）/ 16#0005_0356 故障级（输入非有限独立分支显式映射入本槽，
//           兼状态机 ELSE 非法状态兜底）。0356 共用反证句：非有限与非法状态在现有输出
//           组合下不可观测出差异（均为 bError + 全撤指令 + bValid 撤 + eState 进 eFault），
//           §3 未给本件独立非有限槽，故显式复用不越段。
// 状态机：E_DL_ChillerGroupState（eIdle=0 待机 / eRunning=10 稳态调度 /
//           eStageUp=20 加机延迟中 / eStageDown=30 减机延迟中 / eLowSupply=40 供水低温
//           保护 / eFault=99 故障兜底），CASE 含 ELSE 兜底，ELSE 置 0356 且全撤指令。
// 边界行为：① 无可用机组（全故障或全不就绪）→ 故障 0354 + bNoAvailable（工艺停机级，
//           非提示级）；② 阈值组态非法（减机阈值 ≥ 加机阈值、阈值不在 0~100）→ 故障
//           0355；③ 供水温度 < fSupplyLowC → 强制减机一台 + 信息 040D + bLowSupplyProtect
//           （防冻管，信息级不锁故障但强制动作）；④ 加减机延迟计时中 → 信息 040C；
//           ⑤ 需求台数域 0~6 钳位，且不超过可用台数；⑥ 非有限 → 独立分支显式置 0356，
//           全撤指令；⑦ 失能 → 全撤指令 + bValid := FALSE（R72）；⑧ 轮值调用
//           FB_DL_DutyStandbyRotation（组合调用），tMinRunTime/tMinStopTime 由本件引脚
//           转发，最短运行/停机逻辑不重复实现；轮值件 bError 透传复位并在故障相处置。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.18，依赖 DL_Base 件 FB_DL_DutyStandbyRotation 语义）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_ChillerGroupState（归属 DL_Process，与 FB_DL_ChillerSeqMgr 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ChillerGroupState :
(
    eIdle      := 0,   // 待机：失能，指令全撤 / Idle, all commands dropped
    eRunning   := 10,  // 稳态调度：负荷在双阈值之间 / Steady scheduling, load inside both thresholds
    eStageUp   := 20,  // 加机延迟中：负荷高于加机阈值，等延迟到点 / Stage-up delay running
    eStageDown := 30,  // 减机延迟中：负荷低于减机阈值，等延迟到点 / Stage-down delay running
    eLowSupply := 40,  // 供水低温保护：强制减机 / Supply low-temperature protection, forced stage-down
    eFault     := 99   // 故障兜底：无可用机组/组态非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ChillerSeqMgr
 * 调用约定: 每个扫描周期无条件调用一次；uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ChillerSeqMgr
VAR_INPUT
    abChillerReady   : ARRAY[0..5] OF BOOL;        // 机组就绪（无故障、无就地、无禁止）/ Unit ready
    abChillerRunning : ARRAY[0..5] OF BOOL;        // 机组运行反馈 / Unit running feedback
    abChillerFault   : ARRAY[0..5] OF BOOL;        // 机组故障（轮值件跳过并允许立即停机）/ Unit fault
    fSupplyC         : LREAL;                      // 冷冻水供水温度 [摄氏度] / Chilled-water supply temperature [degC]
    fReturnC         : LREAL;                      // 冷冻水回水温度 [摄氏度] / Chilled-water return temperature [degC]
    fLoadPct         : LREAL;                      // 当前负荷率 [百分数] / Current load [percent]
    fStageUpThrPct   : LREAL := 85.0;              // 加机阈值 [百分数] / Stage-up threshold [percent]
    fStageDownThrPct : LREAL := 40.0;              // 减机阈值 [百分数] / Stage-down threshold [percent]
    tStageUpDelay    : TIME := T#10M;              // 加机延迟 [min] / Stage-up delay [min]
    tStageDownDelay  : TIME := T#15M;              // 减机延迟 [min] / Stage-down delay [min]
    tMinRun          : TIME := T#15M;              // 最小运行时长 [min]，转发轮值件 / Minimum run time, forwarded
    tMinStop         : TIME := T#10M;              // 最小停机时长 [min]，转发轮值件 / Minimum stop time, forwarded
    fSupplyLowC      : LREAL := 4.0;               // 供水低温保护门限 [摄氏度] / Supply low-temperature threshold [degC]
    bEnable          : BOOL;                       // 总使能 / Master enable
    bReset           : BOOL;                       // 复位，上升沿清调度状态并透传轮值件 / Reset, rising edge clears the schedule and the duty block
    uDeltaTimeMs     : UDINT;                      // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
END_VAR
VAR_OUTPUT
    abStartCmd       : ARRAY[0..5] OF BOOL;        // 机组启停命令（FALSE = 停）/ Unit start command, FALSE = stop
    nLeadChiller     : INT;                        // 领机号 0~5，-1 = 无 / Lead chiller 0..5, -1 = none
    nRunningCmd      : INT;                        // 指令开机台数 [台] / Commanded running units [pcs]
    fLoadAvgPct      : LREAL;                      // 平滑后负荷率 [百分数] / Smoothed load [percent]
    bStageUpPending  : BOOL;                       // 加机延迟计时中 / Stage-up delay running
    bStageDownPending : BOOL;                      // 减机延迟计时中 / Stage-down delay running
    bNoAvailable     : BOOL;                       // 无可用机组标志 / No available unit flag
    bLowSupplyProtect : BOOL;                      // 供水低温保护生效 / Supply low-temperature protection active
    eErr             : UDINT;                      // 错误码，0 = 无错，码位 16#0005_040C 起信息级、16#0005_0354 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError           : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid           : BOOL;                       // 命令输出可用标志，失能/故障闸显式 FALSE / Command usable flag, explicit FALSE on disable/fault gates
    eState           : E_DL_ChillerGroupState;     // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset          : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbTonUp          : TON;                        // 加机延迟定时器实例 / Stage-up delay timer
    fbTonDown        : TON;                        // 减机延迟定时器实例 / Stage-down delay timer
    fbDuty           : FB_DL_DutyStandbyRotation;  // 主备轮值调度组合实例（DL_Base，契约见手册）/ Duty rotation composed instance
    abUnitReady      : ARRAY[0..7] OF BOOL;        // 轮值件就绪入参（0~5 机组，6~7 空槽）/ Ready input for the duty block
    abUnitRunning    : ARRAY[0..7] OF BOOL;        // 轮值件运行入参（0~5 机组，6~7 空槽）/ Running input for the duty block
    abUnitFault      : ARRAY[0..7] OF BOOL;        // 轮值件故障入参（0~5 机组，6~7 空槽）/ Fault input for the duty block
    abStartCmdDuty   : ARRAY[0..7] OF BOOL;        // 轮值件启停命令暂存（0~5 有效）[—] / Duty start commands staged
    nLeadStage       : INT;                        // 轮值件领机号暂存 [号] / Lead unit staged from the duty block
    bDutyFault       : BOOL;                       // 轮值件故障标志暂存 / Duty fault flag staged
    nDemand          : INT;                        // 需求运行台数（本拍生效值，下一拍送轮值件）[台] / Demand, effective next scan
    nUsable          : INT;                        // 可用机组数 [台] / Usable unit count
    nLoop            : INT;                        // 循环索引 [—] / Loop index
    uGateCode        : UDINT;                      // 机构闸故障码暂存 / Gate fault code staging
    fDtSec           : LREAL;                      // 扫描间隔换算成秒 [s] / Scan interval in seconds [s]
    fAlpha           : LREAL;                      // 负荷率一阶滤波系数 [—] / First-order filter coefficient
    fDenomSec        : LREAL;                      // 滤波系数分母 [s] / Filter denominator [s]
    bNonFin          : BOOL;                       // 非有限判定中间标志 / Non-finite detection intermediate flag
    bNeedUp          : BOOL;                       // 加机需求（瞬时）/ Stage-up need, instantaneous
    bNeedDown        : BOOL;                       // 减机需求（瞬时）/ Stage-down need, instantaneous
    bRearmUp         : BOOL;                       // 加机定时器重装脉冲 / Stage-up timer re-arm pulse
    bRearmDown       : BOOL;                       // 减机定时器重装脉冲 / Stage-down timer re-arm pulse
    bLowSupply       : BOOL;                       // 供水低温判据（瞬时）/ Low supply predicate
    bFirstScan       : BOOL := TRUE;               // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_CSM_CODE_INFO_1 : UDINT := 16#0005_040C;    // 信息级槽 1（加减机延迟计时中） / info slot 1
    DL_CSM_CODE_INFO_2 : UDINT := 16#0005_040D;    // 信息级槽 2（供水低温保护强制减机） / info slot 2
    DL_CSM_CODE_FLT_1  : UDINT := 16#0005_0354;    // 故障级槽 1（无可用机组） / fault slot 1
    DL_CSM_CODE_FLT_2  : UDINT := 16#0005_0355;    // 故障级槽 2（负荷/台数组态非法） / fault slot 2
    DL_CSM_CODE_FLT_3  : UDINT := 16#0005_0356;    // 故障级槽 3（非有限/非法状态兜底） / fault slot 3
    DL_CSM_UNITS       : INT := 6;                 // 本件机组数，必须等于数组维度 [台] / Unit count, must match the arrays
    DL_CSM_DUTY_UNITS  : INT := 8;                 // 轮值件槽位数 [台] / Slot count of the duty block
    DL_CSM_DEMAND_MIN  : INT := 0;                 // 需求台数下限 [台] / Demand floor [pcs]
    DL_CSM_DEMAND_MAX  : INT := 6;                 // 需求台数上限 [台] / Demand ceiling [pcs]
    DL_CSM_IDX_NONE    : INT := -1;                // 无效机组号哨兵 [号] / Invalid unit sentinel
    DL_CSM_TAU_S       : LREAL := 60.0;            // 负荷率滤波时间常数 [s] / Load filter time constant [s]
    DL_CSM_PCT_MIN     : LREAL := 0.0;             // 百分数下限 [百分数] / Percent floor
    DL_CSM_PCT_MAX     : LREAL := 100.0;           // 百分数上限 [百分数] / Percent ceiling
    DL_CSM_DT_MIN_MS   : UDINT := 1;               // 扫描间隔下限 [ms]，防除零 / Scan interval floor [ms]
    DL_CSM_MS_PER_S    : LREAL := 1000.0;          // 毫秒转秒系数 [ms/s] / Milliseconds per second
    DL_CSM_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_CSM_ONE         : LREAL := 1.0;             // 单位常量，滤波分子补项 [—] / Unity constant
    DL_CSM_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_CSM_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿、两个延迟定时器与轮值件实例在任意分支之外
 *       周期调用恰好一次。轮值件按上一拍需求台数调度（单拍滞后对分钟级延迟无影响），
 *       保证使能/故障/各分支下轮值记账与最短时长保护永不断流
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbTonUp(IN := bNeedUp AND (NOT bRearmUp), PT := tStageUpDelay);      // 加机延迟计时（重装拍强制复位）/ stage-up delay
fbTonDown(IN := bNeedDown AND (NOT bRearmDown), PT := tStageDownDelay);   // 减机延迟计时（重装拍强制复位）/ stage-down delay
IF bRearmUp THEN
    bRearmUp := FALSE;                             // 加机重装脉冲单拍自清 / re-arm pulse self-cleared
END_IF
IF bRearmDown THEN
    bRearmDown := FALSE;                           // 减机重装脉冲单拍自清 / re-arm pulse self-cleared
END_IF
FOR nLoop := 0 TO DL_CSM_DUTY_UNITS - 1 DO
    IF nLoop < DL_CSM_UNITS THEN
        abUnitReady[nLoop] := abChillerReady[nLoop];      // 0~5 槽接本件机组 / slots 0..5 map to the chillers
        abUnitRunning[nLoop] := abChillerRunning[nLoop];  // 运行反馈透传 / running feedback passed through
        abUnitFault[nLoop] := abChillerFault[nLoop];      // 故障透传（轮值件跳过）/ fault passed through
    ELSE
        abUnitReady[nLoop] := FALSE;               // 空槽：不就绪 / empty slot: not ready
        abUnitRunning[nLoop] := FALSE;             // 空槽：不运行 / empty slot: not running
        abUnitFault[nLoop] := FALSE;               // 空槽：不报故障（避免污染可用计数）/ empty slot: no fault
    END_IF
END_FOR
fbDuty(abUnitReady := abUnitReady,                 // 机组就绪（上限 8 槽）/ unit ready, 8 slots
       abUnitRunning := abUnitRunning,             // 运行反馈 / running feedback
       abUnitFault := abUnitFault,                 // 机组故障 / unit fault
       nDemand := nDemand,                         // 需求台数（上一拍生效值）[台] / demand of the previous scan
       bEnable := bEnable,                         // 使能透传 / enable forwarded
       uDeltaTimeMs := uDeltaTimeMs,               // 扫描间隔透传 [ms] / scan interval forwarded
       tMinRunTime := tMinRun,                     // 最小运行时长转发（时长逻辑归轮值件，不重复实现）/ min run forwarded
       tMinStopTime := tMinStop,                   // 最小停机时长转发 / min stop forwarded
       tRotateInterval := T#24H,                   // 轮值周期 24 小时（本件不另设引脚）/ rotation interval fixed at 24 h
       bForceRotate := FALSE,                      // 不强制轮值 / no forced rotation
       bReset := fbReset.Q,                        // 复位沿透传（R115：透传复位且只在故障相处置）/ reset edge forwarded
       abStartCmd => abStartCmdDuty,               // 轮值件启停命令暂存 / duty start commands staged
       nLeadUnit => nLeadStage,                    // 领机号暂存 / lead unit staged
       bError => bDutyFault);                      // 轮值件故障标志暂存（参数冲突透传）/ duty fault flag staged

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：调度状态与需求台数回到保守初值
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_ChillerGroupState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    nDemand := DL_CSM_DEMAND_MIN;                  // 需求台数清 0 / demand cleared
    fLoadAvgPct := DL_CSM_ZERO;                    // 负荷率平滑值清 / smoothed load cleared
    bLowSupplyProtect := FALSE;                    // 低温保护标志清 / low-supply flag cleared
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜机构闸（顺序判定，首个命中为准）：非有限 → 0356；组态非法 → 0355；
 *       无可用机组 → 0354。三者在同一个出口里全撤指令，避免多处 RETURN 漏赋值
 *----------------------------------------------------------------------------*)
bNonFin := (fSupplyC <> fSupplyC) OR (ABS(fSupplyC) >= DL_CSM_INF)
        OR (fReturnC <> fReturnC) OR (ABS(fReturnC) >= DL_CSM_INF)
        OR (fLoadPct <> fLoadPct) OR (ABS(fLoadPct) >= DL_CSM_INF)
        OR (fStageUpThrPct <> fStageUpThrPct) OR (ABS(fStageUpThrPct) >= DL_CSM_INF)
        OR (fStageDownThrPct <> fStageDownThrPct) OR (ABS(fStageDownThrPct) >= DL_CSM_INF)
        OR (fSupplyLowC <> fSupplyLowC) OR (ABS(fSupplyLowC) >= DL_CSM_INF);   // 引脚非有限汇总 / pins non-finite
nUsable := 0;                                      // 可用机组计数初值 / usable count seed
FOR nLoop := 0 TO DL_CSM_UNITS - 1 DO
    IF abChillerReady[nLoop] AND (NOT abChillerFault[nLoop]) THEN
        nUsable := nUsable + 1;                    // 就绪且无故障计入可用 [台] / usable unit counted
    END_IF
END_FOR
uGateCode := 16#0000_0000;                         // 机构闸码初值 0 / gate code seed
IF bNonFin THEN
    uGateCode := DL_CSM_CODE_FLT_3;                // 故障级：输入非有限（独立分支显式映射入 0356）/ fault: non-finite input
ELSIF (fStageDownThrPct >= fStageUpThrPct - DL_CSM_TOL)
   OR (fStageUpThrPct > DL_CSM_PCT_MAX + DL_CSM_TOL) OR (fStageUpThrPct < DL_CSM_PCT_MIN - DL_CSM_TOL)
   OR (fStageDownThrPct > DL_CSM_PCT_MAX + DL_CSM_TOL) OR (fStageDownThrPct < DL_CSM_PCT_MIN - DL_CSM_TOL) THEN
    uGateCode := DL_CSM_CODE_FLT_2;                // 故障级：阈值组态非法（减机阈值必须严格小于加机阈值）/ fault: threshold configuration invalid
ELSIF (nUsable < DL_CSM_DEMAND_MIN + 1) AND bEnable THEN
    uGateCode := DL_CSM_CODE_FLT_1;                // 故障级：无可用机组（工艺停机级）/ fault: no available unit, process stop level
END_IF
IF uGateCode <> 16#0000_0000 THEN
    eState := E_DL_ChillerGroupState.eFault;       // 进故障相 / enter fault state
    eErr   := uGateCode;                           // 落定机构闸码 / settle the gate code
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 命令不可用 / commands unusable
    bNoAvailable := (uGateCode = DL_CSM_CODE_FLT_1);   // 无可用机组标志只在 0354 置位 / raised only on 0354
    bStageUpPending := FALSE;                      // 加机延迟标志撤 / stage-up pending withdrawn
    bStageDownPending := FALSE;                    // 减机延迟标志撤 / stage-down pending withdrawn
    FOR nLoop := 0 TO DL_CSM_UNITS - 1 DO
        abStartCmd[nLoop] := FALSE;                // 全撤启动命令安全侧 / every start command dropped
    END_FOR
    nRunningCmd := 0;                              // 指令台数清 / commanded count cleared
    nLeadChiller := DL_CSM_IDX_NONE;               // 领机号清 / lead cleared
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜负荷率一阶平滑：alpha = Δt / (tau + Δt)，时间常数 60 s。
 *       用注入间隔而非固定拍数，换任务周期不用改参数（跨平台可移植）
 *----------------------------------------------------------------------------*)
IF uDeltaTimeMs < DL_CSM_DT_MIN_MS THEN
    fDtSec := UDINT_TO_LREAL(DL_CSM_DT_MIN_MS) / DL_CSM_MS_PER_S;   // 间隔过小按下限 [s] / floored interval
ELSE
    fDtSec := UDINT_TO_LREAL(uDeltaTimeMs) / DL_CSM_MS_PER_S;       // 间隔原值 [s] / interval as-is
END_IF
fDenomSec := DL_CSM_TAU_S + fDtSec;                // 滤波分母 [s] / filter denominator [s]
IF fDenomSec > DL_CSM_TOL THEN
    fAlpha := fDtSec / fDenomSec;                  // 滤波系数（除子已判非零）[—] / filter coefficient
ELSE
    fAlpha := DL_CSM_ONE;                          // 分母异常：直通本拍值（不引入伪滤波）/ degenerate case passes through
END_IF
IF bFirstScan THEN
    fLoadAvgPct := fLoadPct;                       // 首拍直接取实测，避免从 0 爬升 / first scan takes the measurement
    bFirstScan := FALSE;                           // 首拍标志清除 / first-scan flag cleared
ELSE
    fLoadAvgPct := fLoadAvgPct + (fLoadPct - fLoadAvgPct) * fAlpha;   // 一阶平滑 [百分数] / first-order smoothing
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜加/减机需求谓词与延迟（双延迟防抖动）：需求台数不超过可用台数；
 *       一次延迟周期只动一台，动作后强制重装定时器（负荷仍越限则再计一个周期）
 *----------------------------------------------------------------------------*)
bNeedUp := (fLoadAvgPct > fStageUpThrPct) AND (nDemand < nUsable);     // 加机需求：负荷高且还有可用机组 / stage-up need
bNeedDown := (fLoadAvgPct < fStageDownThrPct) AND (nDemand > DL_CSM_DEMAND_MIN);   // 减机需求：负荷低且还有机组在指令运行 / stage-down need
bStageUpPending := bNeedUp AND (NOT fbTonUp.Q);     // 加机延迟计时中 / stage-up delay running
bStageDownPending := bNeedDown AND (NOT fbTonDown.Q);   // 减机延迟计时中 / stage-down delay running
IF fbTonUp.Q THEN
    nDemand := nDemand + 1;                        // 加一台 [台] / stage up by one
    bRearmUp := TRUE;                              // 定时器重装，负荷仍高则再计一个周期 / re-arm for the next cycle
END_IF
IF fbTonDown.Q THEN
    nDemand := nDemand - 1;                        // 减一台 [台] / stage down by one
    bRearmDown := TRUE;                            // 定时器重装 / re-arm
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜供水低温保护（防冻管）：低于门限强制再减一台，信息 040D。
 *       信息级不锁故障，但动作是强制的（安全侧：宁可欠冷，不可冻管）
 *----------------------------------------------------------------------------*)
bLowSupply := (fSupplyC < fSupplyLowC);            // 低温判据 [摄氏度] / low-supply predicate
bLowSupplyProtect := bLowSupply;                   // 保护标志出口 / protection flag outlet
IF bLowSupply AND (nDemand > DL_CSM_DEMAND_MIN) THEN
    nDemand := nDemand - 1;                        // 强制减一台 [台] / forced stage-down by one
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜需求台数域钳位（0~6 且不超可用台数）：域外一律钳，不新占码位
 *----------------------------------------------------------------------------*)
IF nDemand < DL_CSM_DEMAND_MIN THEN
    nDemand := DL_CSM_DEMAND_MIN;                  // 下限钳位 / clipped to the floor
END_IF
IF nDemand > DL_CSM_DEMAND_MAX THEN
    nDemand := DL_CSM_DEMAND_MAX;                  // 上限钳位 / clipped to the ceiling
END_IF
IF nDemand > nUsable THEN
    nDemand := nUsable;                            // 不超过可用台数（故障切备后的自然收敛）/ clamped to the usable count
END_IF
IF bEnable AND (nDemand < DL_CSM_DEMAND_MIN + 1) THEN
    nDemand := DL_CSM_DEMAND_MIN + 1;              // 使能保底一台领机（否则 10 分钟无冷才起动，工艺不可接受）/ at least one chiller when enabled
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜轮值件故障透传（R115）：只在故障相处置，下一步由 CASE 的 eFault 分支承接
 *----------------------------------------------------------------------------*)
IF bDutyFault THEN
    eState := E_DL_ChillerGroupState.eFault;       // 轮值件参数冲突：进故障相 / duty parameter conflict enters fault
    eErr   := DL_CSM_CODE_FLT_2;                   // 复用组态非法槽（台数/参数冲突同一出口，不升格不加码）/ reuses the configuration slot
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 命令不可用 / commands unusable
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜状态机：CASE 含 ELSE 兜底（非法状态 → 0356 + 全撤指令）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_ChillerGroupState.eIdle:
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        bNoAvailable := FALSE;                     // 无可用标志撤 / no-available flag withdrawn
        bLowSupplyProtect := FALSE;                // 低温保护标志撤 / low-supply flag withdrawn
        bStageUpPending := FALSE;                  // 加机延迟标志撤 / stage-up pending withdrawn
        bStageDownPending := FALSE;                // 减机延迟标志撤 / stage-down pending withdrawn
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_ChillerGroupState.eRunning;   // 使能进稳态调度 / enable enters steady scheduling
        END_IF

    E_DL_ChillerGroupState.eRunning:
        bValid := TRUE;                            // 命令可用 / commands usable
        bError := FALSE;                           // 稳态无故障 / no fault in the steady state
        eErr := 16#0000_0000;                      // 稳态先清码 / clear the code first
        IF bLowSupplyProtect THEN
            eErr := DL_CSM_CODE_INFO_2;            // 信息级：供水低温保护强制减机（优先）/ info: low-supply protection outranks the delay hint
            eState := E_DL_ChillerGroupState.eLowSupply;   // 转低温保护相 / enter the protection state
        ELSIF bStageUpPending THEN
            eErr := DL_CSM_CODE_INFO_1;            // 信息级：加机延迟计时中 / info: stage-up delay running
            eState := E_DL_ChillerGroupState.eStageUp;     // 转加机延迟相 / enter the stage-up state
        ELSIF bStageDownPending THEN
            eErr := DL_CSM_CODE_INFO_1;            // 信息级：减机延迟计时中 / info: stage-down delay running
            eState := E_DL_ChillerGroupState.eStageDown;   // 转减机延迟相 / enter the stage-down state
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_ChillerGroupState.eIdle;    // 失能回待机 / disable returns to idle
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        END_IF

    E_DL_ChillerGroupState.eStageUp:
        bValid := TRUE;                            // 命令可用（延迟期内照常调度）/ commands usable during the delay
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        eErr := DL_CSM_CODE_INFO_1;                // 信息级：加机延迟计时中 / info: stage-up delay running
        IF NOT bEnable THEN
            eState := E_DL_ChillerGroupState.eIdle;    // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF bLowSupplyProtect THEN
            eState := E_DL_ChillerGroupState.eLowSupply;   // 低温保护优先（退出条件二）/ protection outranks, second exit
        ELSIF (NOT bNeedUp) THEN
            eState := E_DL_ChillerGroupState.eRunning;     // 负荷回落回稳态（退出条件三）/ load fell back, third exit
        END_IF

    E_DL_ChillerGroupState.eStageDown:
        bValid := TRUE;                            // 命令可用 / commands usable
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        eErr := DL_CSM_CODE_INFO_1;                // 信息级：减机延迟计时中 / info: stage-down delay running
        IF NOT bEnable THEN
            eState := E_DL_ChillerGroupState.eIdle;    // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF bLowSupplyProtect THEN
            eState := E_DL_ChillerGroupState.eLowSupply;   // 低温保护优先（退出条件二）/ protection outranks, second exit
        ELSIF (NOT bNeedDown) THEN
            eState := E_DL_ChillerGroupState.eRunning;     // 负荷回升回稳态（退出条件三）/ load recovered, third exit
        END_IF

    E_DL_ChillerGroupState.eLowSupply:
        bValid := TRUE;                            // 命令可用（保护动作已强制减机）/ commands usable after the forced stage-down
        bError := FALSE;                           // 信息级不锁故障 / info never latches a fault
        eErr := DL_CSM_CODE_INFO_2;                // 信息级：供水低温保护强制减机 / info: forced stage-down on low supply
        IF NOT bEnable THEN
            eState := E_DL_ChillerGroupState.eIdle;    // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF (NOT bLowSupplyProtect) THEN
            eState := E_DL_ChillerGroupState.eRunning; // 供水温度回升回稳态（退出条件二）/ supply recovered, second exit
        END_IF

    E_DL_ChillerGroupState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bStageUpPending := FALSE;                  // 加机延迟标志撤 / stage-up pending withdrawn
        bStageDownPending := FALSE;                // 减机延迟标志撤 / stage-down pending withdrawn
        IF eErr = 16#0000_0000 THEN
            eErr := DL_CSM_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bEnable AND (NOT bDutyFault) AND (nUsable >= DL_CSM_DEMAND_MIN + 1)
           AND (fStageDownThrPct < fStageUpThrPct - DL_CSM_TOL) THEN
            eState := E_DL_ChillerGroupState.eIdle;    // 前置条件全部恢复才回待机（退出条件 ≥2）/ recover only when every precondition is back
        END_IF

    ELSE
        eState := E_DL_ChillerGroupState.eFault;    // 非法状态兜底 / illegal-state fallback
        eErr := DL_CSM_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 命令不可用 / commands unusable
        bStageUpPending := FALSE;                  // 加机延迟标志撤 / stage-up pending withdrawn
        bStageDownPending := FALSE;                // 减机延迟标志撤 / stage-down pending withdrawn

END_CASE

(*------------------------------------------------------------------------------
 * 段 10｜出口装配：轮值件命令落到 0~5 号池、领机号映射、指令台数统计；
 *        失能/故障一律全撤（安全值而非上次值，红线 6）
 *----------------------------------------------------------------------------*)
nRunningCmd := 0;                                  // 指令台数从零重数 / commanded count recounted
FOR nLoop := 0 TO DL_CSM_UNITS - 1 DO
    IF bEnable AND bValid THEN
        abStartCmd[nLoop] := abStartCmdDuty[nLoop];     // 正常调度：透传轮值件命令 / pass the duty command through
    ELSE
        abStartCmd[nLoop] := FALSE;                     // 失能/故障：全撤安全侧 / drop everything, safe side
    END_IF
    IF abStartCmd[nLoop] THEN
        nRunningCmd := nRunningCmd + 1;                 // 指令台数累加 [台] / commanded count increments
    END_IF
END_FOR
IF (nLeadStage >= 0) AND (nLeadStage < DL_CSM_UNITS) AND bEnable AND bValid THEN
    nLeadChiller := nLeadStage;                    // 领机号映射（空槽不冒充）/ lead mapped, empty slots never pose as a lead
ELSE
    nLeadChiller := DL_CSM_IDX_NONE;               // 无领机 / no lead chiller
END_IF
END_FUNCTION_BLOCK
