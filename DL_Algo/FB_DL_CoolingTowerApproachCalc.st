//==============================================================================
// 功能块：FB_DL_CoolingTowerApproachCalc ｜ 中文名称：冷却塔逼近度计算与风机台数优化建议
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：逼近度 = 冷却水出水温度 − 湿球温度（湿球由
//           FC_DL_WetBulbTempCalc v1.1.0 计算，组合调用不内联）；逼近度
//           滑动均值（1~60 拍窗）进入目标带判断；带外给出增/减风机台数
//           建议（单拍脉冲），带内保持。优化纪律：逼近度优先、N+1 冗余
//           （减台不低于 1 台）、换台最小间隔（tMinStageTime，被阻延沿
//           发一次 3402 提示）、湿球贴物理极限逼近度时加机无益（禁止
//           建议加机）。只出建议，不直接控风机（启停时序由上位轮值件
//           裁决，本件零执行输出）。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：温度[摄氏度] / 相对湿度[%] / 大气压[Pa] / 逼近度[K] / 台数[台] / 换台间隔[min] / 均值窗[拍]
// 错误码表：16#0002_3401 信息级（逼近度小于 0，出水低于湿球，传感器可疑，
//           不给任何换台建议，不置 bError）/ 16#0002_3402 信息级（换台
//           请求被最小间隔阻延，阻延沿发一次，不置 bError）/
//           16#0002_3405 预留禁用（不得挪用）/ 16#0002_3410 故障级（台
//           数或算法组态非法，置 bError）/ 16#0002_3411 故障级（输入非
//           有限或湿球件故障透传，置 bError）/ 16#0002_3412 预留禁用
//           （不得挪用）
// 状态机：E_DL_ApproachState（eIdle=0 / eWarmup=10 / eMonitor=20 /
//           eStageUpPending=30 / eStageDownPending=40 / eFault=99），
//           CASE 含 ELSE 兜底，ELSE 复用 3411（§3 未为本件单列兜底槽，
//           不得越段加码）并回 eFault、脉冲全撤、建议保持（安全侧）
// 边界行为：① 湿球件 bError 或 bValid 为假 → 透传为故障 3411 +
//           bWetBulbFault，锁存型标志只在故障相处置（R115），下游信息级
//           码（钳位提示）不升格；② fApproachK 小于 0（热力学不可能，
//           传感器可疑）→ 信息 3401 + bValid := FALSE + 不给任何换台
//           建议，可疑样本不入均值窗（防污染统计）；③ nFanRunning 大于
//           nFanTotal 或 nFanTotal 小于 1 或均值窗/目标/带宽组态非法 →
//           故障 3410；④ 浮点输入非有限 → 故障 3411；⑤ 换台请求受
//           tMinStageTime 约束，被阻延 → 信息 3402（阻延沿发一次，不每
//           拍刷），阻延期间挂 eStageUpPending/eStageDownPending，退出
//           条件两条：间隔到且需求仍在（发请求回 eMonitor）或带偏差
//           消失/需求翻转（不发请求回 eMonitor）；⑥ 湿球贴物理极限逼
//           近度（常量 2.0 K）且台数已满 → bNoFurtherGain，禁止建议加
//           机；首次换台请求不受守卫约束（上电无历史换台）；⑦ 失能 →
//           建议台数保持、脉冲全撤、bValid := FALSE；⑧ 恢复首拍窗口
//           清空重走暖机；守卫定时器经请求签发「断输入一拍」重启计时
//           （R40 家族）；⑨ 上电首拍 bValid := FALSE。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.3）
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_ApproachState（归属 DL_Algo，与 FB_DL_CoolingTowerApproachCalc 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ApproachState :
(
    eIdle             := 0,   // 失能/待机：建议保持，脉冲全撤 / Idle: suggestion held, pulses withdrawn
    eWarmup           := 10,  // 暖机：均值窗未满，只观测不出建议 / Warmup: window not full, observe only
    eMonitor          := 20,  // 监视：带内保持或按需即时发换台请求 / Monitor: hold in band or issue request at once
    eStageUpPending   := 30,  // 增台请求被最小间隔阻延，等守卫计时 / Increase request blocked by min interval
    eStageDownPending := 40,  // 减台请求被最小间隔阻延，等守卫计时 / Decrease request blocked by min interval
    eFault            := 99   // 故障兜底态：组态非法/非有限/下游透传 / Fault fallback
);
END_TYPE
FUNCTION_BLOCK FB_DL_CoolingTowerApproachCalc
VAR_INPUT
    fCondOutC        : LREAL;                  // 冷却水出水温度 [摄氏度] / Condenser water outlet temperature [degC]
    fAmbDryC         : LREAL;                  // 环境干球温度 [摄氏度] / Ambient dry-bulb temperature [degC]
    fRhPct           : LREAL;                  // 环境相对湿度 [百分数] / Ambient relative humidity [percent]
    fPressPa         : LREAL := 101325.0;      // 大气压 [Pa]，引脚注入非魔法数 / Atmospheric pressure [Pa], pin-injected
    nFanTotal        : INT;                    // 可投风机台数 [台]，1~8 / Total available fans, 1~8
    nFanRunning      : INT;                    // 当前运行台数 [台]，0~8 / Currently running fans, 0~8
    fApproachTargetK : LREAL := 4.0;           // 目标逼近度 [K] / Target approach [K]
    fApproachTolK    : LREAL := 0.5;           // 逼近度带宽半宽 [K] / Approach band half-width [K]
    tMinStageTime    : TIME := T#5M;           // 换台最小间隔 [min] / Minimum interval between stage changes [min]
    nWinSamples      : INT := 10;              // 均值窗长度 [拍]，1~60 / Moving-average window length, 1~60
    bEnable          : BOOL;                   // 总使能 / Master enable
    bReset           : BOOL;                   // 复位，上升沿清状态与窗口 / Reset, rising edge clears state and window
