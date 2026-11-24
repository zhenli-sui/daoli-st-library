//==============================================================================
// 功能块：FB_DL_DewpointReset ｜ 中文名称：依据室内露点重置冷冻水供水温度设定
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：室内露点重置冷冻水供水温度设定：目标 = max(露点 + 安全余
//           量, 下限)，带上下限钳位与斜率限制（fRateKPerS，由
//           uDeltaTimeMs 显式积分，禁系统时间函数）。露点由
//           FC_DL_DewPointCalc 计算（Magnus-Tetens 常数唯一属主为
//           FC_DL_VaporPressureSat，R23 裁定）——只调用不复制。双出
//           口：结露风险（露点 + 余量超上限，供水被顶到上限，除湿能
//           力不足，如实外显不静默）与域外钳位提示。失能保持设定。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 OSCAT ROOM_CONTROL 行为定义/参数域，零代码行与符号名复制）
// 单位表：温度[摄氏度] / 相对湿度[%] / 余量[K] / 斜率[K每s] / 扫描间隔[ms]
// 错误码表：16#0002_3601 信息级（露点域外钳位：湿度钳 1~100、干球钳
//           −40~60、下游件域外提示，不置 bError）/ 16#0002_3602 信息
//           级（防结露下限生效，供水被顶到上限，除湿能力不足，不置
//           bError）/ 16#0002_3605 预留禁用（不得挪用）/ 16#0002_3610
//           故障级（供水上下限倒置或余量/斜率组态非法，置 bError）/
//           16#0002_3611 故障级（输入非有限或下游件数据不可信，置
//           bError）/ 16#0002_3612 预留禁用（不得挪用）
// 状态机：E_DL_DewpointResetState（eIdle=0 / eTrack=10 / eCondRisk=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 复用 3611（§3 未为本
//           件单列兜底槽，不得越段加码）并回上限安全侧
// 边界行为：① 湿度钳 1~100、干球钳 −40~60（下游件承诺域），钳位发生
//           → 信息 3601；② 露点 + 余量大于供水上限 → bCondRisk :=
//           TRUE + 信息 3602，设定被顶到上限（如实反映「制冷量再低
//           也压不住露点」，不静默），退出条件两条：风险消失回追踪相
//           或失能回待机；③ fChwMinC 大于等于 fChwMaxC 或余量小于 0
//           或斜率非正 → 故障 3610；④ 非有限（NaN 自反判 + Inf 幅值
//           上限判，R79）→ 故障 3611，设定回供水上限安全侧（防结露
//           优先，冷却失效由上位温控回路告警，不静默）；⑤ 下游露点
//           件 uErrorId 非零或 bInRange 为假（预钳位后正常不可达，防
//           御路径）→ 复用信息 3601 且露点取干球温度保守估计（热力学
//           事实：露点不超过干球），下游信息级不升格（R115 纪律反向
//           适用：信息安全侧不得放大）；⑥ 失能 → 保持设定 + bValid :=
//           FALSE（供水温度突变会导致除湿振荡）；⑦ 斜率限制用
//           uDeltaTimeMs 显式积分，间隔为 0 本拍不动；⑧ 首拍设定从
//           下限起坡（首拍不出未知值）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.9）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_DewpointResetState（归属 DL_Algo，与 FB_DL_DewpointReset 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DewpointResetState :
(
    eIdle     := 0,   // 失能/待机：设定保持 / Idle: setpoint held
    eTrack    := 10,  // 斜率追踪：向目标设定限速逼近 / Track: rate-limited approach to target
    eCondRisk := 20,  // 结露风险：目标超上限，供水顶上限 / Condensation risk: target above ceiling, supply pinned
    eFault    := 99   // 故障兜底态：组态非法/非有限/非法状态，设定回上限 / Fault fallback, setpoint at ceiling
);
END_TYPE
FUNCTION_BLOCK FB_DL_DewpointReset
VAR_INPUT
    fRoomTempC    : LREAL;                     // 室内干球温度 [摄氏度] / Room dry-bulb temperature [degC]
    fRoomRhPct    : LREAL;                     // 室内相对湿度 [百分数] / Room relative humidity [percent]
    fChwMinC      : LREAL := 7.0;              // 供水设定下限 [摄氏度] / Chilled-water setpoint floor [degC]
    fChwMaxC      : LREAL := 18.0;             // 供水设定上限 [摄氏度] / Chilled-water setpoint ceiling [degC]
    fDewMarginK   : LREAL := 1.5;              // 防结露安全余量 [K] / Anti-condensation margin [K]
    fRateKPerS    : LREAL := 0.05;             // 设定斜率 [K每s] / Setpoint rate limit [K per s]
    uDeltaTimeMs  : UDINT;                     // 扫描间隔 [ms]，调用方注入，禁用系统时间函数 / Scan interval [ms], caller-injected
    bEnable       : BOOL;                      // 总使能 / Master enable
    bReset        : BOOL;                      // 复位，上升沿清状态与设定 / Reset, rising edge clears state and setpoint
END_VAR
VAR_OUTPUT
    fChwSetC      : LREAL;                     // 冷冻水供水温度设定 [摄氏度] / Chilled-water supply setpoint [degC]
    fDewPointC    : LREAL;                     // 室内露点 [摄氏度]，下游件计算透传 / Room dew point [degC], passed through
    fMarginK      : LREAL;                     // 当前供水设定相对露点裕量 [K] / Margin of setpoint over dew point [K]
    bCondRisk     : BOOL;                      // 露点超出可调范围，除湿能力不足 / Dew point beyond adjustable range, dehumidification short
    bAtMin        : BOOL;                      // 设定贴下限 / Setpoint at floor
    bAtMax        : BOOL;                      // 设定贴上限 / Setpoint at ceiling
    eErr          : UDINT;                     // 错误码，0 = 无错，码位 16#0002_3601 起信息级、16#0002_3610 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 设定数据可用标志，失能/故障闸显式 FALSE / Setpoint usable flag, explicit FALSE on disable/fault gates
    eState        : E_DL_DewpointResetState;   // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset       : R_TRIG;                    // 复位上升沿检测实例 / Reset rising edge detector
    fRhClamped    : LREAL;                     // 钳位后湿度 [百分数] / Clamped humidity [percent]
    fTempClamped  : LREAL;                     // 钳位后干球 [摄氏度] / Clamped dry-bulb [degC]
    bDomainClamp  : BOOL;                      // 本拍发生域外钳位 / Domain clamp occurred this scan
    fTempReal     : REAL;                      // 干球降精度暂存 [摄氏度] / Dry-bulb staging in REAL precision
    fRhReal       : REAL;                      // 湿度降精度暂存 [百分数] / Humidity staging in REAL precision
    fDewReal      : REAL;                      // 露点返回值暂存 [摄氏度] / Dew-point return staging in REAL precision
    uDewErr       : UDINT;                     // 下游件错误码暂存 / Downstream error code staging
    fVaporPa      : REAL;                      // 下游件水汽压暂存 [Pa]（诊断透传）/ Downstream vapor pressure staging [Pa]
    bDewInRange   : BOOL;                      // 下游件域内标志暂存 / Downstream in-domain flag staging
    bDewOk        : BOOL;                      // 下游件结果可用判据 / Downstream result usable predicate
    fTargetC      : LREAL;                     // 钳位前目标设定 [摄氏度] / Pre-limit target setpoint [degC]
    fStepK        : LREAL;                     // 本拍允许步长 [K] / Allowed step this scan [K]
    fDeltaK       : LREAL;                     // 本拍目标增量 [K] / Target delta this scan [K]
    fDeltaApplied : LREAL;                     // 本拍实际增量 [K]（步长限幅后）/ Applied delta after rate limit [K]
    bFirstScan    : BOOL := TRUE;              // 首拍初始化标志 / First-scan initialization flag
END_VAR
VAR CONSTANT
    DL_DPR_CODE_INFO_1 : UDINT := 16#0002_3601;   // 信息级槽 1（露点域外钳位） / info slot 1
    DL_DPR_CODE_INFO_2 : UDINT := 16#0002_3602;   // 信息级槽 2（防结露下限生效） / info slot 2
    DL_DPR_CODE_RSV_1  : UDINT := 16#0002_3605;   // 预留禁用（不得挪用） / reserved, do not use
    DL_DPR_CODE_FLT_1  : UDINT := 16#0002_3610;   // 故障级槽 1（供水界倒置或组态非法） / fault slot 1
    DL_DPR_CODE_FLT_2  : UDINT := 16#0002_3611;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_DPR_CODE_RSV_2  : UDINT := 16#0002_3612;   // 预留禁用（不得挪用） / reserved, do not use
    DL_DP_ZERO    : LREAL := 0.0;              // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_DP_TOL     : LREAL := 1.0E-6;           // 浮点比较容差 [—] / Float comparison tolerance
    DL_DP_INF     : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_DP_RH_MIN  : LREAL := 1.0;              // 湿度钳位下限 [百分数] / Humidity clamp floor [percent]
    DL_DP_RH_MAX  : LREAL := 100.0;            // 湿度钳位上限 [百分数] / Humidity clamp ceiling [percent]
    DL_DP_T_MIN   : LREAL := -40.0;            // 干球钳位下限 [摄氏度]，下游件承诺域 / Dry-bulb clamp floor, downstream promised domain
    DL_DP_T_MAX   : LREAL := 60.0;             // 干球钳位上限 [摄氏度] / Dry-bulb clamp ceiling [degC]
    DL_DP_MS_PER_S : LREAL := 1000.0;          // 毫秒转秒系数 [s/ms] / Ms-to-s factor
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState  := E_DL_DewpointResetState.eIdle;
    eErr    := 16#0000_0000;                   // 复位清码 / reset clears code
    bError  := FALSE;                          // 复位清故障 / reset clears fault
    bCondRisk := FALSE;                        // 结露风险标志清 / condensation risk cleared
    bAtMin  := FALSE;                          // 贴下限清 / at-floor cleared
    bAtMax  := FALSE;                          // 贴上限清 / at-ceiling cleared
    bFirstScan := TRUE;                        // 重新首拍化 / re-initialize first scan
    fChwSetC := DL_DP_ZERO;                    // 设定清零待首拍初始化 / setpoint zeroed, awaits first-scan init
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *       命中即设定回上限安全侧（防结露优先）
 *----------------------------------------------------------------------------*)
