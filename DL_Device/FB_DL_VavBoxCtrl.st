//==============================================================================
// 功能块：FB_DL_VavBoxCtrl ｜ 中文名称：压力无关型 VAV 末端风量闭环控制
// 所属子库：DL_Device ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：VAV 末端风量闭环（PI，组合调用 FB_DL_PidController，引脚
//           契约以 MANUAL_DL_Algo.md 为准，不内联不复制）+ 设定先钳入
//           最小/最大风量位 + 风阀开度限幅（输出界）+ 指令-反馈偏差诊
//           断（卡滞/拒动，tFbDelay 内不判防启动瞬态误报）。反馈无效
//           时保持上次开度（R42 家族：禁止塞 0% 或伪值，那会让末端全
//           关）。失能安全侧 = 回最小开度（保最小新风，绝不落到全关）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：风量[m³/h] / 开度[百分数] / 比例增益[百分数每 m³每小时] / 积分时间[s] / 反馈容差[百分数] / 延时[ms]
// 错误码表：16#0003_0194 信息级（风阀反馈无效：保持上次开度，不塞伪
//           值，不置 bError）/ 16#0003_0195 信息级（风量设定域外钳位，
//           不置 bError）/ 16#0003_036F 故障级（风量上下限倒置或开度
//           界倒置或最小风量为负，置 bError；出厂默认值也必须过本闸，
//           R114）/ 16#0003_0370 故障级（浮点输入非有限或 PID 件故障
//           透传，置 bError，开度回最小开度安全侧）/ 16#0003_0371 故
//           障级兜底（状态机落 ELSE 或非法状态，置 bError 并回最小开度）
// 状态机：E_DL_VavState（eIdle=0 / eRun=10 / eFbHold=20 / eFault=99），
//           CASE 含 ELSE 兜底，ELSE 置 0371 并回最小开度（安全侧）
// 边界行为：① fFlowMinM3h 大于 fFlowMaxM3h 或 fOpenMinPct 大于
//           fOpenMaxPct 或 fFlowMinM3h 小于 0 → 故障 036F（默认参数必
//           须过自身组态闸，R114）；② 反馈无效（bDamperFbValid 为假）
//           → 保持上次开度 + 信息 0194（R42 家族：禁止塞 0% 或伪值，
//           那会让末端全关），退出条件两条：反馈恢复（回运行）或失能
//           （回待机）；③ 设定域外钳入 [fFlowMinM3h, fFlowMaxM3h] →
//           信息 0195；④ 浮点输入非有限（NaN 自反判 + Inf 幅值上限
//           判，R79）或 PID 件故障透传（R115，只在故障相处置，信息级
//           不升格）→ 故障 0370，开度回 fOpenMinPct 安全侧；⑤ 失能 →
//           fDamperCmdPct := fOpenMinPct（安全侧保最小新风）+ bValid :=
//           FALSE；⑥ 指令-反馈偏差诊断经 TON 判稳，tFbDelay 内不判
//           bFbMismatch（防启动瞬态误报，R100 同拍起算约束显式化），
//           TON 与 PID 实例无条件周期刷新；⑦ PI 增益口径：风量偏差正
//           （实测低于设定）→ 开大阀（Kp 为正、偏差 = 设定 − 实测）；
//           ⑧ 上电首拍 bValid := FALSE。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.6）
//           v1.0.1 2026-11-17 终审修正一处（对外引脚契约零变更）：非有限闸命中的「安全侧赋值」
//           原为 fDamperCmdPct := fOpenMinPct，而 fOpenMinPct 本身就在本闸的判定集合内——下限脚
//           为 NaN 时等于把 NaN 当安全值写进出口（安全侧自我失效，R84 域端点推演命中）。改为先算
//           可用下限 fFloorPct（脚非有限时回默认常量 DL_VV_OPEN_FLOOR_DEF = 20%）再赋值。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_VavState（归属 DL_Device，与 FB_DL_VavBoxCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VavState :
(
    eIdle   := 0,   // 失能/待机：开度回最小开度，保最小新风 / Idle: damper at minimum, minimum outdoor air kept
    eRun    := 10,  // 闭环运行：PI 调节中，反馈有效 / Run: closed-loop PI, feedback valid
    eFbHold := 20,  // 反馈无效保持：开度保持，等反馈恢复 / Feedback-invalid hold: damper held, awaiting recovery
    eFault  := 99   // 故障兜底态：组态非法/非有限/非法状态，开度回最小 / Fault fallback, damper at minimum
);
END_TYPE
FUNCTION_BLOCK FB_DL_VavBoxCtrl
VAR_INPUT
    fFlowSetM3h   : LREAL;                     // 风量设定 [m³/h]，域外钳入最小/最大风量位 / Airflow setpoint [m3/h], clamped into min/max band
    fFlowMeasM3h  : LREAL;                     // 实测风量 [m³/h] / Measured airflow [m3/h]
    fFlowMinM3h   : LREAL;                     // 最小风量位 [m³/h] / Minimum airflow setpoint [m3/h]
    fFlowMaxM3h   : LREAL;                     // 最大风量位 [m³/h] / Maximum airflow setpoint [m3/h]
    fKpPctPerM3h  : LREAL := 0.02;             // 比例增益 [百分数每 m³每小时] / Proportional gain [percent per m3/h]
    fTiS          : LREAL := 120.0;            // 积分时间 [s]，0 = 纯比例 / Integral time [s], 0 = pure proportional
    fOpenMinPct   : LREAL := 20.0;             // 开度界下限 [百分数]，安全侧 = 此值 / Damper output floor [percent], safe side value
    fOpenMaxPct   : LREAL := 100.0;            // 开度界上限 [百分数] / Damper output ceiling [percent]
    fDamperFbPct  : LREAL;                     // 风阀开度反馈 [百分数] / Damper position feedback [percent]
    bDamperFbValid : BOOL;                     // 开度反馈有效性质量位 / Damper feedback validity quality bit
    fFbTolPct     : LREAL := 10.0;             // 指令-反馈偏差诊断容差 [百分数] / Command-feedback mismatch tolerance [percent]
    tFbDelay      : TIME := T#10S;             // 偏差诊断判稳延时 [ms]，内不判 / Mismatch settle delay [ms], not judged within
    uDeltaTimeMs  : UDINT;                     // 扫描间隔 [ms]，调用方注入，禁用系统时间函数 / Scan interval [ms], caller-injected, no system time calls
    bEnable       : BOOL;                      // 总使能 / Master enable
    bReset        : BOOL;                      // 复位，上升沿清状态与 PID / Reset, rising edge clears state and PID