END_VAR
VAR_OUTPUT
    fWetBulbC        : LREAL;                  // 湿球温度 [摄氏度]，下游件输出透传 / Wet-bulb temperature [degC], passed through
    fApproachK       : LREAL;                  // 即时逼近度 [K]，出水减湿球 / Instantaneous approach [K]
    fApproachAvgK    : LREAL;                  // 逼近度滑动均值 [K] / Moving-average approach [K]
    nFanCmd          : INT;                    // 建议运行台数 [台]，失能保持 / Suggested running fans, held on disable
    bIncReq          : BOOL;                   // 增台建议，单拍脉冲 / Increase suggestion, one-scan pulse
    bDecReq          : BOOL;                   // 减台建议，单拍脉冲 / Decrease suggestion, one-scan pulse
    bNoFurtherGain   : BOOL;                   // 湿球已贴物理极限逼近度，加机无益 / Wet bulb at physical floor, more fans useless
    bWetBulbFault    : BOOL;                   // 湿球下游件故障透传标志，只在故障相处置 / Wet-bulb downstream fault pass-through flag
    eErr             : UDINT;                  // 错误码，0 = 无错，码位 16#0002_3401 起信息级、16#0002_3410 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError           : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid           : BOOL;                   // 建议数据可用标志，失能/故障闸显式 FALSE / Suggestion usable flag, explicit FALSE on disable/fault gates
    eState           : E_DL_ApproachState;     // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fWbOut           : LREAL;                  // 湿球件输出暂存 [摄氏度] / Wet-bulb output staging [degC]
    bWbClamped       : BOOL;                   // 湿球件钳位标志透传 / Wet-bulb clamped flag pass-through
    eWbErr           : UDINT;                  // 湿球件错误码暂存 / Wet-bulb error code staging
    bWbErr           : BOOL;                   // 湿球件故障标志暂存 / Wet-bulb fault flag staging
    bWbOk            : BOOL;                   // 湿球件可用且无故障 / Wet-bulb usable and fault-free
    fbReset          : R_TRIG;                 // 复位上升沿检测实例 / Reset rising edge detector
    fbBlockTrig      : R_TRIG;                 // 换台阻延上升沿检测实例（3402 一次触发）/ Stage-block rising edge detector, 3402 once per edge
    fbStageGuard     : TON;                    // 换台最小间隔守卫定时器 / Stage interval guard timer
    bGuardKick       : BOOL;                   // 守卫定时器断输入一拍标志（R40 家族）/ Guard timer one-scan kick flag
    afWinBuf         : ARRAY[0..59] OF LREAL;  // 逼近度滑动窗缓冲 [K] / Approach sliding window buffer [K]
    nWinIdx          : INT;                    // 窗写指针 [—] / Window write pointer
    uWinFill         : UDINT;                  // 窗已填充数 [拍] / Window filled count
    fWinSum          : LREAL;                  // 窗内累加和 [K]，增量维护 / Window running sum [K], incrementally maintained
    fApproachNew     : LREAL;                  // 本拍新逼近度样本 [K] / New approach sample this scan [K]
    bBadSensor       : BOOL;                   // 逼近度小于 0，传感器可疑 / Approach negative, sensor suspect
    bNeedInc         : BOOL;                   // 本拍需要增台（实时重算）/ Increase needed this scan, recomputed
    bNeedDec         : BOOL;                   // 本拍需要减台（实时重算）/ Decrease needed this scan, recomputed
    bGuardOk         : BOOL;                   // 守卫放行：无历史换台或间隔已满 / Guard released: no history or interval elapsed
    bBlockedNow      : BOOL;                   // 本拍换台请求被阻延 / Stage request blocked this scan
    bStageEverReq    : BOOL;                   // 激活以来是否签发过换台请求 / Any stage request issued since activation
    bFanCmdInit      : BOOL;                   // 建议台数是否已初始化 / Suggestion count initialized flag
    bActiveCalc      : BOOL;                   // 本拍处于可计算状态（暖机/监视/阻延挂起）/ Computable state this scan
