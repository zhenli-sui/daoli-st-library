(*
  ==================================================================
  组件名 Component  : FB_DL_TaktPaceMonitor
  分类   Category   : DL_Process
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.2
  功能   Purpose    : 节拍 / 进度落后监视（ISO 22400-2 公开口径）：bCycleDone
                      两脉冲间隔测实际节拍，EWMA（系数 fAlpha ∈ (0,1]）平滑
                      为 fTaktActS；fPaceDevPct = (实际 − 目标)/目标 × 100，
                      正值即落后（bBehind）。tEvalWindow 评估窗滚动统计窗内
                      产量对目标产量的缺口 uQtyBacklog（溢出钳位 + 信息码）。
                      首件前不出数（bValid=FALSE）；窗内零产出是合法观测——
                      缺口 = 窗内目标产量全额（分母侧显式判，不除以产量）。
  来源   Source     : self-std（ISO 22400-2 节拍/缺口公开口径，零源码复制，
                      术语与公式口径为公开标准条款）
  互引   Cross-ref  : FB_DL_CycleTimeMeasure（同族周期测量件：其 uCycleLast
                      可作本件目标节拍整定参考）；FB_DL_OeeCalculator
                      （下游 KPI 件：本件 fPaceDevPct / uQtyBacklog 可作其
                      性能类输入）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG/LREAL 四则/TIME 比较与整转）
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准件）；TIME_TO_DINT
                      属 IEC 标准类型转换
  设计偏差 Deviation: 时间基准按本库「时间注入」纪律：新增输入 fCallCycleS
                      （调用方注入扫描周期 [s]，FB_DL_CycleTimeMeasure 语义），
                      本件不读平台时刻函数；tEvalWindow 以 TIME_TO_DINT 转
                      毫秒参与闸与滚动判据（TIME 本义即 ms，三平台一致）。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 分母三闸（目标节拍 / 目标+实际差 / 窗长）显式判 +
                      溢出钳位显式 + 非有限闸 + 输出域显式
                      R5 全变量双语同行注释/R6 配置故障为电平面无状态机
                      （CASE 不适用，头注说明）/R7 rtCycle 段 0 无条件刷新
                      R8 容差与阈值常量化
  契约   Contract   : 配置故障（码 01/02）为电平面（当拍复判，非锁存）：故障
                      拍 bValid=FALSE、输出全部冻结保持、bError=TRUE；恢复
                      即恢复。失能相（bEnable=FALSE）串清账：窗内累计清零、
                      上一脉冲基准撤销、bValid=FALSE（R 失能清账条款）。
  错误码 Codes      : 01【故障级】目标节拍配置非法（≤ 0 或非有限）、评估窗
                      非法（≤ T#0MS）或扫描周期注入非法（≤ 0 / 非有限，
                      v1.0.1 将窗面/计时面并入本码，修静默降级）
                      02【故障级】平滑系数 fAlpha 域外（须 (0,1]）或非有限
                      03【信息级】缺口/窗内计数溢出钳位（饱和于 UDINT 上限）
  码位反证 Note     : 01/02 分立依据（R90）：01 在目标面与窗面、02 在平滑
                      系数面可观测，整定入口不同；03 为信息级不置 bError，
                      与 01/02 双通道可区分；窗长非法并入 01 的反证：窗长
                      与目标同为「节拍推进判据」的标定面，处置同形（冻结
                      + 拒推进），输出组合不可区分。
  验收   Acceptance : V1 稳定 60s 节拍 → fTaktActS→60，fPaceDevPct 随目标
                      ｜ V2 目标 50s 实际 60s → bBehind=TRUE ｜ V3 alpha=0
                      或 1.5 → 码 02 ｜ V4 首件前 bValid=FALSE ｜ V5 窗内
                      零产出 → 缺口 = 窗内目标产量（码面无 03）｜ V6 超长窗
                      小目标 → 缺口钳上限 + 码 03 ｜ V7 失能 → 全清账
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 4 序 10）
                      2026-11-22  v1.0.1  R66 终审就地修（1 中）：窗面/计时
                      基准面失效原走静默降级（bValid=FALSE 但不置 bError
                      不置码，R258 家族），并入码 01 电平面出口。
                      2026-11-22  v1.0.2  R67 点修（L4）：段 5 fExpectR 闸界
                      由 UDINT 域 4.294967295E9 前移至 DINT 中转域上界
                      2147483647（常量 TPM_DINT_MAX，与 TIME_TO_DINT /
                      LREAL_TO_DINT 转换链中转域 2^31−1 对齐，窗/目标比 >
                      2.1e9 s 组态下原转换链溢出可达）；M1 码 01 判式
                      （NOT _bTgtOk OR NOT _bTimeOk）维持 v1.0.1 不回退。
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_TaktPaceMonitor
VAR_INPUT
    bCycleDone   : BOOL := FALSE;    // 完工脉冲输入（上升沿计件与测节拍）[-] / the cycle done pulse, counted on the rising edge
    fTaktTargetS : LREAL := 60.0;    // 目标节拍 [s]，须 > 0 且有限 / the takt target, positive and finite
    bEnable      : BOOL := FALSE;    // 使能，FALSE 失能清账（头注契约）[-] / the enable, false clears the books
    fAlpha       : LREAL := 0.2;     // EWMA 平滑系数 [-]，有效域 (0,1] / the EWMA factor, inside zero exclusive to one inclusive
    tEvalWindow  : TIME := T#60M;    // 评估窗长 [ms]（TIME 本义 ms），须 > 0 / the evaluation window length, must be positive
    fCallCycleS  : LREAL := 0.01;    // 调用方注入扫描周期 [s]，须 > 0 / the caller injected scan cycle in seconds
END_VAR
VAR_OUTPUT
    fTaktActS    : LREAL := 0.0;     // EWMA 实际节拍 [s]（首件前保持 0 并 bValid=FALSE）/ the EWMA actual takt [s]
    fPaceDevPct  : LREAL := 0.0;     // 进度偏差 [(实际−目标)/目标×100]，正=落后 [%] / the pace deviation percent, positive is behind
    uQtyBacklog  : UDINT := UDINT#0; // 窗口产量缺口 [件]（溢出钳位）/ the window production backlog, saturated
    bBehind      : BOOL := FALSE;    // 落后指示（fPaceDevPct > 0）[-] / the behind indicator
    bValid       : BOOL := FALSE;    // 输出有效标志（首件前=FALSE）[-] / the output validity, false before the first piece
    bError       : BOOL := FALSE;    // 配置故障标志（电平面，恢复即清，R45 配对）/ the configuration fault flag, per scan level
    uErrorId     : UDINT := 16#0000_0000; // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    rtCycle      : R_TRIG;           // 完工沿实例，段 0 无条件刷新 / the cycle edge instance refreshed unconditionally
    _bHasPrev    : BOOL := FALSE;    // 上一完工脉冲基准是否存在（首件判据）[-] / the previous pulse baseline flag
    _fSinceS     : LREAL := 0.0;     // 距上一完工脉冲的累计时长 [s] / the time since the previous pulse [s]
    _bTaktInit   : BOOL := FALSE;    // EWMA 是否已初始化（首个有效间隔直赋）[-] / the EWMA seeded flag
    _fWinAccMs   : LREAL := 0.0;     // 评估窗累计时长 [ms] / the window elapsed accumulator [ms]
    _uQtyWin     : UDINT := UDINT#0; // 窗内实际产量 [件] / the in window actual quantity [pc]
    _fWinLimMs   : LREAL := 0.0;     // 评估窗长整定 [ms]（TIME 转 LREAL 缓存）/ the window limit cached from TIME [ms]
    _bTgtOk      : BOOL := FALSE;    // 本拍目标有效性 [-] / the per scan target validity
    _bAlphaOk    : BOOL := FALSE;    // 本拍平滑系数有效性 [-] / the per scan alpha validity
    _bTimeOk     : BOOL := FALSE;    // 本拍计时基准有效性 [-] / the per scan time base validity
    _nExpect     : UDINT := UDINT#0; // 窗内目标产量工作寄存器 [件] / the in window expected quantity register
    _bQtySat     : BOOL := FALSE;    // 本拍溢出钳位信息位（单拍）/ the per scan saturation info bit
    fInterval    : LREAL := 0.0;     // 当前完工间隔工作寄存器 [s] / the current interval working register [s]
    fExpectR     : LREAL := 0.0;     // 窗内目标产量实数工作寄存器 [件] / the expected quantity as real [pc]
END_VAR
VAR CONSTANT
    TPM_FIN_MAX   : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    TPM_EPS       : LREAL := 1.0E-9;   // 到达与零判容差 [无量纲] / the tolerance for zero tests
    TPM_U_MAX     : UDINT := 4294967295; // UDINT 上限哨兵 [件] / the UDINT ceiling sentinel
    TPM_DINT_MAX  : LREAL := 2147483647.0; // DINT 中转域上界 2^31-1（实数钳界，v1.0.2 前移）/ the DINT transit domain ceiling
    TPM_ERR_NONE  : UDINT := 16#0000_0000; // 无错误 [码] / no error [code]
    TPM_ERR_TGT   : UDINT := 16#0000_0001; // 码 01：目标/窗配置非法 / code 01, target or window illegal
    TPM_ERR_ALPHA : UDINT := 16#0000_0002; // 码 02：平滑系数域外 / code 02, alpha out of domain
    TPM_ERR_SAT   : UDINT := 16#0000_0003; // 码 03：缺口/计数溢出钳位（信息级）/ code 03, saturation, info level
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜沿检测无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      The edge instance refreshes unconditionally, never inside a branch
 *-----------------------------------------------------------------------------*)
