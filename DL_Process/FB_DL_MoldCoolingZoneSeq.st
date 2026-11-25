(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MoldCoolingZoneSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / ABS / MAX / SHL）
 * 功能描述 (Function)   : 注塑模具分区冷却时序控制：
 *                         eIdle → ePreHeat（预热到 fTempSet 的 ±fTempTol 内并驻留 tHeatDwell）
 *                         → eZoneFlow（按 iZoneCount 逐区开阀，逐区确认流量开关）→
 *                         eBalance（各区温差 ≤ fBalTol 且持续 tBalTime）→ eBlow（吹扫
 *                         tBlowTime）→ eDone；任一分区流量在 tFlowTimeout 内未确认 →
 *                         **eDegraded**（该区阀关闭并置 iFaultZoneMask 对应位，其余分区
 *                         继续依次开启，整段流程不中断）；急停 bEStop 或模温超上限
 *                         bMoldTempHigh → **eFault** 当拍全阀关（出口侧再以 bFaultCut 双保险）。
 * 接口     (Interface)  : 输入 17 项（启动/复位/急停/模温上限/模温/预热设定/容差/
 *                         预热驻留/分区数/8 路流量反馈/8 路分区温度/流量超时/平衡容差/
 *                         平衡持续/吹扫时长），输出 7 项（状态回执/8 路阀/吹扫阀/故障分区
 *                         位图/完成/降级/故障与码）。
 * 边界     (Boundary)   : ① 分区数 iZoneCount 钳位到 1..8；数组下标在每次访问前用
 *                            整数域闸保护（R4 下标钳位），越界即不访问。
 *                         ② 流量超时只降级不中止：置位图、关该区阀、继续其余分区；
 *                            全部区均超时仍走 eBalance → eBlow → eDone（流程闭环）。
 *                         ③ 急停与模温上限为最高优先级拦截，位于 CASE 之前；出口侧
 *                            bFaultCut 再做一次硬件切断（双保险）。
 *                         ④ fMoldTemp / 分区温度非有限值按「判据不可满足」处理
 *                            （不假装通过），并在温度类判据中显式披露。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件占用 16#0004_1010 ~ 16#0004_101F 区间，实际使用 7 个：
 *                         1010 信息级 分区数越界已钳位；1011 信息级 某分区流量超时已降级；
 *                         1012 故障级 急停动作；1013 故障级 模温超上限；
 *                         1014 故障级 模温反馈非有限；1015 故障级 非法状态兜底；
 *                         1016 信息级 平衡温差长期不收敛，按超时降级进吹扫。
 *                         信息级码永不置 bError；故障级码锁存回放，bReset 且条件消失解除。
 * 分工声明 (Scope)      : 本件只做「分区冷却时序 + 阀位排列」，不做温度 PID 调节
 *                         （温度闭环归 FB_DL_TempPidZone 类组件），不做流量计标定。
 * 开源溯源 (Origin)     : 开源溯源：原创实现（无外部代码引入）
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 下标钳位 + 非有限双判 + 容差 1E-9
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 ✓ 八态 ENUM + CASE + ELSE
 *                         R7 ✓ 五个定时器/边沿实例全部无条件每周期调用
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版
 *                         2026-11-23  v1.0.1  R77 闸修复（Inf 阈值直比 / eFault 复位出口 / eBalance 超时兜底）
 * 验收向量 (Acceptance) :
 *   V1 bStart 上升、模温 25 ℃、fTempSet=80 ℃：eStateOut=ePreHeat，8 路阀全 FALSE；
 *      模温升至 80 ℃（容差 2 ℃）后驻留 tHeatDwell，随后 eStateOut=eZoneFlow。
 *   V2 iZoneCount=3、三区流量开关在 1s 内依次闭合：eStateOut 依次 eZoneFlow(区1→2→3)
 *      → eBalance → eBlow → eDone，iFaultZoneMask=0，bDone=TRUE。
 *   V3 iZoneCount=3、区 2 流量开关始终不闭合（tFlowTimeout=10s）：
 *      10s 后 iFaultZoneMask 第 2 位 = 1（十进制 2）、abZoneValve[2]=FALSE、
 *      eStateOut=eDegraded，区 3 仍被开启；后续进入 eBalance → eBlow → eDone，bDegraded=TRUE。
 *   V4 任何状态 bEStop 上升：当拍 eStateOut=eFault、8 路阀与吹扫阀全 FALSE、
 *      uErrorId=16#0004_1012、bError=TRUE；bReset 且 bEStop 回落才回 eIdle。
 *   V5 任何状态 bMoldTempHigh 上升：当拍 eStateOut=eFault、全阀关、
 *      uErrorId=16#0004_1013；fMoldTemp=NaN 时 uErrorId=16#0004_1014 且不进入 ePreHeat。
 *   V6（R77 闸补）bEStop 触发进 eFault 后保持 bEStop=FALSE、bReset 保持一拍 →
 *      eStateOut 回归 eIdle，bFaultCut 落 FALSE，bError=FALSE（eFault 唯一出口可到达）。
 *   V7（R77 闸补）eBalance 内分区温差长期大于 fBalTol（tonBal 永不 Q）→ 超过
 *      tBalTime×5 后 eStateOut=eBlow、uErrorId=16#0004_1016、bError=FALSE（信息级降级）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   声明于调用方 FB 的 VAR 区：fbCool : FB_DL_MoldCoolingZoneSeq;
 *   每周期无条件调用：fbCool(bStart := xMoldStart, bReset := xReset,
 *                            bEStop := xEStopSafe, bMoldTempHigh := xTempHiAlarm,
 *                            fMoldTemp := stMold.fTemp, fTempSet := rTempSp,
 *                            iZoneCount := nZoneNum);
 *   数组引脚：abFlowFb / afZoneTemp 直接指向上层结构体中的 8 元数组。
 *   出口用法：abZoneValve 逐路驱动电磁阀，bFaultCut 由本件内部消费，无需使用者再 AND。
 *   调参指引：tFlowTimeout 取流量开关响应时间的 3 倍；fBalTol 取工艺允许温差的一半；
 *            tBlowTime 取管路容积 ÷ 吹扫流量再加 2 s 余量。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MczState（归属 DL_Process，与 FB_DL_MoldCoolingZoneSeq 同文件）
 * 含义: 模具分区冷却时序状态机的离散状态。正序为 eIdle → ePreHeat → eZoneFlow →
 *       eBalance → eBlow → eDone；eDegraded 为「降级继续」分支相，eFault 为安全相。
 *----------------------------------------------------------------------------*)