END_VAR
VAR CONSTANT
    DL_CTWR_CODE_INFO_1 : UDINT := 16#0002_3401;   // 信息级槽 1（逼近度小于 0） / info slot 1
    DL_CTWR_CODE_INFO_2 : UDINT := 16#0002_3402;   // 信息级槽 2（换台请求被阻延） / info slot 2
    DL_CTWR_CODE_RSV_1  : UDINT := 16#0002_3405;   // 预留禁用（不得挪用） / reserved, do not use
    DL_CTWR_CODE_FLT_1  : UDINT := 16#0002_3410;   // 故障级槽 1（台数或组态非法） / fault slot 1
    DL_CTWR_CODE_FLT_2  : UDINT := 16#0002_3411;   // 故障级槽 2（非有限或湿球透传） / fault slot 2
    DL_CTWR_CODE_RSV_2  : UDINT := 16#0002_3412;   // 预留禁用（不得挪用） / reserved, do not use
    DL_AP_ZERO       : LREAL := 0.0;           // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_AP_INF        : LREAL := 1.7976931348623157E308;  // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling, Inf criterion
    DL_AP_TOL        : LREAL := 1.0E-6;        // 浮点比较容差 [—] / Float comparison tolerance
    DL_AP_WIN_MAX    : INT   := 60;            // 均值窗长度上限 [拍] / Moving-average window ceiling
    DL_AP_FAN_MAX    : INT   := 8;             // 风机台数上限 [台] / Fan count ceiling
    DL_AP_FAN_MIN    : INT   := 1;             // N+1 冗余最低运行台数 [台] / Minimum running fans for N+1 redundancy
    DL_AP_PHYS_FLOOR : LREAL := 2.0;           // 物理极限逼近度 [K]，贴限判加机无益 / Physical floor approach [K], gain-limit criterion
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：沿检测与守卫定时器在任何分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                        // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStageGuard(IN := bEnable AND NOT bGuardKick, // 断输入一拍重启计时（R40 家族）/ break input one scan to restart timing
             PT := tMinStageTime);             // 守卫门槛 = 换台最小间隔 / guard threshold = min stage interval