rtCycle(CLK := bCycleDone);      // 完工沿 / the cycle done edge

(*------------------------------------------------------------------------------
 * 段 1｜错误码与信息位本拍预置（当前周期事实，非锁存）
 *      The error code and the info bit are per scan facts
 *-----------------------------------------------------------------------------*)
uErrorId := TPM_ERR_NONE;        // 预置无错误 / preset no error
_bQtySat := FALSE;               // 信息位复位 / reset the info bit

(*------------------------------------------------------------------------------
 * 段 2｜配置三面闸（电平面，当拍复判，码 01/02）：
 *      目标面（>0 且有限）、平滑系数面（(0,1] 且有限）、窗面（>0）与计时基准面
 *      The three configuration faces, re judged every scan
 *-----------------------------------------------------------------------------*)
_bTgtOk   := (fTaktTargetS > 0.0) AND (fTaktTargetS = fTaktTargetS)
         AND (ABS(fTaktTargetS) <= TPM_FIN_MAX);             // 目标面闸 / the target face gate
_bAlphaOk := (fAlpha > 0.0) AND (fAlpha <= 1.0) AND (fAlpha = fAlpha)
         AND (ABS(fAlpha) <= TPM_FIN_MAX);                   // 平滑系数面闸（(0,1] 域）/ the alpha face gate