END_VAR
VAR_OUTPUT
    fDamperCmdPct : LREAL;                     // 风阀开度指令 [百分数]，失能/故障回最小开度 / Damper command [percent], minimum on disable/fault
    bAtMin        : BOOL;                      // 开度指令贴下限 / Command at output floor
    bAtMax        : BOOL;                      // 开度指令贴上限 / Command at output ceiling
    fFlowErrM3h   : LREAL;                     // 风量偏差 [m³/h]，设定减实测 / Airflow error [m3/h], setpoint minus measured
    bFbMismatch   : BOOL;                      // 卡滞/拒动诊断：偏差超容差持续超延时 / Stuck or refused diagnosis: mismatch beyond tolerance over delay
    eErr          : UDINT;                     // 错误码，0 = 无错，码位 16#0003_0194 起信息级、16#0003_036F 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 控制输出可用标志，失能/故障闸显式 FALSE / Control usable flag, explicit FALSE on disable/fault gates
    eState        : E_DL_VavState;             // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset       : R_TRIG;                    // 复位上升沿检测实例 / Reset rising edge detector
    fbPid         : FB_DL_PidController;       // PI 控制器组合实例（DL_Algo，契约见手册）/ PI controller composed instance
    fbMismatchT   : TON;                       // 偏差诊断判稳定时器 / Mismatch diagnosis settle timer
    fSetClamped   : LREAL;                     // 钳位后有效风量设定 [m³/h] / Clamped effective airflow setpoint [m3/h]
    bSetClampAct  : BOOL;                      // 本拍设定被钳位 / Setpoint clamped this scan
    fCmdHeld      : LREAL;                     // 保持开度暂存 [百分数]（反馈无效时跟踪回投）/ Held damper value [percent], track value on feedback invalid
    fFloorPct     : LREAL;                     // 安全侧可用开度下限 [百分数]（下限脚非有限时回默认常量）/ Usable safe-side floor [percent], falls back to the default constant
    bMismatchRaw  : BOOL;                      // 偏差超容差即时判据（供判稳定时器，跨拍）/ Immediate mismatch predicate, feeds the settle timer
    fPidOutReal   : REAL;                      // PID 输出暂存 [百分数]（REAL 精度显式过渡）/ PID output staging in REAL precision
    fPidErrReal   : REAL;                      // PID 偏差暂存 [m³/h]（REAL 精度显式过渡）/ PID error staging in REAL precision
    tPidSample    : TIME;                      // PID 采样周期 [ms]（扫描间隔下限钳位）/ PID sample period, floored scan interval
    ePidErr       : UDINT;                     // PID 件错误码暂存 / PID error code staging
    bPidErr       : BOOL;                      // PID 件故障标志暂存 / PID fault flag staging
    bFirstScan    : BOOL := TRUE;              // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_VAV_CODE_INFO_1 : UDINT := 16#0003_0194;   // 信息级槽 1（反馈无效保持开度） / info slot 1
    DL_VAV_CODE_INFO_2 : UDINT := 16#0003_0195;   // 信息级槽 2（设定域外钳位） / info slot 2
    DL_VAV_CODE_FLT_1  : UDINT := 16#0003_036F;   // 故障级槽 1（风量/开度界倒置） / fault slot 1
    DL_VAV_CODE_FLT_2  : UDINT := 16#0003_0370;   // 故障级槽 2（非有限或 PID 透传） / fault slot 2
    DL_VAV_CODE_FLT_3  : UDINT := 16#0003_0371;   // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_VV_ZERO    : LREAL := 0.0;              // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_VV_TOL     : LREAL := 1.0E-6;           // 浮点比较容差 [—] / Float comparison tolerance
    DL_VV_INF     : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_VV_MS_PER_S : LREAL := 1000.0;          // 秒转毫秒系数 [ms/s] / Second-to-ms factor
    DL_VV_DT_MIN_MS : UDINT := 10;             // 扫描间隔下限 [ms]，低于按此值注入 PID / Scan interval floor [ms], injected to PID
    DL_VV_OPEN_FLOOR_DEF : LREAL := 20.0;      // 安全侧默认开度下限 [百分数]（下限脚非有限时的兜底）/ Default safe-side floor [percent], used when the floor pin is non-finite
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿与偏差判稳定时器在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbMismatchT(IN := bMismatchRaw AND bDamperFbValid,  // 偏差持续才计时，tFbDelay 内不判（R100 显式化）/ times only while mismatching
            PT := tFbDelay);                   // 判稳延时 / settle delay

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState  := E_DL_VavState.eIdle;
    eErr    := 16#0000_0000;                   // 复位清码 / reset clears code
    bError  := FALSE;                          // 复位清故障 / reset clears fault
    bFbMismatch := FALSE;                      // 诊断清 / diagnosis cleared
    bFirstScan := TRUE;                        // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *       命中即开度回最小开度安全侧；但「安全侧取值」本身必须先证明可用——
 *       下限脚非有限时不得把它原样写进出口（那等于把 NaN 当安全值下发）
 *----------------------------------------------------------------------------*)
