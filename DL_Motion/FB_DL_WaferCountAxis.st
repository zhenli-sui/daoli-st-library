//==============================================================================
// 功能块：FB_DL_WaferCountAxis ｜ 中文名称：晶圆计数轴（编码器分频 + 片位同步）
// 所属子库：DL_Motion ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：编码器脉冲分频晶圆计数——按脉冲/片分频比累计计片，片位同步
//           单拍脉冲输出（EAP 对账用），滑动窗估算节拍率 [片/min]。
// 开源溯源 (Origin)：道莅原创实现（参考半导体 EAP 对账与计数轴工程惯例 分类与参数域）
// 单位表：脉冲[—] / 分频比[脉冲/片] / 计数[片] / 节拍率[片/min] / 窗[ms]
// 错误码表：16#0004_01DF 信息级（计数饱和 4294967295，不回绕，不置
//           bError）/ 16#0004_01E0 预留禁用（不得挪用）/ 16#0004_02F9
//           故障级（分频比为 0，除零前置闸，置 bError）/ 16#0004_02FA
//           预留禁用（不得挪用）/ 16#0004_02FB 故障级兜底（置 bError）
// 状态机：N/A（分频计数 + 窗口估算为电平逻辑，无相位状态机）
// 边界行为：① uPulsesPerWafer = 0 → 故障 02F9（除零前置闸，计数冻结）；
//           ② 计数饱和 4294967295 + 信息 01DF，不回绕；③ bResetCount
//           优先级最高（同拍清分频累加器、窗计数与总计数）；④ 节拍率窗
//           tRateWindow <= 0 → 斜率走窗口为 0 的构造路径保护（估算率
//           冻结 0，不除零）；⑤ R_TRIG 首部无条件刷新（R40）。
// 依赖纪律：Motion 不得引用任何其他 DL_ 子库（R22 纪律延续）——本件仅用
//           Standard.library（TON/R_TRIG），未使用同库 I_DL_MotionAxis
//           （纯脉冲计数无需轴接口，头注释声明此设计取舍）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 半导体 P1 §369）
//==============================================================================

FUNCTION_BLOCK FB_DL_WaferCountAxis
VAR_INPUT
    bEncPulse       : BOOL;                 // 编码器脉冲输入 [—] / Encoder pulse input
    uPulsesPerWafer : UINT := 100;          // 分频比 [脉冲/片]，须 > 0 / Divider ratio [pulses per wafer], must be > 0
    bCountEnable    : BOOL;                 // 计数使能 [—] / Count enable
    bResetCount     : BOOL;                 // 计数复位 [—]，优先级最高 / Count reset, highest priority
END_VAR
VAR_OUTPUT
    uWaferCount     : UDINT;                // 晶圆计数 [片]，饱和 4294967295 不回绕 / Wafer count [pieces], saturated without wrap
    bWaferIndexPulse: BOOL;                 // 片位同步单拍脉冲 [—] / Wafer-index one-scan pulse
    fEstRate        : LREAL;                // 估算节拍率 [片/min] / Estimated rate [pieces/min]
    eErr            : UDINT;                // 错误码，0 = 无错 / Error code, 0 = no error
    bError          : BOOL;                 // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                 // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    rtEnc           : R_TRIG;               // 编码器脉冲上升沿，段 6 无条件刷新 / Encoder pulse rising edge
    fbRateWin       : TON;                  // 节拍率估算窗，段 6 无条件刷新 [ms] / Rate estimation window
    _uPulseAcc      : UINT;                 // 分频脉冲累加器 [脉冲] / Divider pulse accumulator [pulses]
    _uWinCount      : UINT;                 // 窗内计片数 [片] / Wafer count within the window [pieces]
    _fWinMinutes    : LREAL;                // 估算窗时长 [min] / Window duration [min]
    _bInit          : BOOL := FALSE;        // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bDivZero       : BOOL;                 // 分频比为 0 锁存 / Zero-divider latch
    _bSaturated     : BOOL;                 // 计数饱和当拍标志 / Saturation flag of this scan
    _bIdxPulse      : BOOL;                 // 片位脉冲单拍标志 / One-scan index pulse flag