bGuardKick := FALSE;                           // kick 标志单拍自清（本拍签发请求时由状态机重置位）/ kick flag self-clears, state machine re-sets on issue

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState        := E_DL_ApproachState.eIdle;
    eErr          := 16#0000_0000;             // 复位清码 / reset clears code
    bError        := FALSE;                    // 复位清故障 / reset clears fault
    uWinFill      := 0;                        // 窗口清空重走暖机 / window cleared, warmup again
    nWinIdx       := 0;                        // 写指针归零 / write pointer zeroed
    fWinSum       := DL_AP_ZERO;               // 累加和清零 / sum zeroed
    fApproachAvgK := DL_AP_ZERO;               // 均值出口清零 / average output zeroed
    bIncReq       := FALSE;                    // 脉冲全撤 / pulses withdrawn
    bDecReq       := FALSE;                    // 脉冲全撤 / pulses withdrawn
    bNoFurtherGain := FALSE;                   // 贴限标志清除 / gain-limit flag cleared
    bBadSensor    := FALSE;                    // 传感器可疑标志清除 / suspect flag cleared
    bStageEverReq := FALSE;                    // 换台历史清零，首个请求放行 / stage history cleared, first request released
    bFanCmdInit   := FALSE;                    // 建议台数待重初始化 / suggestion count re-initialized
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸（浮点引脚逐个：NaN 自反判 + Inf 幅值上限判，R79）
 *----------------------------------------------------------------------------*)
IF (fCondOutC <> fCondOutC) OR (ABS(fCondOutC) >= DL_AP_INF)
   OR (fAmbDryC <> fAmbDryC) OR (ABS(fAmbDryC) >= DL_AP_INF)
   OR (fRhPct <> fRhPct) OR (ABS(fRhPct) >= DL_AP_INF)
   OR (fPressPa <> fPressPa) OR (ABS(fPressPa) >= DL_AP_INF)
   OR (fApproachTargetK <> fApproachTargetK) OR (ABS(fApproachTargetK) >= DL_AP_INF)
   OR (fApproachTolK <> fApproachTolK) OR (ABS(fApproachTolK) >= DL_AP_INF) THEN
    eState := E_DL_ApproachState.eFault;
    eErr   := DL_CTWR_CODE_FLT_2;                  // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    bIncReq := FALSE;                          // 脉冲全撤安全侧 / pulses withdrawn, safe side
    bDecReq := FALSE;                          // 脉冲全撤安全侧 / pulses withdrawn, safe side
    bNoFurtherGain := FALSE;                   // 故障态不判贴限 / gain-limit not judged in fault
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸（台数域/主从关系/窗长/目标/带宽）
 *----------------------------------------------------------------------------*)
IF (nFanTotal < DL_AP_FAN_MIN) OR (nFanTotal > DL_AP_FAN_MAX)
   OR (nFanRunning < 0) OR (nFanRunning > nFanTotal)
   OR (nWinSamples < 1) OR (nWinSamples > DL_AP_WIN_MAX)
   OR (fApproachTargetK <= DL_AP_TOL) OR (fApproachTolK <= DL_AP_TOL) THEN
    eState := E_DL_ApproachState.eFault;
    eErr   := DL_CTWR_CODE_FLT_1;                  // 故障级：台数或算法组态非法 / fault: fan or algorithm config invalid
    bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                           // 输出不可用 / outputs unusable
    bIncReq := FALSE;                          // 脉冲全撤安全侧 / pulses withdrawn, safe side
    bDecReq := FALSE;                          // 脉冲全撤安全侧 / pulses withdrawn, safe side
    bNoFurtherGain := FALSE;                   // 故障态不判贴限 / gain-limit not judged in fault
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜湿球组合调用：每拍恰好一次，不内联不复制（R115 透传纪律）
 *----------------------------------------------------------------------------*)