IF (fOpenMinPct <> fOpenMinPct) OR (ABS(fOpenMinPct) >= DL_VV_INF) THEN
    fFloorPct := DL_VV_OPEN_FLOOR_DEF;         // 下限脚非有限：回默认开度下限 [百分数] / non-finite floor pin falls back to the default
ELSE
    fFloorPct := fOpenMinPct;                  // 下限脚可用：按用户组态 [百分数] / usable floor pin honoured
END_IF
IF (fFlowSetM3h <> fFlowSetM3h) OR (ABS(fFlowSetM3h) >= DL_VV_INF)
   OR (fFlowMeasM3h <> fFlowMeasM3h) OR (ABS(fFlowMeasM3h) >= DL_VV_INF)
   OR (fFlowMinM3h <> fFlowMinM3h) OR (ABS(fFlowMinM3h) >= DL_VV_INF)
   OR (fFlowMaxM3h <> fFlowMaxM3h) OR (ABS(fFlowMaxM3h) >= DL_VV_INF)
   OR (fKpPctPerM3h <> fKpPctPerM3h) OR (ABS(fKpPctPerM3h) >= DL_VV_INF)
   OR (fTiS <> fTiS) OR (ABS(fTiS) >= DL_VV_INF)
   OR (fOpenMinPct <> fOpenMinPct) OR (ABS(fOpenMinPct) >= DL_VV_INF)
   OR (fOpenMaxPct <> fOpenMaxPct) OR (ABS(fOpenMaxPct) >= DL_VV_INF)
   OR (fDamperFbPct <> fDamperFbPct) OR (ABS(fDamperFbPct) >= DL_VV_INF) THEN
    eState        := E_DL_VavState.eFault;
    eErr          := DL_VAV_CODE_FLT_2;            // 故障级：浮点输入非有限 / fault: non-finite float input
    bError        := TRUE;                     // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid        := FALSE;                    // 输出不可用 / outputs unusable
    fDamperCmdPct := fFloorPct;                // 开度回可用下限（下限脚自身非有限时回默认常量，禁把 NaN 出口）/ damper to the usable floor, never a NaN outlet
    bAtMin := TRUE;                            // 贴下限如实外显 / at-floor shown truthfully
    bAtMax := FALSE;                           // 贴上限撤 / at-ceiling withdrawn
    fFlowErrM3h := DL_VV_ZERO;                 // 偏差出口清零 / error output zeroed
    bFbMismatch := FALSE;                      // 故障态不判卡滞 / mismatch not judged in fault
    fbPid(bEnable := FALSE);                   // PID 无条件调用保刷新（使能撤）/ PID called unconditionally, enable off
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（风量界倒置/开度界倒置/最小风量为负，默认值同闸，R114）
 *----------------------------------------------------------------------------*)
