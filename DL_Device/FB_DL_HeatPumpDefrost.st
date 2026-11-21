//==============================================================================
// 功能块：FB_DL_HeatPumpDefrost ｜ 中文名称：空气源热泵除霜判据与除霜态时序
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：进入三条件：盘管-环境温差达门槛（环境温减盘管温大于等于
//           fCoilAmbDeltaK）、压缩机连续运行达 tMinCompRun、环境温度
//           处于窗口内且湿度达门限；退出：盘管温升至 fExitCoilC 或除
//           霜超时（tDefrostMax）；最小间隔 tDefrostGap 防频繁除霜；
//           超时连续累计供检修判据（MANUAL 建议连续 3 次检修，本件不
//           锁故障：锁死会使机组彻底停机，现场代价高于结霜）。安全侧
//           铁律：任何异常退出都回制热（除霜卡死会让蒸发器彻底结冰）。
//           本件只出请求与状态，四通阀/风机执行由上位裁决。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：温度[摄氏度] / 温差[K] / 相对湿度[%] / 时长参数[min] / 计数[次]
// 错误码表：16#0003_0192 信息级（除霜请求被最小间隔阻延，阻延沿发一次，
//           不置 bError）/ 16#0003_0193 信息级（除霜超时强制退出回制
//           热，计数累计，不置 bError）/ 16#0003_036C 故障级（参数组
//           态非法，含环境窗倒置、温差门槛非正、任一时长非正、湿度门
//           限超 0~100 域，置 bError）/ 16#0003_036D 故障级（输入非有
//           限，置 bError，强制退出回制热）/ 16#0003_036E 故障级兜底
//           （状态机落 ELSE 或非法状态，置 bError 并强制退出回制热）
// 状态机：E_DL_DefrostState（eIdle=0 / eMonitor=10 / eGapWait=20 /
//           eDefrost=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 036E
//           并强制退出除霜回制热（安全侧：除霜态绝不残留）
// 边界行为：① 除霜超时 → 信息 0193 + 强制退出回制热 + uTimeoutCount
//           饱和累计（连续 3 次由 MANUAL 建议检修，不锁故障）；② 环境
//           窗倒置（低大于高）、温差门槛非正、任一时长非正、湿度门限
//           超 0~100 域 → 故障 036C；③ 最小间隔未到 → bBlockedByGap :=
//           TRUE + 信息 0192（请求阻延上升沿发一次，不每拍刷），挂
//           eGapWait，退出条件两条：间隔到（转除霜）或进入条件消失
//           （回监视）；④ 输入非有限（NaN 自反判 + Inf 幅值上限判，
//           R79）→ 故障 036D + 强制退出回制热；⑤ 失能 → 立即退出除
//           霜回制热（安全侧）+ bValid := FALSE；⑥ TON 实例在待机/
//           故障/除霜各分支无条件周期刷新（R40 家族），除霜计时无相
//           内累计；⑦ 首次除霜请求不受间隔约束（上电无历史除霜）；
//           ⑧ 除霜间隔定时器经除霜退出「断输入一拍」重启计时；
//           ⑨ fDeltaK 定义为环境温减盘管温（正值越大结霜趋势越强）。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.5）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_DefrostState（归属 DL_Device，与 FB_DL_HeatPumpDefrost 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DefrostState :
(
    eIdle     := 0,   // 失能/待机：除霜撤、回制热语义 / Idle: defrost withdrawn, back to heating
    eMonitor  := 10,  // 制热监视：三条件逐拍评估 / Monitor: heating, entry conditions evaluated per scan
    eGapWait  := 20,  // 条件满足但最小间隔未到，等待放行 / Conditions met but gap timer running
    eDefrost  := 30,  // 除霜进行中：升温或超时退出 / Defrost active: exits on coil rise or timeout
    eFault    := 99   // 故障兜底态：组态非法/非有限/非法状态，强制回制热 / Fault fallback, forced back to heating
);
END_TYPE
FUNCTION_BLOCK FB_DL_HeatPumpDefrost
VAR_INPUT
    fCoilC        : LREAL;                       // 盘管温度 [摄氏度] / Coil temperature [degC]
    fAmbC         : LREAL;                       // 环境温度 [摄氏度] / Ambient temperature [degC]
    fAmbRhPct     : LREAL;                       // 环境相对湿度 [百分数] / Ambient relative humidity [percent]
    bCompRunning  : BOOL;                        // 压缩机运行反馈 / Compressor running feedback
    fCoilAmbDeltaK : LREAL := 8.0;               // 进入温差门槛 [K]（环境减盘管）/ Entry delta threshold [K], ambient minus coil
    fAmbWinLowC   : LREAL := -5.0;               // 环境温度窗下限 [摄氏度] / Ambient window lower bound [degC]
    fAmbWinHighC  : LREAL := 15.0;               // 环境温度窗上限 [摄氏度] / Ambient window upper bound [degC]
    fRhMinPct     : LREAL := 50.0;               // 湿度门限 [百分数] / Humidity threshold [percent]
    fExitCoilC    : LREAL := 12.0;               // 退出盘管温 [摄氏度] / Exit coil temperature [degC]
    tMinCompRun   : TIME := T#45M;               // 压缩机连续运行门槛 [min] / Minimum continuous compressor run [min]
    tDefrostMax   : TIME := T#10M;               // 除霜最大时长 [min] / Maximum defrost duration [min]
    tDefrostGap   : TIME := T#30M;               // 两次除霜最小间隔 [min] / Minimum interval between defrosts [min]
    bEnable       : BOOL;                        // 总使能 / Master enable
    bReset        : BOOL;                        // 复位，上升沿清状态与计数 / Reset, rising edge clears state and counters