_bTimeOk  := (fCallCycleS > 0.0) AND (fCallCycleS = fCallCycleS)
         AND (tEvalWindow > T#0MS);                          // 计时基准面 + 窗面闸（TIME 直接比较）/ the time base and window faces
IF (NOT _bTgtOk) OR (NOT _bTimeOk) THEN
    bError := TRUE;                  // 故障标志（R45 配对，v1.0.1：窗/计时面并入码 01 不再静默）/ the fault flag
    uErrorId := TPM_ERR_TGT;         // 码 01（目标/窗/计时基准面）/ code 01
ELSIF NOT _bAlphaOk THEN
    bError := TRUE;                  // 码 02 / code 02
    uErrorId := TPM_ERR_ALPHA;
ELSE
    bError := FALSE;                 // 配置恢复即清（电平面契约）/ cleared when the configuration recovers
END_IF
IF NOT (_bTgtOk AND _bAlphaOk AND _bTimeOk) THEN
    bValid := FALSE;                 // 任一配置面失效即不出数 / no output while any face fails
    RETURN;                          // 输出全部冻结保持（头注契约）/ all outputs frozen
END_IF
_fWinLimMs := DINT_TO_LREAL(TIME_TO_DINT(tEvalWindow));  // 窗长转毫秒缓存（TIME 本义 ms）[ms] / the window limit in ms

(*------------------------------------------------------------------------------
 * 段 3｜失能相串清账（R 失能清账）：窗累计清零、脉冲基准撤销、bValid 撤销
 *      The disable phase clears the books, the outputs hold frozen
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    bValid := FALSE;                 // 失能不出数 / no output while disabled
    _bHasPrev := FALSE;              // 撤销脉冲基准（重新使能从下一脉冲起测）/ withdraw the pulse baseline
    _fSinceS := 0.0;                 // 间隔累计清零 / clear the interval accumulator
    _fWinAccMs := 0.0;               // 窗累计清零 / clear the window accumulator
    _uQtyWin := UDINT#0;             // 窗内计数清零 / clear the window count
    _bTaktInit := FALSE;             // EWMA 重新种子（首件语义重置）/ re seed the EWMA
    RETURN;                          // 输出冻结保持 / outputs frozen
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜推进与计件：间隔累计 + 完工沿处理（首件只立基准不出数）
 *      The advance and counting, the first pulse only arms the baseline
 *-----------------------------------------------------------------------------*)
_fSinceS := _fSinceS + fCallCycleS;      // 间隔累计 [s]（推进判据与配置闸不同源）/ accumulate the interval
IF rtCycle.Q THEN                        // 完工沿 / the cycle done edge
    IF _bHasPrev THEN                    // 有基准才出间隔（首件不出数）/ an interval only with a baseline
        fInterval := _fSinceS;           // 取完工间隔 [s] / take the interval
        IF (fInterval <> fInterval) OR (ABS(fInterval) > TPM_FIN_MAX) THEN
            _bQtySat := TRUE;            // 非有限间隔弃用并记信息位（防御，结构性罕见）/ a non finite interval is dropped, marked
        ELSE
            IF NOT _bTaktInit THEN
                fTaktActS := fInterval;  // EWMA 首个有效样本直赋（禁 0 当种子）/ seed the EWMA directly
                _bTaktInit := TRUE;
            ELSE
                fTaktActS := fTaktActS + fAlpha * (fInterval - fTaktActS);  // EWMA 递推 [s] / the EWMA recursion
            END_IF
            bValid := TRUE;              // 首个有效间隔后开始出数 / live after the first valid interval
        END_IF
    ELSE
        bValid := FALSE;                 // 首件前不出数（头注契约）/ no output before the first piece
    END_IF
    _bHasPrev := TRUE;                   // 立脉冲基准 / arm the baseline
    _fSinceS := 0.0;                     // 间隔累计清零 / clear the interval accumulator
    IF _uQtyWin < TPM_U_MAX THEN         // 窗内计数溢出钳位（先闸后加）/ the count saturation clamp
        _uQtyWin := _uQtyWin + UDINT#1;  // 窗内计件 [件] / count the piece in window
    ELSE
        _bQtySat := TRUE;                // 计数饱和记信息位 / mark the saturation
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜评估窗滚动：窗满结算缺口（分母侧显式判：目标面已闸，产量不进分母）
 *      The window roll, the backlog settlement, the quantity never enters a denominator
 *-----------------------------------------------------------------------------*)