IF (fFlowMinM3h > fFlowMaxM3h) OR (fOpenMinPct > fOpenMaxPct) OR (fFlowMinM3h < DL_VV_ZERO) THEN
    eState        := E_DL_VavState.eFault;
    eErr          := DL_VAV_CODE_FLT_1;            // 故障级：风量上下限倒置或开度界倒置 / fault: airflow band or damper band inverted
    bError        := TRUE;                     // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid        := FALSE;                    // 输出不可用 / outputs unusable
    fDamperCmdPct := fOpenMinPct;              // 开度回最小开度（安全侧保最小新风）/ damper to floor, safe side
    bAtMin := TRUE;                            // 贴下限如实外显 / at-floor shown truthfully
    bAtMax := FALSE;                           // 贴上限撤 / at-ceiling withdrawn
    fFlowErrM3h := DL_VV_ZERO;                 // 偏差出口清零 / error output zeroed
    bFbMismatch := FALSE;                      // 故障态不判卡滞 / mismatch not judged in fault
    fbPid(bEnable := FALSE);                   // PID 无条件调用保刷新（使能撤）/ PID called unconditionally, enable off
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜设定钳位（域外钳入 [min, max] → 信息 0195）
 *----------------------------------------------------------------------------*)
fSetClamped := fFlowSetM3h;                    // 有效设定初值 / effective setpoint seed
bSetClampAct := FALSE;                         // 钳位标志逐拍重判 / clamp flag re-judged per scan
IF fSetClamped < fFlowMinM3h THEN
    fSetClamped := fFlowMinM3h;                // 低于下限钳入 / below floor clamped
    bSetClampAct := TRUE;                      // 钳位发生 / clamped
END_IF
IF fSetClamped > fFlowMaxM3h THEN
    fSetClamped := fFlowMaxM3h;                // 高于上限钳入 / above ceiling clamped
    bSetClampAct := TRUE;                      // 钳位发生 / clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜采样周期钳位 + PI 组合调用：每拍无条件执行恰好一次（实例纪律）。
 *       增益口径：PID 偏差 = 设定 − 实测，偏差正 = 需要加大风量 = 开大阀，
 *       故 fKp 取正；积分时间 fTiS = 0 由 PID 内部解释为纯比例。
 *       反馈无效时经 bTrack/fTrackValue 把 PID 输出回投为保持开度
 *       （抗饱和：积分跟踪保持值，恢复无扰）。
 *----------------------------------------------------------------------------*)
IF uDeltaTimeMs < DL_VV_DT_MIN_MS THEN
    tPidSample := UDINT_TO_TIME(DL_VV_DT_MIN_MS);  // 间隔过小按下限注入 / floored interval injected
ELSE
    tPidSample := UDINT_TO_TIME(uDeltaTimeMs);     // 间隔原值注入 / interval injected as-is