END_VAR
VAR_OUTPUT
    bDefrostReq   : BOOL;                       // 除霜请求（条件满足且未在除霜中）/ Defrost request (conditions met and not active)
    bDefrostActive : BOOL;                      // 除霜进行中 / Defrost active flag
    tDefrostElapsed : TIME;                     // 除霜已进行时长 [min]：除霜中实时，退出后保持末次时长（诊断用）/ Elapsed defrost duration, live while active, holds last value after exit for diagnostics
    fDeltaK       : LREAL;                      // 结霜趋势温差 [K]，环境减盘管 / Frost-trend delta [K], ambient minus coil
    bBlockedByGap : BOOL;                       // 请求被最小间隔阻延 / Request blocked by gap interval
    bOutOfWindow  : BOOL;                       // 环境温度在窗外 / Ambient temperature out of window
    uDefrostCount : UDINT;                      // 累计除霜次数 [次]，饱和计数 / Cumulative defrost count, saturated
    uTimeoutCount : UDINT;                      // 累计除霜超时次数 [次]，饱和计数 / Cumulative timeout count, saturated
    eErr          : UDINT;                      // 错误码，0 = 无错，码位 16#0003_0192 起信息级、16#0003_036C 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                       // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                       // 判据数据可用标志，失能/故障闸显式 FALSE / Verdict usable flag, explicit FALSE on disable/fault gates
    eState        : E_DL_DefrostState;          // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset       : R_TRIG;                     // 复位上升沿检测实例 / Reset rising edge detector
    fbCompRun     : TON;                        // 压缩机连续运行定时器 / Continuous compressor run timer
    fbDefrost     : TON;                        // 除霜时长定时器（超时判据）/ Defrost duration timer, timeout basis
    fbGap         : TON;                        // 除霜最小间隔定时器 / Defrost gap interval timer
    bGapKick      : BOOL;                       // 间隔定时器断输入一拍标志（R40 家族）/ Gap timer one-scan kick flag
    fbReqBlockTrig : R_TRIG;                    // 请求阻延上升沿检测实例（0192 一次触发）/ Request-block rising edge detector, 0192 once per edge
    bEnterCond    : BOOL;                       // 除霜进入三条件全满足 / All three entry conditions met
    bGapOk        : BOOL;                       // 间隔放行：无历史除霜或间隔已满 / Gap released: no history or interval elapsed
    bBlockedNow   : BOOL;                       // 本拍请求被阻延 / Request blocked this scan
    bDefrostEver  : BOOL;                       // 激活以来是否除过霜 / Any defrost since activation
END_VAR
VAR CONSTANT
    DL_HPD_CODE_INFO_1 : UDINT := 16#0003_0192;   // 信息级槽 1（请求被最小间隔阻延） / info slot 1
    DL_HPD_CODE_INFO_2 : UDINT := 16#0003_0193;   // 信息级槽 2（除霜超时强制退出） / info slot 2
    DL_HPD_CODE_FLT_1  : UDINT := 16#0003_036C;   // 故障级槽 1（参数组态非法） / fault slot 1
    DL_HPD_CODE_FLT_2  : UDINT := 16#0003_036D;   // 故障级槽 2（输入非有限） / fault slot 2
    DL_HPD_CODE_FLT_3  : UDINT := 16#0003_036E;   // 故障级槽 3（非法状态兜底） / fault slot 3, illegal-state fallback
    DL_DF_ZERO    : LREAL := 0.0;               // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_DF_TOL     : LREAL := 1.0E-6;            // 浮点比较容差 [—] / Float comparison tolerance
    DL_DF_INF     : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_DF_CNT_MAX : UDINT := 16#FFFF_FFFE;      // 饱和计数上限 [次] / Saturating counter ceiling
    DL_DF_RH_MAX  : LREAL := 100.0;             // 湿度门限域上限 [百分数] / Humidity threshold domain ceiling [percent]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：三 TON 与两 R_TRIG 在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbCompRun(IN := bCompRunning AND bEnable,      // 压缩机连续运行计时（失能即断）/ compressor run timing, broken on disable
          PT := tMinCompRun);                  // 连续运行门槛 / continuous run threshold