IF (fRoomTempC <> fRoomTempC) OR (ABS(fRoomTempC) >= DL_DP_INF)
   OR (fRoomRhPct <> fRoomRhPct) OR (ABS(fRoomRhPct) >= DL_DP_INF)
   OR (fChwMinC <> fChwMinC) OR (ABS(fChwMinC) >= DL_DP_INF)
   OR (fChwMaxC <> fChwMaxC) OR (ABS(fChwMaxC) >= DL_DP_INF)
   OR (fDewMarginK <> fDewMarginK) OR (ABS(fDewMarginK) >= DL_DP_INF)
   OR (fRateKPerS <> fRateKPerS) OR (ABS(fRateKPerS) >= DL_DP_INF) THEN
    eState  := E_DL_DewpointResetState.eFault;
    eErr    := DL_DPR_CODE_FLT_2;              // 故障级：输入非有限 / fault: non-finite input
    bError  := TRUE;                           // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
    fChwSetC := fChwMaxC;                      // 设定回上限安全侧（防结露优先）/ setpoint to ceiling, safe side
    bCondRisk := FALSE;                        // 故障态不判结露风险 / risk not judged in fault
    bAtMin := FALSE;                           // 贴限撤 / at-floor withdrawn
    bAtMax := TRUE;                            // 贴上限如实外显 / at-ceiling shown truthfully
    fDewPointC := DL_DP_ZERO;                  // 露点出口清零 / dew-point output zeroed
    fMarginK := DL_DP_ZERO;                    // 裕量出口清零 / margin output zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（供水界倒置/余量小于 0/斜率非正）
 *----------------------------------------------------------------------------*)