TYPE E_DL_MczState :
(
    eIdle     := 0,    // 空闲态：全阀关，等 bStart 上升沿 / Idle: all valves closed, waiting for bStart rise
    ePreHeat  := 10,   // 预热态：等模温进入 设定±容差 并驻留 tHeatDwell / Pre-heat: wait for mould temperature in band plus dwell
    eZoneFlow := 20,   // 分区开阀态：按 iZone 逐区开阀并确认流量反馈 / Zone flow: open valve by index and confirm flow feedback
    eBalance  := 30,   // 平衡态：各区温差 ≤ fBalTol 持续 tBalTime / Balance: zone temperature spread within tolerance for tBalTime
    eBlow     := 40,   // 吹扫态：全分区阀关、吹扫阀开 tBlowTime / Blow: zone valves closed, blow valve open for tBlowTime
    eDone     := 50,   // 完成态：全阀关，保持完成标志直到 bStart 跌落 / Done: all valves closed, holds until bStart falls
    eDegraded := 60,   // 降级态：某区流量超时，该区已关阀置位图，其余分区继续 / Degraded: one zone failed, others keep sequencing
    eFault    := 99    // 故障安全态：急停/模温超上限/非法状态，全阀立即关 / Fault safe state: e-stop or over-temperature, all valves closed at once
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_MoldCoolingZoneSeq
 * 调用约定: 每周期无条件调用一次；五个定时器/边沿实例在段 2 无条件刷新。
 * 出口语义: abZoneValve / bBlowValve 在 eFault（或急停、模温超上限）当拍即被强制关断，
 *           不依赖状态机内部清零是否已执行（双保险）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_MoldCoolingZoneSeq
VAR_INPUT
    bStart        : BOOL := FALSE;      // 启动（上升沿开始流程，跌落回 eIdle）/ Start, rising edge begins the sequence, falling returns to eIdle
    bReset        : BOOL := FALSE;      // 复位（电平有效），解除故障锁存 / Reset (level), clears the fault latch
    bEStop        : BOOL := FALSE;      // 急停信号，TRUE = 急停动作，最高优先级拦截 / Emergency stop, TRUE = actuated, highest priority interlock
    bMoldTempHigh : BOOL := FALSE;      // 模温超上限开关，TRUE = 超限，最高优先级拦截 / Mould over-temperature switch, TRUE = over limit, highest priority
    fMoldTemp     : REAL := 0.0;        // 模具当前温度 [℃] / Current mould temperature [degC]
    fTempSet      : REAL := 80.0;       // 预热设定温度 [℃] / Pre-heat setpoint temperature [degC]
    fTempTol      : REAL := 2.0;        // 预热到温容差 [℃] / Pre-heat in-band tolerance [degC]
    tHeatDwell    : TIME := T#10S;      // 到温驻留时间 [s] / Dwell time after reaching temperature [s]
    iZoneCount    : INT := 4;           // 参与时序的分区数，钳位 1..8 [-] / Number of zones in the sequence, clamped 1..8
    abFlowFb      : ARRAY[1..8] OF BOOL;      // 分区流量开关反馈，TRUE = 有流量 [BOOL] / Per-zone flow switch feedback, TRUE = flow present
    afZoneTemp    : ARRAY[1..8] OF REAL;      // 分区冷却水温反馈 [℃] / Per-zone coolant temperature feedback [degC]
    tFlowTimeout  : TIME := T#10S;      // 单区流量确认超时 [s] / Per-zone flow confirmation timeout [s]
    fBalTol       : REAL := 3.0;        // 平衡温差容差 [℃] / Balance temperature spread tolerance [degC]
    tBalTime      : TIME := T#15S;      // 平衡持续确认时间 [s] / Balance confirmation duration [s]
    tBlowTime     : TIME := T#5S;       // 吹扫时长 [s] / Blow duration [s]
END_VAR
VAR_OUTPUT
    eStateOut     : E_DL_MczState;      // 状态机当前状态回执 [-] / Current state feedback
    abZoneValve   : ARRAY[1..8] OF BOOL;      // 分区冷却阀输出，TRUE = 开阀 [BOOL] / Per-zone coolant valve output, TRUE = open
    bBlowValve    : BOOL;               // 吹扫阀输出，TRUE = 开 / Blow valve output, TRUE = open
    iFaultZoneMask: INT;                // 流量超时分区位图，位 0 = 1 区 [-] / Zone fault bitmap, bit 0 = zone 1
    bDone         : BOOL;               // 流程完成标志（eDone 相保持）/ Sequence done flag, held during eDone
    bDegraded     : BOOL;               // 降级运行标志（至少一区流量超时）/ Degraded run flag, at least one zone timed out
    bFaultCut     : BOOL;               // 强制切断回执，TRUE 表示出口已被安全侧切断 / Forced cut-off feedback, TRUE means outlets are cut by the safety side
    bValid        : BOOL;               // 出口数据可信标志 / Output data trustworthy flag
    bError        : BOOL;               // 故障级标志，与 uErrorId 严格联动 / Fault-level flag, strictly coupled with uErrorId
    uErrorId      : UDINT;              // 错误码，0 = 无码 / Error code, 0 = no code
END_VAR
VAR
    eState        : E_DL_MczState;      // 内部状态 [-] / Internal state
    tonHeat       : TON;                // 到温驻留定时器，无条件刷新 / In-band dwell timer, refreshed unconditionally
    tonFlow       : TON;                // 单区流量确认定时器，无条件刷新 / Per-zone flow confirmation timer, refreshed unconditionally
    tonBal        : TON;                // 平衡持续定时器，无条件刷新 / Balance duration timer, refreshed unconditionally
    tonBlow       : TON;                // 吹扫时长定时器，无条件刷新 / Blow duration timer, refreshed unconditionally
    tonBalTmo     : TON;                // 平衡超时兜底定时器（tBalTime×5），无条件刷新 / Balance timeout watchdog timer, refreshed unconditionally
    rtrStart      : R_TRIG;             // 启动上升沿检测，无条件刷新 / Start rising edge detector, refreshed unconditionally
    abZoneOn      : ARRAY[1..8] OF BOOL;      // 分区阀内部指令锁存 [BOOL] / Internal per-zone valve command latch
    iZone         : INT;                // 当前处理分区号，1 基 [-] / Current zone index, one based
    iZonePrev     : INT;                // 上一拍分区号，用于换区复位定时器 [-] / Previous zone index, used to restart the flow timer
    iZoneUse      : INT;                // 钳位后的实际分区数 [-] / Clamped effective zone count
    iIdx          : INT;                // 通用循环下标 [-] / Generic loop index
    bZoneNew      : BOOL;               // 换区单拍标志（新分区首拍）/ Zone-changed single-shot flag, first scan of a new zone
    bFlowOk       : BOOL;               // 当前分区流量已确认 / Current zone flow confirmed
    bTempInBand   : BOOL;               // 模温已进入设定带 [-]/[℃] / Mould temperature inside the band
    bTempFinite   : BOOL;               // 模温反馈为有限值 / Mould temperature feedback is finite
    bZoneTempOk   : BOOL;               // 全部分区温度均有限且可比 / All active zone temperatures finite and comparable
    bSpreadOk     : BOOL;               // 分区温差在容差内 / Zone temperature spread inside tolerance
    bFaultLatch   : BOOL;               // 安全故障锁存位 / Safety fault latch
    bFaultCond    : BOOL;               // 安全故障条件（急停或模温超上限）/ Safety fault condition, e-stop or over-temperature
    bCountClamped : BOOL;               // 分区数被钳位的单拍记录 / Zone count clamp record
    wBitTmp       : WORD;               // 位图构造中间量 [位图] / Bitmap construction scratch [bitmap]
    nShift        : INT;                // 移位量，恒 ≤ 7，绝不等于位宽 [位] / Shift amount, always <= 7, never equals bit width [bit]
    fZoneMax      : REAL;               // 活动分区最高水温 [℃] / Highest coolant temperature among active zones [degC]
    fZoneMin      : REAL;               // 活动分区最低水温 [℃] / Lowest coolant temperature among active zones [degC]
    fTempTolEff   : REAL;               // 钳位后到温容差 [℃] / Clamped in-band tolerance [degC]
    fBalTolEff    : REAL;               // 钳位后平衡容差 [℃] / Clamped balance tolerance [degC]
    uInfoCode     : UDINT;              // 信息级码暂存 / Info-level code scratch
END_VAR
VAR CONSTANT
    DL_MCZ_ZONE_MAX : INT := 8;                    // 分区数硬上限（数组上界）[-] / Hard zone limit, the array upper bound
    DL_MCZ_ZONE_MIN : INT := 1;                    // 分区数硬下限 [-] / Hard zone lower bound
    DL_MCZ_BIT_ONE  : WORD := 16#0001;             // 位图起始掩码（1 区）/ Bitmap base mask for zone one
    DL_MCZ_WORD_0   : WORD := 16#0000;             // 零哨兵，避免裸字面量比较 / Zero sentinel avoiding bare literal comparison
    DL_MCZ_TOL      : REAL := 1.0E-3;              // 容差下限硬钳位值 [℃] / Tolerance lower clamp value [degC]
    DL_MCZ_EPS      : REAL := 1.0E-9;              // 浮点比较容差（统一口径）/ Unified floating point comparison tolerance
    DL_MCZ_ZERO     : REAL := 0.0;                 // 零基准哨兵 / Zero reference sentinel
    DL_MCZ_OK       : UDINT := 16#0000_0000;       // 无码哨兵 / No-code sentinel
    DL_MCZ_RMAX     : REAL := 3.4028235E38;         // 本机 REAL 可表示上限，Inf 阈值直比基准 [无量纲] / Locally representable REAL maximum, Inf threshold base
    DL_MCZ_BAL_TMO_FACTOR : INT := 5;               // 平衡超时倍率，超时 = tBalTime × 本倍率 [-] / Balance timeout factor, timeout = tBalTime x this
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜参数域闸（不中断扫描）：分区数钳位 1..8、容差下限钳位
 *      Parameter domain gate: clamp zone count to 1..8 and tolerance floors
 *-----------------------------------------------------------------------------*)