fbDefrost(IN := (eState = E_DL_DefrostState.eDefrost) AND bEnable,  // 仅除霜态计时（相内不累计，R40 家族）/ times only in defrost state
          PT := tDefrostMax);                  // 除霜最大时长 / maximum defrost duration
fbGap(IN := bEnable AND NOT bGapKick,          // 间隔计时，断输入一拍重启（R40 家族）/ gap timing, kicked one scan per defrost exit
      PT := tDefrostGap);                      // 最小间隔 / minimum interval
bGapKick := FALSE;                             // kick 标志单拍自清（除霜退出时由状态机重置位）/ kick self-clears, state machine re-sets on exit

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState        := E_DL_DefrostState.eIdle;
    eErr          := 16#0000_0000;             // 复位清码 / reset clears code
    bError        := FALSE;                    // 复位清故障 / reset clears fault
    bDefrostReq   := FALSE;                    // 请求撤 / request withdrawn
    bDefrostActive := FALSE;                   // 除霜撤（回制热语义）/ defrost withdrawn
    bBlockedByGap := FALSE;                    // 阻延标志清 / block flag cleared
    uDefrostCount := 0;                        // 除霜计数清零 / defrost count zeroed
    uTimeoutCount := 0;                        // 超时计数清零 / timeout count zeroed
    bDefrostEver  := FALSE;                    // 除霜历史清零，首个请求放行 / defrost history cleared, first request released
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *       命中即强制退出除霜回制热（安全侧）
 *----------------------------------------------------------------------------*)
IF (fCoilC <> fCoilC) OR (ABS(fCoilC) >= DL_DF_INF)
   OR (fAmbC <> fAmbC) OR (ABS(fAmbC) >= DL_DF_INF)
   OR (fAmbRhPct <> fAmbRhPct) OR (ABS(fAmbRhPct) >= DL_DF_INF)
   OR (fCoilAmbDeltaK <> fCoilAmbDeltaK) OR (ABS(fCoilAmbDeltaK) >= DL_DF_INF)
   OR (fAmbWinLowC <> fAmbWinLowC) OR (ABS(fAmbWinLowC) >= DL_DF_INF)
   OR (fAmbWinHighC <> fAmbWinHighC) OR (ABS(fAmbWinHighC) >= DL_DF_INF)
   OR (fRhMinPct <> fRhMinPct) OR (ABS(fRhMinPct) >= DL_DF_INF)
   OR (fExitCoilC <> fExitCoilC) OR (ABS(fExitCoilC) >= DL_DF_INF) THEN
    eState         := E_DL_DefrostState.eFault;
    eErr           := DL_HPD_CODE_FLT_2;           // 故障级：输入非有限 / fault: non-finite input
    bError         := TRUE;                    // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid         := FALSE;                   // 输出不可用 / outputs unusable
    bDefrostReq    := FALSE;                   // 请求撤 / request withdrawn
    bDefrostActive := FALSE;                   // 强制退出回制热（安全侧）/ forced back to heating, safe side
    bBlockedByGap  := FALSE;                   // 阻延标志清 / block flag cleared
    bOutOfWindow   := FALSE;                   // 故障态不判窗外 / out-of-window not judged in fault
    tDefrostElapsed := fbDefrost.ET;           // 时长出口为定时器实值（已断输入归零）/ elapsed output mirrors timer (input broken, zeroed)
    fbReqBlockTrig(CLK := FALSE);              // 阻延沿检测无条件刷新（早退路径保刷新，红线 5）/ block edge refreshed unconditionally on early-exit path
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数组态闸（窗倒置/温差门槛非正/任一时长非正/湿度门限超域/退出温非正）
 *----------------------------------------------------------------------------*)