FC_DL_WetBulbTempCalc(fTempC := fAmbDryC, fRh := fRhPct, fPress := fPressPa,
                      fWetBulbC => fWbOut, bClamped => bWbClamped,
                      eErr => eWbErr, bError => bWbErr, bValid => bWbOk);
fWetBulbC := fWbOut;                           // 湿球出口透传 / wet-bulb output pass-through
IF bWbErr OR (NOT bWbOk) THEN
    bWetBulbFault := TRUE;                     // 下游故障透传标志 / downstream fault pass-through flag
ELSE
    bWetBulbFault := FALSE;                    // 下游正常，信息级钳位不升格 / downstream ok, info-level clamp not escalated
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜逼近度计算与滑动窗维护（仅在使能、湿球可用、传感器不可疑时推进）
 *----------------------------------------------------------------------------*)
bActiveCalc := bEnable AND (NOT bWetBulbFault)
           AND (eState = E_DL_ApproachState.eWarmup
             OR eState = E_DL_ApproachState.eMonitor
             OR eState = E_DL_ApproachState.eStageUpPending
             OR eState = E_DL_ApproachState.eStageDownPending);  // 可计算状态判据 / computable-state predicate
bBadSensor := FALSE;                           // 传感器可疑标志逐拍重判 / suspect flag re-judged per scan
IF bActiveCalc THEN
    fApproachK := fCondOutC - fWetBulbC;       // 即时逼近度 = 出水 − 湿球 [K] / instantaneous approach = outlet minus wet bulb
    bBadSensor := fApproachK < -DL_AP_TOL;     // 热力学不可能，传感器可疑 / thermodynamically impossible, sensor suspect
    IF bBadSensor THEN
        // 可疑样本不入窗，均值保持（防污染统计）/ suspect sample not pushed, average held
    ELSE
        IF uWinFill < INT_TO_UDINT(nWinSamples) THEN
            uWinFill := uWinFill + 1;          // 窗未满：填充数递增 / window not full: fill count up
            fWinSum := fWinSum + fApproachK;   // 累加和并入新样本 / sum absorbs new sample
            afWinBuf[nWinIdx] := fApproachK;   // 写入当前槽 / write current slot
        ELSE
            fWinSum := fWinSum - afWinBuf[nWinIdx] + fApproachK;  // 窗满：换出旧值并入新值 / window full: swap out old, absorb new
            afWinBuf[nWinIdx] := fApproachK;   // 覆盖当前槽 / overwrite current slot
        END_IF
        nWinIdx := (nWinIdx + 1) MOD nWinSamples;  // 写指针环形推进，nWinSamples 已闸大于 0 / ring-advance write pointer, divisor gated
        fApproachAvgK := fWinSum / UDINT_TO_LREAL(uWinFill);  // 均值 = 和/填充数，填充数已闸大于 0 / average, fill count gated
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜决策块：带偏差实时重算（阻延挂起态也用同一决策，需求翻转即退出）
 *----------------------------------------------------------------------------*)