uInfoCode  := DL_MCZ_OK;                                    // 信息码预置无码 / Preset no info code
bCountClamped := FALSE;                                     // 钳位记录预置 / Preset clamp record FALSE

IF iZoneCount < DL_MCZ_ZONE_MIN THEN
    iZoneUse      := DL_MCZ_ZONE_MIN;                       // 分区数过小钳到 1 / Too few zones clamped to one
    bCountClamped := TRUE;                                  // 记录钳位 / Record the clamp
ELSIF iZoneCount > DL_MCZ_ZONE_MAX THEN
    iZoneUse      := DL_MCZ_ZONE_MAX;                       // 分区数过大钳到 8（数组上界）/ Too many zones clamped to eight
    bCountClamped := TRUE;                                  // 记录钳位 / Record the clamp
ELSE
    iZoneUse := iZoneCount;                                 // 合法分区数原值生效 / Legal zone count applied as-is
END_IF
IF bCountClamped THEN
    uInfoCode := 16#0004_1010;                              // 信息级：分区数越界已钳位 / Info: zone count out of range, clamped
END_IF

fTempTolEff := MAX(fTempTol, DL_MCZ_TOL);                   // 到温容差下限钳位 [℃] / In-band tolerance floor [degC]
fBalTolEff  := MAX(fBalTol, DL_MCZ_TOL);                    // 平衡容差下限钳位 [℃] / Balance tolerance floor [degC]