IF (fChwMinC >= fChwMaxC) OR (fDewMarginK < DL_DP_ZERO) OR (fRateKPerS <= DL_DP_TOL) THEN
    eState  := E_DL_DewpointResetState.eFault;
    eErr    := DL_DPR_CODE_FLT_1;              // 故障级：供水上下限倒置或组态非法 / fault: band inverted or config invalid
    bError  := TRUE;                           // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid  := FALSE;                          // 输出不可用 / outputs unusable
    fChwSetC := fChwMaxC;                      // 设定回上限安全侧（防结露优先）/ setpoint to ceiling, safe side
    bCondRisk := FALSE;                        // 故障态不判结露风险 / risk not judged in fault
    bAtMin := FALSE;                           // 贴限撤 / at-floor withdrawn
    bAtMax := TRUE;                            // 贴上限如实外显 / at-ceiling shown truthfully
    fDewPointC := DL_DP_ZERO;                  // 露点出口清零 / dew-point output zeroed
    fMarginK := DL_DP_ZERO;                    // 裕量出口清零 / margin output zeroed
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜首拍初始化：设定从下限起坡（首拍不出未知值）
 *----------------------------------------------------------------------------*)
IF bFirstScan THEN
    fChwSetC := fChwMinC;                      // 首拍设定 = 下限 / first-scan setpoint = floor
    bFirstScan := FALSE;                       // 初始化完成 / initialization done
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜域钳位（湿度 1~100、干球 −40~60，下游件承诺域）+ 露点组合调用
 *       （FC_DL_DewPointCalc，每拍恰好一次，只调用不复制）
 *----------------------------------------------------------------------------*)