END_IF
fbPid(bEnable := bEnable,                      // PID 件每拍无条件调用 / PID called unconditionally per scan
      bManual := FALSE,                        // 纯自动，无手动模式 / auto only, no manual mode
      fSetpoint := LREAL_TO_REAL(fSetClamped),             // 设定 [m³/h] 显式降精度 / setpoint, explicit narrowing
      fActual := LREAL_TO_REAL(fFlowMeasM3h),               // 实测 [m³/h] 显式降精度 / measured, explicit narrowing
      fKp := LREAL_TO_REAL(fKpPctPerM3h),                   // 比例增益显式降精度 / gain, explicit narrowing
      tTi := DINT_TO_TIME(LREAL_TO_DINT(fTiS * DL_VV_MS_PER_S)),  // 积分时间 [ms]，0 = 纯比例 / integral time, 0 = pure P
      tTd := T#0S,                             // 微分关闭 / derivative off
      fDeadband := 0.0,                        // 无控制死区（带宽逻辑在上层）/ no deadband here
      bIncremental := FALSE,                   // 位置式 / positional form
      rOutMin := LREAL_TO_REAL(fOpenMinPct),                // 输出下限 = 开度界下限 / output floor
      rOutMax := LREAL_TO_REAL(fOpenMaxPct),                // 输出上限 = 开度界上限 / output ceiling
      tSampleTime := tPidSample,               // 采样周期（已钳位）/ sample period, floored
      bTrack := (eState = E_DL_VavState.eFbHold),          // 反馈无效保持期回投 / track during feedback hold
      fTrackValue := LREAL_TO_REAL(fCmdHeld),               // 跟踪值 = 保持开度 / track value = held damper
      bReset := fbReset.Q,                     // 复位沿透传 / reset edge passed through
      fOut => fPidOutReal,                     // 开度指令暂存 [百分数] / command staging
      fErr => fPidErrReal,                     // 风量偏差暂存 [m³/h] / error staging
      uErrorId => ePidErr,                     // PID 错误码暂存 / PID error code staging
      bError => bPidErr);                      // PID 故障标志暂存 / PID fault flag staging
fDamperCmdPct := fPidOutReal;                  // 开度指令出口升精度回 LREAL / command output widened back to LREAL
fFlowErrM3h := fPidErrReal;                    // 风量偏差出口升精度回 LREAL / error output widened back to LREAL

(*------------------------------------------------------------------------------
 * 段 7｜状态机：CASE 含 ELSE 兜底（非法状态 → 0371 + 回最小开度，安全侧）
 *----------------------------------------------------------------------------*)
fCmdHeld := fDamperCmdPct;                     // 保持开度暂存为本拍指令（供下一拍跟踪回投）/ held value = this scan command, for next-scan tracking
bAtMin := ABS(fDamperCmdPct - fOpenMinPct) < DL_VV_TOL;   // 贴下限判定（容差比较，禁浮点判等）/ at-floor with tolerance
bAtMax := ABS(fDamperCmdPct - fOpenMaxPct) < DL_VV_TOL;   // 贴上限判定（容差比较）/ at-ceiling with tolerance
bMismatchRaw := bDamperFbValid AND (ABS(fDamperFbPct - fDamperCmdPct) > fFbTolPct);  // 偏差即时判据（供下拍判稳定时器）/ immediate mismatch predicate