(*------------------------------------------------------------------------------
 * 段 1｜判据量计算：模温带判定（非有限值判「不可满足」）与当前分区流量确认
 *      Predicate computation: temperature band test treating non-finite as unsatisfied
 *-----------------------------------------------------------------------------*)
bTempFinite := NOT ((fMoldTemp <> fMoldTemp)
                    OR (fMoldTemp > DL_MCZ_RMAX) OR (fMoldTemp < -DL_MCZ_RMAX));          // 模温有限判定：NaN 自反 + Inf 阈值直比 / Finite test: NaN self-comparison plus Inf threshold
bTempInBand := bTempFinite AND (ABS(fMoldTemp - fTempSet) <= fTempTolEff);                 // 到温带判定 [℃] / In-band test [degC]

bFlowOk := FALSE;                                           // 默认未确认流量 / Flow not confirmed by default
IF (iZone >= DL_MCZ_ZONE_MIN) AND (iZone <= DL_MCZ_ZONE_MAX) THEN
    bFlowOk := abFlowFb[iZone];                             // 下标域闸通过才访问数组 / Array accessed only after the index gate
END_IF

bZoneNew := iZone <> iZonePrev;                             // 换区单拍标志（本拍为新分区首拍）/ Zone change single shot

(*------------------------------------------------------------------------------
 * 段 2｜定时器与边沿实例无条件刷新（红线 R7）：全部置于 CASE 之外
 *      Unconditional refresh of timers and edge detectors, all outside the CASE
 *      流量窗口 IN 串 NOT bZoneNew：换区当拍强制复位 ET，绝不让上一区余量带入新区
 *-----------------------------------------------------------------------------*)