fRhClamped := fRoomRhPct;                      // 湿度工作副本 / humidity working copy
fTempClamped := fRoomTempC;                    // 干球工作副本 / dry-bulb working copy
bDomainClamp := FALSE;                         // 钳位标志逐拍重判 / clamp flag re-judged per scan
IF fRhClamped < DL_DP_RH_MIN THEN
    fRhClamped := DL_DP_RH_MIN;                // 湿度钳下限 / humidity clamped to floor
    bDomainClamp := TRUE;                      // 钳位发生 / clamped
END_IF
IF fRhClamped > DL_DP_RH_MAX THEN
    fRhClamped := DL_DP_RH_MAX;                // 湿度钳上限 / humidity clamped to ceiling
    bDomainClamp := TRUE;                      // 钳位发生 / clamped
END_IF
IF fTempClamped < DL_DP_T_MIN THEN
    fTempClamped := DL_DP_T_MIN;               // 干球钳下限 / dry-bulb clamped to floor
    bDomainClamp := TRUE;                      // 钳位发生 / clamped
END_IF
IF fTempClamped > DL_DP_T_MAX THEN
    fTempClamped := DL_DP_T_MAX;               // 干球钳上限 / dry-bulb clamped to ceiling
    bDomainClamp := TRUE;                      // 钳位发生 / clamped
END_IF
fTempReal := LREAL_TO_REAL(fTempClamped);      // 干球降精度显式转换 / dry-bulb explicit narrowing
fRhReal := LREAL_TO_REAL(fRhClamped);          // 湿度降精度显式转换 / humidity explicit narrowing
fDewReal := FC_DL_DewPointCalc(fTempC := fTempReal, fRhPct := fRhReal,
                               uErrorId => uDewErr, fVaporPa => fVaporPa,
                               bInRange => bDewInRange);  // 露点组合调用，返回值即露点 [摄氏度] / dew-point call, return is the dew point
bDewOk := (uDewErr = 16#0000_0000) AND bDewInRange;    // 下游可用判据 / downstream usable predicate
IF bDewOk THEN
    fDewPointC := fDewReal;                    // 露点出口透传 / dew-point output pass-through
ELSE
    fDewPointC := fTempClamped;                // 防御路径：露点取干球保守估计（露点不超过干球）/ defensive: dry-bulb conservative estimate
    bDomainClamp := TRUE;                      // 下游域外提示并入钳位信息（不升格）/ downstream hint merged into clamp info
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜目标计算：max(露点 + 余量, 下限)，超上限则顶上限并置结露风险
 *----------------------------------------------------------------------------*)
fTargetC := fDewPointC + fDewMarginK;          // 防结露目标 = 露点 + 余量 [摄氏度] / target = dew point plus margin
IF fTargetC < fChwMinC THEN
    fTargetC := fChwMinC;                      // 低于下限抬到下限 / below floor raised to floor