bNeedInc := FALSE;                             // 增台需求逐拍重判 / increase need re-judged per scan
bNeedDec := FALSE;                             // 减台需求逐拍重判 / decrease need re-judged per scan
bNoFurtherGain := FALSE;                       // 贴限标志逐拍重判，非计算态不残留 / gain-limit flag re-judged per scan
bGuardOk := (NOT bStageEverReq) OR fbStageGuard.Q;  // 守卫放行：无历史换台或最小间隔已满 / guard released
IF bActiveCalc AND (NOT bBadSensor) THEN
    IF NOT bFanCmdInit THEN
        nFanCmd := nFanRunning;                // 建议台数首拍初始化为当前运行台数 / suggestion initialized to running count
        bFanCmdInit := TRUE;                   // 初始化完成 / initialization done
    END_IF
    bNoFurtherGain := (fApproachK <= DL_AP_PHYS_FLOOR) AND (nFanRunning >= nFanTotal);  // 贴物理极限且台数已满，加机无益 / at physical floor with all fans on
    IF (fApproachAvgK - fApproachTargetK) > fApproachTolK THEN
        bNeedInc := (nFanRunning < nFanTotal) AND (NOT bNoFurtherGain);  // 偏热且有余量：增台 / too hot with headroom: increase
    ELSIF (fApproachTargetK - fApproachAvgK) > fApproachTolK THEN
        bNeedDec := (nFanRunning > DL_AP_FAN_MIN);  // 偏冷且高于冗余下限：减台 / too cold above redundancy floor: decrease
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜阻延沿检测（无条件周期调用，CLK 为本拍阻延判据，3402 沿发一次）
 *----------------------------------------------------------------------------*)
bBlockedNow := bActiveCalc AND (NOT bBadSensor) AND (bNeedInc OR bNeedDec) AND (NOT bGuardOk);  // 本拍阻延判据 / blocked predicate this scan
fbBlockTrig(CLK := bBlockedNow);               // 阻延沿检测无条件刷新 / block edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 9｜状态机：CASE 含 ELSE 兜底。bIncReq/bDecReq 为单拍脉冲：本段开头
 *       先无条件撤脉冲，状态机内按需重置位（先撤后置，不跨拍残留）。
 *----------------------------------------------------------------------------*)
bIncReq := FALSE;                              // 单拍脉冲先撤 / one-scan pulse withdrawn first
bDecReq := FALSE;                              // 单拍脉冲先撤 / one-scan pulse withdrawn first