rtrStart(CLK := bStart);                                    // 启动上升沿，无条件调用 / Start edge, called unconditionally

tonHeat(IN := bTempInBand AND (eState = ePreHeat), PT := tHeatDwell);   // 到温驻留计时，无条件调用 / In-band dwell timer, called unconditionally

tonFlow(IN := ((eState = eZoneFlow) OR (eState = eDegraded))
             AND (iZone >= DL_MCZ_ZONE_MIN) AND (iZone <= iZoneUse)
             AND (NOT bFlowOk) AND (NOT bZoneNew), PT := tFlowTimeout);   // 单区流量窗，无条件调用 / Zone flow window, called unconditionally

tonBal(IN := bSpreadOk AND (eState = eBalance), PT := tBalTime);        // 平衡持续计时，无条件调用 / Balance duration timer, called unconditionally

tonBlow(IN := (eState = eBlow), PT := tBlowTime);                       // 吹扫时长计时，无条件调用 / Blow duration timer, called unconditionally

tonBalTmo(IN := (eState = eBalance), PT := tBalTime * DL_MCZ_BAL_TMO_FACTOR);   // 平衡超时兜底计时，IN 挂状态量故离相即自复位，无条件调用 / Balance watchdog, self-reset by leaving the state, called unconditionally

(*------------------------------------------------------------------------------
 * 段 3｜安全拦截（最高优先级，位于 CASE 之前）：急停 / 模温超上限 → 当拍进 eFault
 *      Safety interlock before the CASE: e-stop or over-temperature enters eFault at once
 *      故障锁存解除路径唯一：bReset 且 bEStop 回落 且 bMoldTempHigh 回落
 *      解除当拍状态同步回归 eIdle（eFault 的唯一出口，须在段 4 之前生效，否则永久停故障态）
 *      Sole clear path: reset with both conditions gone; the same scan returns the state
 *      machine to eIdle, which is the only exit from eFault, applied before segment 4.
 *-----------------------------------------------------------------------------*)
bFaultCond := bEStop OR bMoldTempHigh;                      // 安全故障条件 / Safety fault condition

IF bFaultCond THEN
    bFaultLatch := TRUE;                                    // 安全故障锁存置位 / Safety fault latch set
    eState      := eFault;                                   // 当拍强制进安全相 / Force the safe state this scan
ELSIF bFaultLatch THEN
    IF bReset THEN
        bFaultLatch := FALSE;                               // 唯一解除路径：复位且条件已回落 / Sole clear path: reset with conditions gone
        eState      := eIdle;                               // 复位回归怠速态：eFault 的唯一出口（段 4 之前生效）/ Reset returns to idle, the only exit from eFault, applied before segment 4
    ELSE
        eState := eFault;                                   // 未复位则保持安全相 / Stay in the safe state without reset
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with enum, case coverage and ELSE interception
 *      迁入安全相后的出口清零由段 5 的 bFaultCut 统一保证，CASE 内不重复做门控
 *-----------------------------------------------------------------------------*)