END_VAR
VAR CONSTANT
    DL_WC_CNT_MAX   : UDINT := 4294967295;  // 计数饱和上限 [片] / Counter saturation ceiling [pieces]
    DL_WC_RATE_WIN  : TIME  := T#10S;       // 节拍率估算窗 [ms] / Rate estimation window [ms]
    DL_WC_MS_PER_MIN: LREAL := 60000.0;     // 毫秒 → 分钟换算系数 [ms/min] / Millisecond-to-minute factor [ms/min]
    DL_WC_INF       : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零（R25 第一律：只置必销）
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bWaferIndexPulse := FALSE;                  // 片位脉冲预清零 / Index pulse pre-cleared
fEstRate         := 0.0;                    // 节拍率预置零 / Rate preset zero
eErr             := 16#0000_0000;           // 错误码每拍重算 / Error code recomputed
bError           := FALSE;                  // 故障标志每拍重算 / Fault flag recomputed
bValid           := FALSE;                  // 可用标志每拍重算 / Usable flag recomputed
_bSaturated      := FALSE;                  // 饱和标志预清零 / Saturation flag pre-cleared
_bIdxPulse       := FALSE;                  // 片位暂存预清零 / Index staging pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    uWaferCount := 0;                       // 计数清零 / Counter cleared
    _uPulseAcc  := 0;                       // 分频累加器清零 / Accumulator cleared
    _uWinCount  := 0;                       // 窗计数清零 / Window counter cleared
    _bDivZero   := FALSE;                   // 除零锁存清零 / Zero-divider latch cleared
    _bInit      := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜R_TRIG 与估算窗无条件刷新（R40：CASE 之外每拍必调）
 *      R_TRIG and the rate window refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
rtEnc(CLK := bEncPulse);                    // 编码器脉冲上升沿 / Encoder pulse rising edge
fbRateWin(IN := bCountEnable AND (NOT _bDivZero), PT := DL_WC_RATE_WIN); // 节拍率估算窗 / Rate estimation window

(*------------------------------------------------------------------------------
 * 段 4｜复位优先级最高：清全部累计量
 *      Reset has the highest priority, clears every accumulator
 *-----------------------------------------------------------------------------*)
IF bResetCount THEN
    uWaferCount := 0;                       // 总计数清零 / Counter cleared
    _uPulseAcc  := 0;                       // 分频累加器清零 / Accumulator cleared
    _uWinCount  := 0;                       // 窗计数清零 / Window counter cleared
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜分频计数：使能 + 沿有效时累加，达分频比进片（计数饱和不回绕）
 *      Divider counting with saturation guard
 *-----------------------------------------------------------------------------*)
IF bCountEnable AND (NOT _bDivZero) AND rtEnc.Q AND (NOT bResetCount) THEN
    IF _uPulseAcc + 1 >= uPulsesPerWafer THEN
        _uPulseAcc := 0;                    // 分频累加器归零 / Accumulator rolled over
        IF uWaferCount < DL_WC_CNT_MAX THEN
            uWaferCount := uWaferCount + 1; // 计片递增 / Wafer count increment
            _uWinCount  := _uWinCount + 1;  // 窗计数递增 / Window counter increment
            _bIdxPulse := TRUE;             // 片位脉冲单拍置位（段 1 预清，只置必销） / One-scan index pulse
        ELSE
            _bSaturated := TRUE;            // 计数饱和声明 / Saturation declared
        END_IF
    ELSE
        _uPulseAcc := _uPulseAcc + 1;       // 分频累加 / Accumulator increment
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜节拍率估算：窗满按窗计片换算 [片/min]（窗 <= 0 走构造路径冻结）
 *      Rate estimation with the zero-window construction-path guard
 *-----------------------------------------------------------------------------*)
_fWinMinutes := TIME_TO_DINT(DL_WC_RATE_WIN) / DL_WC_MS_PER_MIN; // 窗时长 [min] / Window duration [min]
IF fbRateWin.Q AND (_fWinMinutes > 0.0) THEN
    fEstRate := UINT_TO_LREAL(_uWinCount) / _fWinMinutes; // 节拍率 [片/min]（标准类型转换，零方言） / Estimated rate [pieces/min], standard conversion
    _uWinCount := 0;                        // 窗计数清零重开 / Window counter cleared and restarted
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜组态闸与码位出口
 *      Configuration gate and the code outlet
 *-----------------------------------------------------------------------------*)
IF uPulsesPerWafer = 0 THEN
    _bDivZero := TRUE;                      // 除零前置闸锁存（计数冻结） / Zero-divider latch, counting frozen
END_IF
bWaferIndexPulse := _bIdxPulse;             // 片位脉冲出口 / Index pulse outlet

IF _bDivZero THEN
    eErr   := 16#0004_02F9;                 // 故障级：分频比为 0 / Fault: zero divider ratio
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF _bSaturated THEN
    eErr := 16#0004_01DF;                   // 信息级：计数饱和不回绕 / Info: counter saturated without wrap
    bValid := TRUE;                         // 输出可用 / Outputs usable
ELSE
    bValid := bCountEnable;                 // 使能且正常：输出可用 / Outputs usable when enabled
END_IF
END_FUNCTION_BLOCK