END_IF
IF fTargetC > fChwMaxC THEN
    fTargetC := fChwMaxC;                      // 超上限顶到上限 / above ceiling pinned to ceiling
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜状态机：CASE 含 ELSE 兜底（非法状态 → 复用 3611 + 回上限，安全侧）
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_DewpointResetState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        bCondRisk := FALSE;                    // 待机不判风险 / risk not judged in idle
        bAtMin := FALSE;                       // 贴限撤 / at-floor withdrawn
        bAtMax := FALSE;                       // 贴限撤 / at-ceiling withdrawn
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_DewpointResetState.eTrack;  // 使能进追踪相 / enable enters track
        END_IF

    E_DL_DewpointResetState.eTrack:
        bValid := TRUE;                        // 追踪相设定可用 / setpoint usable in track
        eErr := 16#0000_0000;                  // 追踪相先清码 / track clears code first
        bError := FALSE;                       // 追踪相先清故障 / track clears fault first
        IF bDomainClamp THEN
            eErr := DL_DPR_CODE_INFO_1;        // 信息级：露点域外钳位 / info: dew-point domain clamp
        END_IF
        IF NOT bEnable THEN
            eState := E_DL_DewpointResetState.eIdle;   // 失能回待机（设定保持）/ disable returns to idle, setpoint held
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
        ELSE
            fStepK := fRateKPerS * UDINT_TO_LREAL(uDeltaTimeMs) / DL_DP_MS_PER_S;  // 本拍步长 = 斜率乘时长 [K]，间隔 0 即不动 / step = rate times interval
            fDeltaK := fTargetC - fChwSetC;    // 目标增量 [K] / target delta [K]
            IF ABS(fDeltaK) <= fStepK THEN
                fDeltaApplied := fDeltaK;      // 一步到位 / single-step arrival
            ELSIF fDeltaK > DL_DP_ZERO THEN
                fDeltaApplied := fStepK;       // 正向限速 / positive rate-limited
            ELSE
                fDeltaApplied := -fStepK;      // 反向限速 / negative rate-limited
            END_IF
            fChwSetC := fChwSetC + fDeltaApplied;      // 限速逼近目标 / rate-limited approach
            bAtMin := ABS(fChwSetC - fChwMinC) < DL_DP_TOL;    // 贴下限（容差比较）/ at-floor with tolerance
            bAtMax := ABS(fChwSetC - fChwMaxC) < DL_DP_TOL;    // 贴上限（容差比较）/ at-ceiling with tolerance
            IF (fDewPointC + fDewMarginK) > fChwMaxC + DL_DP_TOL THEN
                eState := E_DL_DewpointResetState.eCondRisk;   // 露点超上限转结露风险相 / dew point beyond ceiling enters risk
            END_IF
        END_IF

    E_DL_DewpointResetState.eCondRisk:
        bValid := TRUE;                        // 风险相设定可用（顶上限值）/ setpoint usable in risk (pinned value)
        fChwSetC := fChwMaxC;                  // 供水被顶到上限（除湿能力不足，如实外显）/ supply pinned to ceiling
        bCondRisk := TRUE;                     // 结露风险标志 / condensation risk flag
        bAtMin := FALSE;                       // 贴下限撤 / at-floor withdrawn
        bAtMax := TRUE;                        // 贴上限如实外显 / at-ceiling shown truthfully
        eErr := DL_DPR_CODE_INFO_2;            // 信息级：防结露下限生效 / info: anti-condensation limit active
        bError := FALSE;                       // 信息级不置 bError / info never raises bError
        IF NOT bEnable THEN
            eState := E_DL_DewpointResetState.eIdle;   // 失能回待机（第二条退出条件）/ disable returns to idle, second exit
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bCondRisk := FALSE;                // 风险标志清 / risk flag cleared
        ELSIF (fDewPointC + fDewMarginK) <= fChwMaxC + DL_DP_TOL THEN
            eState := E_DL_DewpointResetState.eTrack;  // 风险消失回追踪相（第一条退出条件）/ risk gone, first exit to track
        END_IF

    ELSE
        eState := E_DL_DewpointResetState.eFault;  // 非法状态兜底 / illegal-state fallback
        eErr := DL_DPR_CODE_FLT_2;             // 兜底复用故障级槽 2（§3 未单列兜底槽，不得越段加码）/ fallback reuses fault slot 2
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        fChwSetC := fChwMaxC;                  // 设定回上限安全侧（防结露优先）/ setpoint to ceiling, safe side
        bCondRisk := FALSE;                    // 风险标志清 / risk flag cleared
        bAtMin := FALSE;                       // 贴限撤 / at-floor withdrawn
        bAtMax := TRUE;                        // 贴上限如实外显 / at-ceiling shown truthfully
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜裕量出口：当前供水设定相对露点裕量 [K]（负值即结露，可观测）
 *----------------------------------------------------------------------------*)
fMarginK := fChwSetC - fDewPointC;             // 裕量 = 设定 − 露点 [K] / margin = setpoint minus dew point
END_FUNCTION_BLOCK