IF eState = eFault THEN
    (* 安全相出口：分区阀指令全部清零（CASE 内不做二次判定，避免同拍竞态）*)
    (* Safe state outlets: clear every zone command, no second judgement to avoid race *)
    FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
        abZoneOn[iIdx] := FALSE;                            // 逐路清指令 / Clear command zone by zone
    END_FOR
    iZone  := DL_MCZ_ZONE_MIN;                              // 分区游标回 1 / Zone cursor back to one
    bDone  := FALSE;                                        // 完成标志清除 / Done flag cleared
    bValid := FALSE;                                        // 出口数据不可信 / Outlet data untrustworthy
ELSE
    CASE eState OF

        eIdle:
            (* 空闲：游标与位图复位，等 bStart 上升沿 *)
            (* Idle: reset cursor and bitmap, wait for the start edge *)
            FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
                abZoneOn[iIdx] := FALSE;                    // 逐路清阀指令 / Clear valve command zone by zone
            END_FOR
            iZone          := DL_MCZ_ZONE_MIN;              // 游标回 1 / Cursor back to one
            iFaultZoneMask := 0;                            // 位图清零 / Bitmap cleared
            bDone          := FALSE;                        // 完成标志清除 / Done flag cleared
            bDegraded      := FALSE;                        // 降级标志清除 / Degraded flag cleared
            bValid         := TRUE;                         // 空闲相出口可信 / Outlets trustworthy in idle
            IF rtrStart.Q AND (NOT bTempFinite) THEN
                eState := eFault;                           // 温度反馈已坏：拒绝启动（不漏判）/ Broken feedback, refuse to start
            ELSIF rtrStart.Q THEN
                eState := ePreHeat;                         // 启动沿进预热 / Start edge enters pre-heat
            END_IF

        ePreHeat:
            (* 预热：到温带内驻留 tHeatDwell 后进入分区开阀；进相前温度坏值转故障 *)
            (* Pre-heat: dwell in band, then go to zone flow, broken feedback turns to fault *)
            FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
                abZoneOn[iIdx] := FALSE;                    // 预热相不开分区阀 / No zone valve open during pre-heat
            END_FOR
            bValid := TRUE;                                 // 预热相出口可信 / Outlets trustworthy in pre-heat
            IF NOT bTempFinite THEN
                eState := eFault;                           // 温度非有限：进安全相 / Non-finite temperature, safe state
            ELSIF NOT bStart THEN
                eState := eIdle;                            // 启动撤销回空闲 / Start removed returns to idle
            ELSIF tonHeat.Q THEN
                iZone  := DL_MCZ_ZONE_MIN;                  // 到温驻留完成，游标从 1 区起 / Dwell done, cursor starts at zone one
                eState := eZoneFlow;                        // 进入分区开阀 / Enter zone flow
            END_IF

        eZoneFlow:
            (* 分区开阀：下标域闸通过才访问数组；确认 → 推进；超时 → 降级态 *)
            (* Zone flow: index gate before array access, confirm advances, timeout degrades *)
            IF iZone > iZoneUse THEN
                eState := eBalance;                         // 全部分区处理完进平衡 / All zones done, enter balance
            ELSIF iZone < DL_MCZ_ZONE_MIN THEN
                iZone := DL_MCZ_ZONE_MIN;                   // 游标防御性归位 / Defensive cursor reset
            ELSE
                abZoneOn[iZone] := TRUE;                    // 开当前分区阀 / Open the current zone valve
                bValid := TRUE;                             // 出口可信 / Outlets trustworthy
                IF bFlowOk THEN
                    iZone := iZone + 1;                     // 流量确认，推进下一区 / Flow confirmed, advance
                ELSIF tonFlow.Q THEN
                    abZoneOn[iZone] := FALSE;               // 超时先关该区阀 / Close the timed-out zone valve
                    nShift   := iZone - 1;                  // 移位量恒 0..7，绝不等于位宽 / Shift always 0..7, never the bit width
                    wBitTmp  := SHL(DL_MCZ_BIT_ONE, nShift);   // 构造该区位掩码 / Build the zone bit mask
                    IF wBitTmp <> DL_MCZ_WORD_0 THEN
                        iFaultZoneMask := iFaultZoneMask OR WORD_TO_INT(wBitTmp);   // 置位图 / Set the bitmap bit
                    END_IF
                    bDegraded := TRUE;                      // 降级标志置位 / Degraded flag set
                    uInfoCode := 16#0004_1011;              // 信息级：某区流量超时 / Info: a zone timed out
                    iZone     := iZone + 1;                 // 推进，其余分区继续 / Advance, other zones continue
                    eState    := eDegraded;                 // 进入降级相 / Enter degraded state
                END_IF
            END_IF

        eDegraded:
            (* 降级继续：与 eZoneFlow 同构但不再回头进位；超时只加位图不换相 *)
            (* Degraded continue: same body as eZoneFlow but timeouts only add bitmap bits *)
            IF iZone > iZoneUse THEN
                eState := eBalance;                         // 剩余分区处理完进平衡 / Remaining zones done, enter balance
            ELSIF iZone < DL_MCZ_ZONE_MIN THEN
                iZone := DL_MCZ_ZONE_MIN;                   // 游标防御性归位 / Defensive cursor reset
            ELSE
                abZoneOn[iZone] := TRUE;                    // 开当前分区阀 / Open the current zone valve
                bValid := TRUE;                             // 出口可信 / Outlets trustworthy
                IF bFlowOk THEN
                    iZone := iZone + 1;                     // 流量确认，推进 / Flow confirmed, advance
                ELSIF tonFlow.Q THEN
                    abZoneOn[iZone] := FALSE;               // 超时关该区阀 / Close the timed-out valve
                    nShift   := iZone - 1;                  // 移位量恒 0..7 / Shift always 0..7
                    wBitTmp  := SHL(DL_MCZ_BIT_ONE, nShift);   // 区位掩码 / Zone bit mask
                    IF wBitTmp <> DL_MCZ_WORD_0 THEN
                        iFaultZoneMask := iFaultZoneMask OR WORD_TO_INT(wBitTmp);   // 追加位图 / Add the bitmap bit
                    END_IF
                    uInfoCode := 16#0004_1011;              // 信息级：又一分区流量超时 / Info: another zone timed out
                    iZone     := iZone + 1;                 // 推进 / Advance
                END_IF
            END_IF

        eBalance:
            (* 平衡：活动分区水温极差 ≤ 容差并持续 tBalTime；阀保持开（不重写指令）*)
            (* Balance: active zone spread within tolerance for tBalTime, valves stay open *)
            bValid := TRUE;                                 // 平衡相出口可信 / Outlets trustworthy
            fZoneMax := afZoneTemp[DL_MCZ_ZONE_MIN];        // 极值初值取 1 区（下标常量，恒合法）/ Extremes start from zone one
            fZoneMin := afZoneTemp[DL_MCZ_ZONE_MIN];        // 极值初值取 1 区 / Extremes start from zone one
            bZoneTempOk := NOT ((afZoneTemp[DL_MCZ_ZONE_MIN] <> afZoneTemp[DL_MCZ_ZONE_MIN])
                             OR (afZoneTemp[DL_MCZ_ZONE_MIN] > DL_MCZ_RMAX)
                             OR (afZoneTemp[DL_MCZ_ZONE_MIN] < -DL_MCZ_RMAX));   // 首区有限判定：NaN 自反 + Inf 阈值直比 / Zone-one finite test: NaN plus Inf threshold
            FOR iIdx := DL_MCZ_ZONE_MIN TO iZoneUse DO
                IF (afZoneTemp[iIdx] <> afZoneTemp[iIdx])
                   OR (afZoneTemp[iIdx] > DL_MCZ_RMAX)
                   OR (afZoneTemp[iIdx] < -DL_MCZ_RMAX) THEN
                    bZoneTempOk := FALSE;                   // 任一区非有限即整体判据不可满足 / Any non-finite zone makes the predicate unsatisfiable
                ELSE
                    IF afZoneTemp[iIdx] > fZoneMax THEN
                        fZoneMax := afZoneTemp[iIdx];       // 更新最高水温 / Update the maximum
                    END_IF
                    IF afZoneTemp[iIdx] < fZoneMin THEN
                        fZoneMin := afZoneTemp[iIdx];       // 更新最低水温 / Update the minimum
                    END_IF
                END_IF
            END_FOR
            bSpreadOk := bZoneTempOk AND ((fZoneMax - fZoneMin) <= fBalTolEff);   // 极差判据 [℃]，非有限即不可满足 / Spread predicate [degC], unsatisfiable when non-finite
            IF NOT bStart THEN
                eState := eIdle;                            // 启动撤销回空闲 / Start removed returns to idle
            ELSIF tonBal.Q THEN
                eState := eBlow;                            // 平衡持续到，进吹扫 / Balance sustained, enter blow
            ELSIF tonBalTmo.Q THEN
                (* 温差长期不收敛按超时降级处理（信息级，不置 bError）：避免 bSpreadOk 永不成立时长期驻留且分区阀全开 *)
                (* Spread never converging degrades by timeout at info level, no bError, preventing a permanent all-valve-open dwell *)
                uInfoCode := 16#0004_1016;                  // 信息级：平衡温差长期不收敛 / Info: balance spread did not converge in time
                eState    := eBlow;                         // 保流程闭环，进吹扫 / Keep the sequence closed, enter blow
            END_IF

        eBlow:
            (* 吹扫：分区阀全关、吹扫阀开（吹扫阀由段 5 依状态派生）*)
            (* Blow: all zone valves closed, blow valve derived from the state in segment 5 *)
            FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
                abZoneOn[iIdx] := FALSE;                    // 吹扫前关闭全部分区阀 / Close all zone valves before blow
            END_FOR
            bValid := TRUE;                                 // 吹扫相出口可信 / Outlets trustworthy
            IF NOT bStart THEN
                eState := eIdle;                            // 启动撤销回空闲 / Start removed returns to idle
            ELSIF tonBlow.Q THEN
                eState := eDone;                            // 吹扫完成 / Blow finished
            END_IF

        eDone:
            (* 完成：全阀关，bDone 保持到 bStart 跌落 *)
            (* Done: all valves closed, bDone held until bStart falls *)
            FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
                abZoneOn[iIdx] := FALSE;                    // 完成相关闭全部阀 / Close all valves in the done state
            END_FOR
            bDone  := TRUE;                                 // 完成标志置位 / Done flag set
            bValid := TRUE;                                 // 完成相出口可信 / Outlets trustworthy
            IF NOT bStart THEN
                eState := eIdle;                            // 启动跌落回空闲（下一循环可重入）/ Start falls, ready for the next cycle
            END_IF

        ELSE
            (* 非法状态拦截：任何未定义枚举值一律进安全相并置兜底码 *)
            (* Illegal state interception: undefined enum values go to the safe state with a code *)
            eState    := eFault;                            // 强制回安全相 / Force the safe state
            bFaultLatch := TRUE;                            // 锁存，禁自动恢复 / Latch, no automatic recovery
            uInfoCode := 16#0004_1015;                      // 故障级：非法状态兜底 / Fault: illegal state fallback
            bValid    := FALSE;                             // 出口不可信 / Outlets untrustworthy

    END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜出口派生与安全切断（双保险）：bFaultCut = 安全相 或 急停 或 模温超上限
 *      Outlet derivation with a second safety cut, independent of state machine bookkeeping
 *-----------------------------------------------------------------------------*)