CASE eState OF

    E_DL_ApproachState.eIdle:
        bValid := FALSE;                       // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        eErr := 16#0000_0000;                  // 待机无错 / no error in idle
        bError := FALSE;                       // 待机无故障 / no fault in idle
        bWetBulbFault := FALSE;                // 待机不透传故障相（R115：只在故障相处置）/ pass-through only in fault phase
        bNoFurtherGain := FALSE;               // 待机不判贴限 / gain-limit not judged in idle
        IF bEnable THEN
            IF bWetBulbFault THEN
                eState := E_DL_ApproachState.eFault;   // 湿球不可用直接进故障 / unusable wet bulb enters fault
                eErr := DL_CTWR_CODE_FLT_2;    // 故障级：湿球件故障透传 / fault: wet-bulb pass-through
                bError := TRUE;                // 故障级必置 bError / fault-class pairs with bError
            ELSE
                eState := E_DL_ApproachState.eWarmup;  // 使能且湿球可用进暖机 / enable with valid wet bulb enters warmup
            END_IF
        END_IF

    E_DL_ApproachState.eWarmup:
        eErr := 16#0000_0000;                  // 暖机默认无错 / warmup defaults to no error
        bError := FALSE;                       // 暖机默认无故障 / warmup defaults to no fault
        bValid := FALSE;                       // 暖机期窗口未满不可用 / unusable during warmup
        IF NOT bEnable THEN
            eState := E_DL_ApproachState.eIdle;        // 失能回待机 / disable returns to idle
        ELSIF bWetBulbFault THEN
            eState := E_DL_ApproachState.eFault;       // 下游故障进故障态 / downstream fault enters fault state
            eErr := DL_CTWR_CODE_FLT_2;        // 故障级：湿球件故障透传 / fault: wet-bulb pass-through
            bError := TRUE;                    // 故障级必置 bError / fault-class pairs with bError
        ELSIF bBadSensor THEN
            eErr := DL_CTWR_CODE_INFO_1;       // 信息级：逼近度小于 0，传感器可疑 / info: negative approach, sensor suspect
            bValid := FALSE;                   // 传感器可疑，不给建议 / suspect sensor, no advice
        ELSIF uWinFill >= INT_TO_UDINT(nWinSamples) THEN
            eState := E_DL_ApproachState.eMonitor;     // 均值窗已满进监视 / window full enters monitor
        END_IF

    E_DL_ApproachState.eMonitor:
        IF NOT bEnable THEN
            eState := E_DL_ApproachState.eIdle;        // 失能回待机 / disable returns to idle
            bValid := FALSE;                   // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        ELSIF bWetBulbFault THEN
            eState := E_DL_ApproachState.eFault;
            eErr := DL_CTWR_CODE_FLT_2;        // 故障级：湿球件故障透传 / fault: wet-bulb pass-through
            bError := TRUE;                    // 故障级必置 bError / fault-class pairs with bError
            bValid := FALSE;                   // 故障闸显式不可用 / explicit FALSE on fault gate
        ELSIF bBadSensor THEN
            eErr := DL_CTWR_CODE_INFO_1;       // 信息级：逼近度小于 0 / info: negative approach
            bError := FALSE;                   // 信息级不置 bError / info never raises bError
            bValid := FALSE;                   // 传感器可疑，不给建议（边界行为②）/ suspect sensor, no advice
        ELSE
            eErr := 16#0000_0000;              // 正常监视清码 / normal monitor clears code
            bError := FALSE;                   // 正常监视清故障 / normal monitor clears fault
            bValid := TRUE;                    // 建议数据可用 / suggestion usable
            IF bNeedInc OR bNeedDec THEN
                IF bGuardOk THEN
                    IF bNeedInc THEN
                        bIncReq := TRUE;       // 增台建议单拍脉冲 / increase pulse
                        nFanCmd := nFanRunning + 1;    // 建议台数加一 / suggested count up
                    ELSE
                        bDecReq := TRUE;       // 减台建议单拍脉冲 / decrease pulse
                        nFanCmd := nFanRunning - 1;    // 建议台数减一 / suggested count down
                    END_IF
                    bStageEverReq := TRUE;     // 记录换台历史 / record stage history
                    bGuardKick := TRUE;        // 守卫定时器断输入一拍重启 / guard timer kicked one scan
                ELSE
                    IF bNeedInc THEN
                        eState := E_DL_ApproachState.eStageUpPending;  // 增台请求被阻延挂起 / increase request blocked, pending
                    ELSE
                        eState := E_DL_ApproachState.eStageDownPending;  // 减台请求被阻延挂起 / decrease request blocked, pending
                    END_IF
                END_IF
            END_IF
        END_IF

    E_DL_ApproachState.eStageUpPending:
        IF NOT bEnable THEN
            eState := E_DL_ApproachState.eIdle;
            bValid := FALSE;                   // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        ELSIF bWetBulbFault THEN
            eState := E_DL_ApproachState.eFault;
            eErr := DL_CTWR_CODE_FLT_2;
            bError := TRUE;
            bValid := FALSE;
        ELSIF bBadSensor THEN
            eState := E_DL_ApproachState.eMonitor;     // 传感器可疑，需求作废回监视 / suspect sensor, need voided, back to monitor
            eErr := DL_CTWR_CODE_INFO_1;
            bError := FALSE;
            bValid := FALSE;
        ELSIF NOT bNeedInc THEN
            eState := E_DL_ApproachState.eMonitor;     // 需求消失退出（第二条退出条件）/ need vanished, second exit condition
            eErr := 16#0000_0000;              // 回监视清码 / clear code on return
            bValid := TRUE;                    // 回监视数据可用 / usable on return
        ELSIF fbStageGuard.Q THEN
            bIncReq := TRUE;                   // 间隔到且需求仍在：签发增台 / interval elapsed with need: issue increase
            nFanCmd := nFanRunning + 1;        // 建议台数加一 / suggested count up
            bStageEverReq := TRUE;             // 记录换台历史 / record stage history
            bGuardKick := TRUE;                // 守卫定时器断输入一拍重启 / guard timer kicked one scan
            eState := E_DL_ApproachState.eMonitor;     // 签发后回监视 / back to monitor after issue
            eErr := 16#0000_0000;              // 阻延解除清码 / clear code on release
            bValid := TRUE;                    // 数据可用 / usable
        ELSE
            bValid := TRUE;                    // 挂起期间建议数据仍可用 / suggestion usable while pending
        END_IF

    E_DL_ApproachState.eStageDownPending:
        IF NOT bEnable THEN
            eState := E_DL_ApproachState.eIdle;
            bValid := FALSE;                   // 失能闸显式不可用（R72）/ explicit FALSE on disable gate
        ELSIF bWetBulbFault THEN
            eState := E_DL_ApproachState.eFault;
            eErr := DL_CTWR_CODE_FLT_2;
            bError := TRUE;
            bValid := FALSE;
        ELSIF bBadSensor THEN
            eState := E_DL_ApproachState.eMonitor;     // 传感器可疑，需求作废回监视 / suspect sensor, need voided, back to monitor
            eErr := DL_CTWR_CODE_INFO_1;
            bError := FALSE;
            bValid := FALSE;
        ELSIF NOT bNeedDec THEN
            eState := E_DL_ApproachState.eMonitor;     // 需求消失退出（第二条退出条件）/ need vanished, second exit condition
            eErr := 16#0000_0000;              // 回监视清码 / clear code on return
            bValid := TRUE;                    // 回监视数据可用 / usable on return
        ELSIF fbStageGuard.Q THEN
            bDecReq := TRUE;                   // 间隔到且需求仍在：签发减台 / interval elapsed with need: issue decrease
            nFanCmd := nFanRunning - 1;        // 建议台数减一 / suggested count down
            bStageEverReq := TRUE;             // 记录换台历史 / record stage history
            bGuardKick := TRUE;                // 守卫定时器断输入一拍重启 / guard timer kicked one scan
            eState := E_DL_ApproachState.eMonitor;     // 签发后回监视 / back to monitor after issue
            eErr := 16#0000_0000;              // 阻延解除清码 / clear code on release
            bValid := TRUE;                    // 数据可用 / usable
        ELSE
            bValid := TRUE;                    // 挂起期间建议数据仍可用 / suggestion usable while pending
        END_IF

    ELSE
        eState := E_DL_ApproachState.eFault;   // 非法状态兜底 / illegal-state fallback
        eErr   := DL_CTWR_CODE_FLT_2;          // 兜底复用故障级槽 2（§3 未单列兜底槽，不得越段加码）/ fallback reuses fault slot 2
        bError := TRUE;                        // 故障级必置 bError / fault-class pairs with bError
        bValid := FALSE;                       // 输出不可用 / outputs unusable
        bIncReq := FALSE;                      // 脉冲全撤安全侧 / pulses withdrawn, safe side
        bDecReq := FALSE;                      // 脉冲全撤安全侧 / pulses withdrawn, safe side
END_CASE

(*------------------------------------------------------------------------------
 * 段 10｜信息级收口：阻延沿发一次 3402（不每拍刷，见边界行为⑤）
 *----------------------------------------------------------------------------*)
IF fbBlockTrig.Q THEN
    eErr := DL_CTWR_CODE_INFO_2;               // 信息级：换台请求被最小间隔阻延 / info: stage request blocked by interval
    bError := FALSE;                           // 信息级不置 bError / info never raises bError
END_IF
END_FUNCTION_BLOCK