IF (fAmbWinLowC > fAmbWinHighC)
   OR (fCoilAmbDeltaK <= DL_DF_TOL)
   OR (tMinCompRun <= T#0S) OR (tDefrostMax <= T#0S) OR (tDefrostGap <= T#0S)
   OR (fRhMinPct < DL_DF_ZERO) OR (fRhMinPct > DL_DF_RH_MAX)
   OR (fExitCoilC <= DL_DF_ZERO) THEN
    eState         := E_DL_DefrostState.eFault;
    eErr           := DL_HPD_CODE_FLT_1;           // 故障级：参数组态非法 / fault: parameter config invalid
    bError         := TRUE;                    // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid         := FALSE;                   // 输出不可用 / outputs unusable
    bDefrostReq    := FALSE;                   // 请求撤 / request withdrawn
    bDefrostActive := FALSE;                   // 强制退出回制热（安全侧）/ forced back to heating, safe side
    bBlockedByGap  := FALSE;                   // 阻延标志清 / block flag cleared
    bOutOfWindow   := FALSE;                   // 故障态不判窗外 / out-of-window not judged in fault
    tDefrostElapsed := fbDefrost.ET;           // 时长出口为定时器实值 / elapsed output mirrors timer
    fbReqBlockTrig(CLK := FALSE);              // 阻延沿检测无条件刷新（早退路径保刷新，红线 5）/ block edge refreshed unconditionally on early-exit path
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜判据计算：温差、窗外、进入三条件、间隔放行、阻延
 *----------------------------------------------------------------------------*)
fDeltaK := fAmbC - fCoilC;                     // 结霜趋势温差 = 环境 − 盘管 [K] / frost-trend delta [K]
bOutOfWindow := (fAmbC < fAmbWinLowC) OR (fAmbC > fAmbWinHighC);  // 环境窗外 / ambient out of window
bEnterCond := (fDeltaK >= fCoilAmbDeltaK)      // 条件一：温差达门槛 / condition 1: delta threshold
          AND fbCompRun.Q                     // 条件二：压缩机连续运行达门槛 / condition 2: continuous run
          AND (NOT bOutOfWindow)              // 条件三之一：环境在窗内 / condition 3a: in window
          AND (fAmbRhPct >= fRhMinPct)        // 条件三之二：湿度达门限 / condition 3b: humidity threshold
          AND bCompRunning;                   // 压缩机运行中（除霜只在运行态进）/ compressor running
bGapOk := (NOT bDefrostEver) OR fbGap.Q;       // 间隔放行：无历史除霜或最小间隔已满 / gap released
bBlockedNow := bEnterCond AND (NOT bGapOk);    // 本拍阻延判据 / blocked predicate this scan
fbReqBlockTrig(CLK := bBlockedNow);            // 阻延沿检测无条件刷新（0192 沿发一次）/ block edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 6｜状态机：CASE 含 ELSE 兜底（非法状态 → 036E + 强制回制热，安全侧）
 *----------------------------------------------------------------------------*)
bDefrostActive := (eState = E_DL_DefrostState.eDefrost);  // 除霜态先行取值（CASE 改写前）/ defrost flag captured before CASE rewrite