CASE eState OF

    E_DL_VavState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        fDamperCmdPct := fOpenMinPct;          // 失能安全侧：回最小开度保最小新风 / safe side: floor, minimum outdoor air
        bAtMin := TRUE;                        // 贴下限如实外显 / at-floor shown truthfully
        bAtMax := FALSE;                       // 贴上限撤 / at-ceiling withdrawn
        bFbMismatch := FALSE;                  // 失能不判卡滞 / mismatch not judged in idle
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_VavState.eRun;      // 使能进闭环运行 / enable enters run
            IF bFirstScan OR (NOT bDamperFbValid) THEN
                eState := E_DL_VavState.eFbHold;       // 反馈无效先进保持态 / invalid feedback enters hold first
            END_IF
            bFirstScan := FALSE;               // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_VavState.eRun:
        bValid := TRUE;                        // 运行态输出可用 / usable in run
        eErr := 16#0000_0000;                  // 运行态先清码 / run clears code first
        bError := FALSE;                       // 运行态先清故障 / run clears fault first
        IF bSetClampAct THEN
            eErr := DL_VAV_CODE_INFO_2;        // 信息级：设定域外钳位 / info: setpoint clamped
        END_IF
        IF bPidErr THEN
            eState := E_DL_VavState.eFault;    // PID 件故障透传（R115，故障相处置）/ PID fault passed through in fault phase
            eErr := DL_VAV_CODE_FLT_2;         // 复用非有限故障槽（PID 件故障 = 控制数据不可信，不升格不加码）/ reuses fault slot, no escalation
            bError := TRUE;                    // 故障级必置 bError / fault-class pairs with bError
            fDamperCmdPct := fOpenMinPct;      // 开度回最小开度（安全侧）/ damper to floor, safe side
            bValid := FALSE;                   // 故障闸显式不可用 / explicit FALSE on fault gate
        ELSIF NOT bEnable THEN
            eState := E_DL_VavState.eIdle;     // 失能回待机 / disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSIF NOT bDamperFbValid THEN
            eState := E_DL_VavState.eFbHold;   // 反馈无效进保持态 / invalid feedback enters hold
        END_IF

    E_DL_VavState.eFbHold:
        bValid := TRUE;                        // 保持态指令输出仍可用（保持值）/ usable in hold (held command)
        eErr := DL_VAV_CODE_INFO_1;            // 信息级：反馈无效保持上次开度，不塞伪值 / info: feedback invalid, hold last command
        bError := FALSE;                       // 信息级不置 bError / info never raises bError
        IF bSetClampAct THEN
            eErr := DL_VAV_CODE_INFO_2;        // 设定钳位提示并列，后写覆盖 / setpoint clamp hint, later write wins
        END_IF
        IF bPidErr THEN
            eState := E_DL_VavState.eFault;    // PID 件故障透传（R115，故障相处置）/ PID fault passed through in fault phase
            eErr := DL_VAV_CODE_FLT_2;
            bError := TRUE;
            fDamperCmdPct := fOpenMinPct;      // 开度回最小开度（安全侧）/ damper to floor, safe side
            bValid := FALSE;                   // 故障闸显式不可用 / explicit FALSE on fault gate
        ELSIF NOT bEnable THEN
            eState := E_DL_VavState.eIdle;     // 失能回待机 / disable returns to idle
            bValid := FALSE;
        ELSIF bDamperFbValid THEN
            eState := E_DL_VavState.eRun;      // 反馈恢复回运行态（前置消失退出）/ feedback recovered, precondition cleared
        END_IF

    E_DL_VavState.eFault:
        bValid := FALSE;                       // 故障闸显式不可用 / explicit FALSE on fault gate
        fDamperCmdPct := fOpenMinPct;          // 开度回最小开度（安全侧保最小新风）/ damper to floor, safe side
        bAtMin := TRUE;                        // 贴下限如实外显 / at-floor shown truthfully
        bAtMax := FALSE;                       // 贴上限撤 / at-ceiling withdrawn
        bFbMismatch := FALSE;                  // 故障态不判卡滞 / mismatch not judged in fault
        eErr := DL_VAV_CODE_FLT_2;                 // 故障级保持：PID 件故障或非有限（上游闸持续命中时已在早退路径改写）/ fault held
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        IF bEnable AND (NOT bPidErr) THEN
            eState := E_DL_VavState.eIdle;     // 故障源消失且使能：回待机重启 / fault source gone: back to idle
        END_IF

    ELSE
        eState := E_DL_VavState.eFault;        // 非法状态兜底 / illegal-state fallback
        eErr := DL_VAV_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        fDamperCmdPct := fOpenMinPct;          // 开度回最小开度（安全侧）/ damper to floor, safe side
        bAtMin := TRUE;                        // 贴下限如实外显 / at-floor shown truthfully
        bAtMax := FALSE;                       // 贴上限撤 / at-ceiling withdrawn
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜卡滞/拒动诊断收口：判稳计时器 Q 即诊断（tFbDelay 内不判，R100）
 *----------------------------------------------------------------------------*)
bFbMismatch := fbMismatchT.Q;                  // 诊断出口 = 判稳定时器 Q / diagnosis output = settle timer Q
END_FUNCTION_BLOCK