_fWinAccMs := _fWinAccMs + fCallCycleS * 1000.0;  // 窗累计 [ms] / accumulate the window
IF _fWinAccMs >= _fWinLimMs THEN         // 窗满滚动判据 / the roll criterion
    fExpectR := (_fWinLimMs / 1000.0) / fTaktTargetS;  // 窗内目标产量 [件]（分母 = 目标，已闸 > 0）/ the expected quantity, the denominator is the gated target
    IF (fExpectR <> fExpectR) OR (fExpectR >= TPM_DINT_MAX) THEN
        _nExpect := TPM_U_MAX;           // 目标产量超 DINT 中转域（v1.0.2 前移至 2^31-1）钳上限 + 信息码（取整前实数上限兜底）/ clamp the expectation to the ceiling
        _bQtySat := TRUE;
    ELSE
        _nExpect := DINT_TO_UDINT(LREAL_TO_DINT(TRUNC(fExpectR)));  // 实数截断为件数（标准转换链，向下取整口径）/ truncate the expectation, standard chain
    END_IF
    IF _nExpect > _uQtyWin THEN
        uQtyBacklog := _nExpect - _uQtyWin;  // 缺口 = 目标 − 实际（无除法面）/ the backlog is the shortfall
    ELSE
        uQtyBacklog := UDINT#0;          // 超产或持平缺口归零（钳位显式）/ no shortfall clamps to zero
    END_IF
    _fWinAccMs := _fWinAccMs - _fWinLimMs;  // 窗基准滚动（保留余量，防长周期漂移）/ roll the window keeping the remainder
    _uQtyWin := UDINT#0;                 // 窗内计数清零 / clear the window count
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜进度偏差与落后判定（分母 = 目标节拍，已闸 > 0；容差判零禁浮点判等）
 *      The pace deviation and the behind verdict, the denominator already gated
 *-----------------------------------------------------------------------------*)
IF bValid THEN                           // 首件前不刷新偏差（输出语义一致）/ no deviation before the first piece
    fPaceDevPct := (fTaktActS - fTaktTargetS) / fTaktTargetS * 100.0;  // 偏差 [%] / the deviation percent
    IF fPaceDevPct > TPM_EPS THEN
        bBehind := TRUE;                 // 正偏差判落后（容差判零）/ a positive deviation means behind
    ELSE
        bBehind := FALSE;                // 非正偏差不落后 / not behind otherwise
    END_IF
END_IF
IF _bQtySat THEN
    uErrorId := TPM_ERR_SAT;             // 信息级码（不置 bError，功能不受影响）/ the info code, no fault flag
END_IF
END_FUNCTION_BLOCK