CASE eState OF

    E_DL_DefrostState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        bDefrostReq := FALSE;                  // 请求撤 / request withdrawn
        bDefrostActive := FALSE;               // 除霜撤（回制热语义）/ defrost withdrawn
        bBlockedByGap := FALSE;                // 阻延标志清 / block flag cleared
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        IF bEnable THEN
            eState := E_DL_DefrostState.eMonitor;      // 使能进制热监视 / enable enters heating monitor
        END_IF

    E_DL_DefrostState.eMonitor:
        bValid := TRUE;                        // 监视态判据可用 / verdict usable in monitor
        bDefrostActive := FALSE;               // 非除霜态 / not defrosting
        bDefrostReq := bEnterCond AND (NOT bGapOk);  // 请求被阻延时仍如实外显 / request shown while blocked
        bBlockedByGap := bBlockedNow;          // 阻延标志逐拍刷新 / block flag refreshed per scan
        IF bEnterCond AND bGapOk THEN
            eState := E_DL_DefrostState.eDefrost;      // 三条件齐且间隔放行：进除霜 / conditions met and gap released: defrost
            bDefrostEver := TRUE;              // 记录除霜历史 / record defrost history
            uDefrostCount := uDefrostCount + 1;        // 除霜计数累计 / defrost count up
            IF uDefrostCount >= DL_DF_CNT_MAX THEN
                uDefrostCount := DL_DF_CNT_MAX;        // 饱和防回绕 / saturate to avoid wrap
            END_IF
        ELSIF bEnterCond THEN
            eState := E_DL_DefrostState.eGapWait;      // 条件齐但间隔未到：挂起等待 / conditions met but gap running: wait
        END_IF

    E_DL_DefrostState.eGapWait:
        bValid := TRUE;                        // 等待态判据可用 / verdict usable in wait
        bDefrostActive := FALSE;               // 非除霜态 / not defrosting
        bDefrostReq := TRUE;                   // 请求保持外显 / request held visible
        bBlockedByGap := TRUE;                 // 阻延标志保持 / block flag held
        IF NOT bEnable THEN
            eState := E_DL_DefrostState.eIdle;         // 失能回待机（安全侧）/ disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用 / explicit FALSE on disable gate
            bDefrostReq := FALSE;              // 请求撤 / request withdrawn
            bBlockedByGap := FALSE;            // 阻延标志清 / block flag cleared
        ELSIF NOT bEnterCond THEN
            eState := E_DL_DefrostState.eMonitor;      // 进入条件消失退出（第二条退出条件）/ entry conditions vanished, second exit
            bDefrostReq := FALSE;              // 请求撤 / request withdrawn
            bBlockedByGap := FALSE;            // 阻延标志清 / block flag cleared
        ELSIF fbGap.Q THEN
            eState := E_DL_DefrostState.eDefrost;      // 间隔到转除霜（第一条退出条件）/ gap elapsed, first exit: defrost
            bDefrostEver := TRUE;              // 记录除霜历史 / record defrost history
            uDefrostCount := uDefrostCount + 1;        // 除霜计数累计 / defrost count up
            IF uDefrostCount >= DL_DF_CNT_MAX THEN
                uDefrostCount := DL_DF_CNT_MAX;        // 饱和防回绕 / saturate to avoid wrap
            END_IF
        END_IF

    E_DL_DefrostState.eDefrost:
        bValid := TRUE;                        // 除霜态判据可用 / verdict usable in defrost
        bDefrostActive := TRUE;                // 除霜进行中 / defrosting
        bDefrostReq := FALSE;                  // 已在除霜，请求撤 / already defrosting, request withdrawn
        bBlockedByGap := FALSE;                // 除霜中无阻延语义 / no blocking semantics in defrost
        tDefrostElapsed := fbDefrost.ET;       // 除霜时长出口 [min] / elapsed defrost duration
        IF fCoilC >= fExitCoilC THEN
            eState := E_DL_DefrostState.eMonitor;      // 盘管升温正常退出 / coil warmed, normal exit
            bGapKick := TRUE;                  // 间隔定时器断输入一拍重启 / gap timer kicked one scan
            bDefrostActive := FALSE;           // 回制热（安全侧）/ back to heating, safe side
        ELSIF fbDefrost.Q THEN
            eState := E_DL_DefrostState.eMonitor;      // 超时强制退出回制热（安全侧）/ timeout forced exit back to heating
            eErr := DL_HPD_CODE_INFO_2;        // 信息级：除霜超时强制退出 / info: defrost timeout forced exit
            bError := FALSE;                   // 信息级不置 bError / info never raises bError
            uTimeoutCount := uTimeoutCount + 1;        // 超时计数累计（检修判据）/ timeout count up, maintenance evidence
            IF uTimeoutCount >= DL_DF_CNT_MAX THEN
                uTimeoutCount := DL_DF_CNT_MAX;        // 饱和防回绕 / saturate to avoid wrap
            END_IF
            bGapKick := TRUE;                  // 间隔定时器断输入一拍重启 / gap timer kicked one scan
            bDefrostActive := FALSE;           // 回制热（安全侧）/ back to heating, safe side
        END_IF

    ELSE
        eState := E_DL_DefrostState.eFault;    // 非法状态兜底 / illegal-state fallback
        eErr := DL_HPD_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        bDefrostReq := FALSE;                  // 请求撤 / request withdrawn
        bDefrostActive := FALSE;               // 强制退出回制热（安全侧，除霜态绝不残留）/ forced back to heating, never residual
        bBlockedByGap := FALSE;                // 阻延标志清 / block flag cleared
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜信息级收口：阻延沿发一次 0192（不每拍刷，见边界行为③）
 *----------------------------------------------------------------------------*)
IF fbReqBlockTrig.Q THEN
    eErr := DL_HPD_CODE_INFO_1;                // 信息级：除霜请求被最小间隔阻延 / info: defrost request blocked by gap
    bError := FALSE;                           // 信息级不置 bError / info never raises bError
END_IF
END_FUNCTION_BLOCK