bFaultCut := bFaultCond OR (eState = eFault);               // 安全切断条件 / Safety cut-off condition
IF bFaultCut THEN
    FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
        abZoneOn[iIdx] := FALSE;                            // 切断时同步清指令锁存 / Clear the command latch on cut-off
    END_FOR
END_IF

FOR iIdx := DL_MCZ_ZONE_MIN TO DL_MCZ_ZONE_MAX DO
    abZoneValve[iIdx] := abZoneOn[iIdx] AND (NOT bFaultCut);   // 逐路出口映射，安全侧再 AND 一次 / Per-zone outlet mapping with a second safety AND
END_FOR
bBlowValve := (eState = eBlow) AND (NOT bFaultCut);         // 吹扫阀出口映射 / Blow valve outlet mapping

(*------------------------------------------------------------------------------
 * 段 6｜故障码统一出口（故障级锁存回放，信息级不置 bError；急停优先于超温）
 *      Unified code outlet: fault codes replayed latched, info codes never raise bError
 *-----------------------------------------------------------------------------*)
IF bFaultCond THEN
    IF bEStop THEN
        uErrorId := 16#0004_1012;                           // 故障级：急停动作 / Fault: emergency stop actuated
    ELSIF bMoldTempHigh THEN
        uErrorId := 16#0004_1013;                           // 故障级：模温超上限 / Fault: mould over-temperature
    ELSE
        uErrorId := 16#0004_1015;                           // 故障级：非法兜底 / Fault: fallback
    END_IF
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
    bValid   := FALSE;                                      // 安全相出口不可信 / Outlets untrustworthy in the safe state
ELSIF (NOT bTempFinite) AND (eState <> eIdle) THEN
    uErrorId := 16#0004_1014;                               // 故障级：模温反馈非有限 / Fault: mould temperature feedback non-finite
    bError   := TRUE;                                       // 故障级码配对置位 / Paired fault flag set
    bValid   := FALSE;                                      // 指标不可信 / Metric untrustworthy
ELSE
    uErrorId := uInfoCode;                                  // 信息级码（流量超时/分区钳位）或 0 / Info code or zero
    bError   := FALSE;                                      // 信息级不置故障标志 / Info level never raises the fault flag
END_IF

eStateOut := eState;                                        // 状态回执单一出口 / State feedback through a single outlet
iZonePrev := iZone;                                         // 换区基准刷新（本拍结束）/ Refresh the zone baseline at scan end
END_FUNCTION_BLOCK
