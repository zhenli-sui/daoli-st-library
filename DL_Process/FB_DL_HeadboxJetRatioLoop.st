(*
  DL Factory R84 | FB_DL_HeadboxJetRatioLoop
  功能：流浆箱唇口喷射比闭环：由浆料流量、浆浓、幅宽与唇口开度换算浆速并求喷射比，按喷射比偏差与五点横幅定量偏差加权均值出 PI 唇口开度指令，限位时冻结积分并出限位位，网速或开度为零时不出比值保持上一有效指令。
  开源溯源：无（clean-room 自研，依据公开工艺公式与安全设计惯例，来源=行业通用公式+工程实践，许可证=MIT，借鉴点=公式结构与联锁分层）
  规则：R1-R16 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG、LREAL、ENUM、CASE）
  边界一：只出唇口开度指令与限位位，不驱动唇口伺服、不控上浆泵、不改横幅执行器（属主边界，执行由下层 PRG 完成）。
  边界二：浆速换算——浆速 [m/min]＝浆料流量 [L/min] ÷（唇口开度 [mm] × 幅宽 [m]），
          推导：流量 [L/min]＝0.001 [m³/L] × 数值，面积 [m²]＝0.001 [m/mm] × 开度 × 幅宽，
          两者相除后两个 0.001 相消，故公式不含任何折算系数（量纲自洽，写死为字面量形式）。
  边界三：喷射比＝浆速 ÷ 网速，为使浆速与网速同速，目标喷射比 fJetRatioSp 默认 1.00（唇口射流与网速等速为常规稳态）。
  边界四：横幅定量偏差五点加权——权重为三角权 1／2／3／2／1（中心权重三、两侧递减），权数和为常量 9；
          权重按 3 − ABS(i − 2) 逐点算术生成，不建常量权重表（避免定长数组常量在部分平台不被接受）。
  边界五：控制律为位置式 PI——开度指令＝基准开度 ＋ Kp·e ＋ 积分项，积分项在限位或相位不在调节窗口时冻结（抗饱和）；
          基准开度在进入稳定相时锁存为当时的开度指令（复位与首扫时该指令以开度反馈为初值），故积分项归零时指令自然回到基准，无扰切换。
  边界六：无效拍语义——网速或当前开度为零（或非有限）→ 不计算喷射比、xValid 出假、开度指令保持上一有效值，
          相位与积分均不推进（不除零、不外推）。
  量纲自检：喷射比 [-]＝浆速 [m/min] ÷ 网速 [m/min]；开度 [mm]＝fSliceMm、fSliceCmd、上下限；
          流量 [L/min]＝fStockFlowLpm；浓度 [百分数]＝fConsPct 与 fConsNomPct；幅宽 [m]＝fWidthM；
          横幅偏差 [g/m²]＝afProfileDev 五点；增益 Kp 单位 [mm/比值]、Ki 单位 [mm/比值·拍]。
  码表：本件全部码位为信息级（2901 组态越域、2902 入参非有限、2903 网速或开度为零、2904 开度到达限位、
        2905 非法相位）；信息级码每拍重算且不置 bError；限位由 xAtLimit 电平位表达，故本件无 bError 出口（R187）。
  输出契约：fSliceCmd 在上下限之间恒成立（域内硬钳）；xAtLimit 为电平位（限位相成立期间为真）；
          fJetRatio 在无有效比值的拍保持上一有效值；fProfileMean 为五点加权横幅偏差 [g/m²]。
  修订记录：2026-11-24 v1.0.0 R84 首版（批 R84 · 序号 44）
*)

TYPE E_DL_HjrState :
(
    eIdle      := 0, // 空闲：等使能与输入有效 / idle, waiting for the enable and valid inputs
    eStabilize := 10, // 稳定：等稳定窗到期或偏差入死区 / stabilising, waiting for the window or the dead band
    eRegulate  := 20, // 调节：闭环出开度指令 / regulating, the loop drives the slice
    eLimitHold := 30  // 限位保持：开度到限，冻结积分 / limit hold, the slice is on a limit and the integral is frozen
);
END_TYPE

TYPE E_DL_HjrCause :
(
    eNone      := 0, // 无成因 / no cause
    eCfgBad    := 1, // 组态越域（信息级 2901）/ the configuration is out of domain, info grade 2901
    eNotFinite := 2, // 入参非有限（信息级 2902）/ a non-finite input, info grade 2902
    eNoRatio   := 3, // 网速或开度为零（信息级 2903）/ the wire speed or the slice is zero, info grade 2903
    eAtLimit   := 4, // 开度到达限位（信息级 2904）/ the slice reached a limit, info grade 2904
    ePhaseBad  := 5  // 非法相位（信息级 2905）/ an illegal phase, info grade 2905
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeadboxJetRatioLoop
VAR CONSTANT
    DL_HJR_KP          : LREAL := 0.30;    // 比例增益 [mm/比值] / the proportional gain [mm per ratio]
    DL_HJR_KI          : LREAL := 0.02;    // 积分增益（每拍）[mm/比值·拍] / the integral gain per scan [mm per ratio]
    DL_HJR_INT_MAX     : LREAL := 0.60;    // 积分项限幅 [mm] / the integral term limit [mm]
    DL_HJR_STEP_MM     : LREAL := 0.05;    // 单拍开度变化限幅 [mm] / the per scan slice step limit [mm]
    DL_HJR_DEADBAND    : LREAL := 0.01;    // 喷射比死区 [比值] / the jet ratio dead band [ratio]
    DL_HJR_PROF_GAIN   : LREAL := 0.05;    // 横幅偏差折算增益 [比值/(g/m²)] / the profile deviation gain [ratio per g/m2]
    DL_HJR_CONS_GAIN   : LREAL := 0.50;    // 浆浓前馈增益 [mm/倍] / the consistency feed forward gain [mm per times]
    DL_HJR_LIMIT_BAND  : LREAL := 0.001;   // 限位判定带 [mm] / the limit detection band [mm]
    DL_HJR_W_CENTER    : INT := 3;         // 横幅权重基数（中心权重）[-] / the centre weight of the profile weights [-]
    DL_HJR_W_LAST      : INT := 4;         // 横幅最后一点下标 [-] / the last profile subscript [-]
    DL_HJR_EPS         : LREAL := 1.0E-9;  // 除法零闸与零判定门限 [-] / the division guard and zero test threshold [-]
END_VAR
VAR_INPUT
    bEnable        : BOOL := TRUE;      // 使能，失能回空闲且冻结积分 [-] / enable, a disable returns to idle and freezes the integral
    bReset         : BOOL := FALSE;     // 复位上升沿清积分与基准开度 [-] / reset rising edge clears the integral and the base
    fStockFlowLpm  : LREAL := 6000.0;   // 浆料流量 [L/min] / the stock flow [L/min]
    fConsPct       : LREAL := 3.20;     // 浆浓（实测）[百分数] / the measured consistency [percent]
    fConsNomPct    : LREAL := 3.20;     // 浆浓设计值（前馈基准）[百分数] / the design consistency as the feed forward base [percent]
    fWireSpeedMpm  : LREAL := 800.0;    // 网速 [m/min] / the wire speed [m/min]
    fSliceMm       : LREAL := 9.00;     // 唇口开度反馈 [mm] / the slice opening feedback [mm]
    fSliceMinMm    : LREAL := 3.00;     // 唇口开度下限 [mm] / the slice lower limit [mm]
    fSliceMaxMm    : LREAL := 20.0;     // 唇口开度上限 [mm] / the slice upper limit [mm]
    fWidthM        : LREAL := 6.00;     // 成形幅宽 [m] / the forming width [m]
    fJetRatioSp    : LREAL := 1.00;     // 目标喷射比（默认等速）[比值] / the jet ratio setpoint, unity by default [ratio]
    afProfileDev   : ARRAY[0..4] OF LREAL := [0.0, 0.0, 0.0, 0.0, 0.0]; // 横幅五点定量偏差 [g/m²] / the five point basis weight deviations [g/m2]
    tStab          : TIME := T#10S;     // 稳定窗（进稳定相后计时）[毫秒] / the stabilising window [ms]
END_VAR
VAR_OUTPUT
    fSliceCmd      : LREAL := 0.0;  // 唇口开度指令 [mm] / the slice opening command [mm]
    fJetRatio      : LREAL := 1.0;  // 实测喷射比（无有效值时保持）[比值] / the measured jet ratio, held when invalid [ratio]
    fStockSpeedMpm : LREAL := 0.0;  // 换算浆速 [m/min] / the converted stock speed [m/min]
    fProfileMean   : LREAL := 0.0;  // 横幅五点加权偏差均值 [g/m²] / the weighted profile deviation mean [g/m2]
    fRatioErr      : LREAL := 0.0;  // 喷射比偏差（含前馈与横幅修正）[比值] / the ratio error including both corrections [ratio]
    fSliceStep     : LREAL := 0.0;  // 本拍开度增量（限幅后）[mm] / the slice step of this scan after limiting [mm]
    xAtLimit       : BOOL := FALSE; // 开度到达限位（电平位）[-] / the slice reached a limit
    eState         : E_DL_HjrState := E_DL_HjrState.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    iErrCode       : INT := 0;      // 信息级码（每拍重算，非锁存）[码] / the info grade code, recomputed every scan [code]
    xValid         : BOOL := FALSE; // 本拍输入可信且比值可算 [-] / the inputs are trustworthy and the ratio is computable
END_VAR
VAR
    rtReset    : R_TRIG; // 复位沿实例（无量纲）[-] / the reset edge refreshed unconditionally
    tonStab    : TON;    // 稳定窗实例（无量纲）[-] / the stabilising window gated by eStabilize
    _eState    : E_DL_HjrState := E_DL_HjrState.eIdle; // 内部相位（枚举，无量纲）[-] / the internal phase, the only CASE target
    _i         : INT := 0;      // 横幅遍历下标 [-] / the profile traversal index
    _iErrTmp   : INT := 0;      // 本拍信息级码暂存 [码] / the scan info code scratch [code]
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bScalarFin: BOOL := FALSE; // 标量浮点入参有限 [-] / the scalar floating inputs are finite
    _bProfFin  : BOOL := FALSE; // 横幅五点数组逐点有限 [-] / every profile point is finite
    _bFinOk    : BOOL := FALSE; // 标量与数组有限之合取 [-] / the conjunction of the scalar and array gates
    _bCfgOk    : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside its domain
    _bRatioOk  : BOOL := FALSE; // 网速与开度非零（比值可算）[-] / the wire speed and the slice are non zero
    _bAtLimit  : BOOL := FALSE; // 开度到达限位判据 [-] / the slice limit verdict
    _bFreeze   : BOOL := FALSE; // 积分冻结判据 [-] / the integral freeze verdict
    _fStockVel : LREAL := 0.0;  // 换算浆速（本拍）[m/min] / the converted stock speed of this scan [m/min]
    _fRatio    : LREAL := 1.0;  // 喷射比（本拍计算）[比值] / the jet ratio of this scan [ratio]
    _fRatioLst : LREAL := 1.0;  // 上一有效喷射比（保持槽）[比值] / the last valid jet ratio, a hold slot [ratio]
    _fWSum     : LREAL := 0.0;  // 横幅权重和 [-] / the sum of the profile weights
    _fDevSum   : LREAL := 0.0;  // 横幅加权偏差和 [g/m²] / the weighted profile deviation sum [g/m2]
    _fW        : LREAL := 0.0;  // 单点权重 [-] / the single point weight
    _fProfMean : LREAL := 0.0;  // 横幅加权均值 [g/m²] / the weighted profile mean [g/m2]
    _fConsFact : LREAL := 1.0;  // 浆浓与设计值之比（前馈）[倍] / the consistency ratio for the feed forward [times]
    _fErr      : LREAL := 0.0;  // 喷射比偏差（原始）[比值] / the raw ratio error [ratio]
    _fErrCtl   : LREAL := 0.0;  // 加前馈与横幅修正后的控制偏差 [比值] / the control error with both corrections [ratio]
    _fInt      : LREAL := 0.0;  // 积分项（位置式，限幅）[mm] / the integral term of the positional form [mm]
    _fBase     : LREAL := 0.0;  // 基准开度（进稳定相时锁存）[mm] / the base opening latched when stabilising starts [mm]
    _fPiOut    : LREAL := 0.0;  // PI 输出量 [mm] / the PI output [mm]
    _fTarget   : LREAL := 0.0;  // 目标开度（未限幅）[mm] / the target opening before limiting [mm]
    _fStep     : LREAL := 0.0;  // 本拍开度增量（限幅后）[mm] / the step of this scan after limiting [mm]
    _fCmd      : LREAL := 0.0;  // 开度指令累加（唯一写入点）[mm] / the command accumulator, the only write point [mm]
    _fCmdLst   : LREAL := 0.0;  // 上一有效开度指令（无效拍保持）[mm] / the last valid command held on an invalid scan [mm]
    _tStab     : TIME := T#1S;  // 稳定窗实参（钳定后）[毫秒] / the stabilising window passed to the timer [ms]
END_VAR
// 段 0｜出口预置：全部出口先赋安全侧值，任何路径不留未初始化输出
xValid := FALSE; // 有效性预置假 / validity preset false
xAtLimit := FALSE; // 限位位预置假 / the limit bit preset false
fSliceCmd := _fCmdLst; // 开度指令回放上一有效值（无效拍保持，边界六）/ replay the last valid command
fJetRatio := _fRatioLst; // 喷射比回放上一有效值 / replay the last valid ratio
fStockSpeedMpm := 0.0; // 浆速预置零 / the stock speed preset zero
fProfileMean := 0.0; // 横幅均值预置零 / the profile mean preset zero
fRatioErr := 0.0; // 偏差预置零 / the error preset zero
fSliceStep := 0.0; // 开度增量预置零（不调节拍不出量）/ the step preset zero
eState := _eState; // 相位回放 / replay the phase
iErrCode := 0; // 信息级码预置零（本拍重算）/ the info code preset zero
_iErrTmp := 0; // 单拍码暂存预清（FB32-1）/ preclear the code scratch
_fStep := 0.0; // 单拍增量预清 / preclear the step
// 段 1｜非有限闸（标量）：NaN 自反比较、Inf 差值自减双判，逐项枚举九个标量浮点入参（R79、R272）
_bScalarFin := (fStockFlowLpm = fStockFlowLpm) AND ((fStockFlowLpm - fStockFlowLpm) = (fStockFlowLpm - fStockFlowLpm)) // 浆料流量有限 [-] / the stock flow is finite
    AND (fConsPct = fConsPct) AND ((fConsPct - fConsPct) = (fConsPct - fConsPct)) // 浆浓有限 [-] / the consistency is finite
    AND (fConsNomPct = fConsNomPct) AND ((fConsNomPct - fConsNomPct) = (fConsNomPct - fConsNomPct)) // 设计浆浓有限 [-] / the design consistency is finite
    AND (fWireSpeedMpm = fWireSpeedMpm) AND ((fWireSpeedMpm - fWireSpeedMpm) = (fWireSpeedMpm - fWireSpeedMpm)) // 网速有限 [-] / the wire speed is finite
    AND (fSliceMm = fSliceMm) AND ((fSliceMm - fSliceMm) = (fSliceMm - fSliceMm)) // 开度反馈有限 [-] / the slice feedback is finite
    AND (fSliceMinMm = fSliceMinMm) AND ((fSliceMinMm - fSliceMinMm) = (fSliceMinMm - fSliceMinMm)) // 开度下限有限 [-] / the slice floor is finite
    AND (fSliceMaxMm = fSliceMaxMm) AND ((fSliceMaxMm - fSliceMaxMm) = (fSliceMaxMm - fSliceMaxMm)) // 开度上限有限 [-] / the slice ceiling is finite
    AND (fWidthM = fWidthM) AND ((fWidthM - fWidthM) = (fWidthM - fWidthM)) // 幅宽有限 [-] / the width is finite
    AND (fJetRatioSp = fJetRatioSp) AND ((fJetRatioSp - fJetRatioSp) = (fJetRatioSp - fJetRatioSp)); // 目标喷射比有限 [-] / the setpoint is finite
// 段 2｜非有限闸（横幅数组）：逐点枚举，漏判单点会污染加权均值（R151）
_bProfFin := TRUE; // 逐点闸初值真 / the per point gate starts true
FOR _i := 0 TO (DL_HJR_W_LAST) DO // 定长字面界 0..4（禁动态上下界，E037）/ the literal subscript range
    IF NOT (afProfileDev[_i] = afProfileDev[_i]) THEN _bProfFin := FALSE; END_IF // 该点 NaN 判否 / the point is NaN
    IF (afProfileDev[_i] - afProfileDev[_i]) <> (afProfileDev[_i] - afProfileDev[_i]) THEN _bProfFin := FALSE; END_IF // 该点 Inf 判否 / the point is infinite
END_FOR
_bFinOk := _bScalarFin AND _bProfFin; // 标量与数组有限之合取 / the conjunction of the scalar and array gates
// 段 3｜组态域闸：开度上下限次序、幅宽与设计浆浓正定、稳定窗正定（R151）
_bCfgOk := (fSliceMinMm > 0.0) AND (fSliceMaxMm > fSliceMinMm) // 开度域闸（上限严格大于下限）[-] / the slice domain gate
    AND (fWidthM > DL_HJR_EPS) AND (fConsNomPct > DL_HJR_EPS) // 幅宽与设计浆浓非零 [-] / the width and the design consistency are non zero
    AND (fJetRatioSp > DL_HJR_EPS) AND (tStab > T#0S); // 目标比值与稳定窗域闸 [-] / the setpoint and the window gates
_tStab := tStab; // 稳定窗一级回退：取引脚值 [ms] / level one fallback, take the pin value
IF _tStab <= T#0S THEN _tStab := T#1S; END_IF // 稳定窗二级回退：按有效域钳定 / level two, clamp into the valid domain
IF NOT _bFinOk THEN _iErrTmp := 2902; ELSIF NOT _bCfgOk THEN _iErrTmp := 2901; END_IF // 信息级码分派（有限 → 组态）/ the info code dispatch
// 段 4｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志 / the first scan flag
    _fInt := 0.0; // 作用域一：清积分项（唯一清除边，R188）/ scope one, clear the integral term
    _fCmd := fSliceMm; // 作用域二：指令基准取当前反馈 [mm] / scope two, the command base is the feedback [mm]
    IF _fCmd < fSliceMinMm THEN _fCmd := fSliceMinMm; END_IF // 基准下限钳定 / clamp the base low
    IF _fCmd > fSliceMaxMm THEN _fCmd := fSliceMaxMm; END_IF // 基准上限钳定 / clamp the base high
    _fCmdLst := _fCmd; // 作用域二：上一有效指令同步 / scope two, sync the last valid command
    _fBase := _fCmd; // 作用域二：基准开度同步 / scope two, sync the base opening
    _fRatioLst := fJetRatioSp; // 作用域三：喷射比保持槽预置为目标值 / scope three, preset the ratio hold slot
    _eState := E_DL_HjrState.eIdle; // 作用域一：迁回空闲相 / scope one, migrate to idle
END_IF
// 段 5｜定时器与沿检测无条件周期刷新（R7），稳定窗只串 eStabilize 相
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonStab(IN := (_eState = E_DL_HjrState.eStabilize) AND _bFinOk, PT := _tStab); // 稳定窗，只串稳定相 / the window gated by the stabilise phase
// 段 6｜横幅五点加权均值：三角权 1/2/3/2/1，权数和为常量九，除零结构性排除
_fWSum := 0.0; _fDevSum := 0.0; // 权重和与加权和清零 / clear the weight sum and the weighted sum
FOR _i := 0 TO (DL_HJR_W_LAST) DO // 定长字面界 0..4 / the literal subscript range
    _fW := INT_TO_LREAL(DL_HJR_W_CENTER - ABS(_i - 2)); // 三角权重 1/2/3/2/1 [-] / the triangular weight
    _fWSum := _fWSum + _fW; // 权重累加 / accumulate the weight
    _fDevSum := _fDevSum + (_fW * afProfileDev[_i]); // 加权偏差累加 [g/m²] / accumulate the weighted deviation
END_FOR
IF _fWSum > DL_HJR_EPS THEN // 权重和零闸（常量九，结构性恒真，防御性保留）/ the weight sum guard
    _fProfMean := _fDevSum / _fWSum; // 加权均值 [g/m²] / the weighted mean [g/m2]
ELSE // 权重和非法 / an illegal weight sum
    _fProfMean := 0.0; // 均值出零（不放大修正）/ the mean goes to zero
END_IF
IF NOT (_fProfMean = _fProfMean) THEN _fProfMean := 0.0; END_IF // 均值 NaN 兜底 / the NaN fallback
IF (_fProfMean - _fProfMean) <> (_fProfMean - _fProfMean) THEN _fProfMean := 0.0; END_IF // 均值 Inf 兜底 / the Inf fallback
// 段 7｜浆速与喷射比：网速或开度为零不计算比值，保持上一有效值（边界六、R4）
_bRatioOk := (ABS(fWireSpeedMpm) > DL_HJR_EPS) AND (ABS(fSliceMm) > DL_HJR_EPS) AND (ABS(fWidthM) > DL_HJR_EPS); // 三分母零闸 / the three denominator guards
IF _bRatioOk AND _bFinOk THEN // 比值可算且入参可信 / the ratio is computable with trustworthy inputs
    _fStockVel := fStockFlowLpm / (fSliceMm * fWidthM); // 浆速 [m/min]（两个千分折算相消，边界二）/ the stock speed [m/min]
    _fRatio := _fStockVel / fWireSpeedMpm; // 喷射比 [比值] / the jet ratio [ratio]
    IF NOT (_fRatio = _fRatio) THEN _fRatio := _fRatioLst; END_IF // 比值 NaN 兜底（回退上一有效）/ the NaN fallback to the hold slot
    IF (_fRatio - _fRatio) <> (_fRatio - _fRatio) THEN _fRatio := _fRatioLst; END_IF // 比值 Inf 兜底 / the Inf fallback to the hold slot
    _fRatioLst := _fRatio; // 保持槽写入（已过非有限闸，R133）/ the guarded write into the hold slot
ELSE // 网速或开度为零 / the wire speed or the slice is zero
    _fRatio := _fRatioLst; // 比值保持上一有效值 / hold the last valid ratio
    _fStockVel := 0.0; // 浆速出零（不虚报）/ the stock speed goes to zero
    IF _iErrTmp = 0 THEN _iErrTmp := 2903; END_IF // 信息级：比值不可算 / the info code for an uncomputable ratio
END_IF
// 段 8｜PI 调节与限位抗饱和：仅在调节窗口内积分（状态量门控，R99）
_fConsFact := 1.0; // 浆浓比预置一 / the consistency ratio preset unity
IF fConsNomPct > DL_HJR_EPS THEN _fConsFact := fConsPct / fConsNomPct; END_IF // 浆浓比（分母已过域闸）[倍] / the consistency ratio [times]
IF _bRatioOk AND _bFinOk AND _bCfgOk AND bEnable THEN // 控制律在输入可信、比值可算且使能时推进（R583 补使能门控）
    _fErr := _fRatio - fJetRatioSp; // 喷射比偏差 [比值]，正为浆速偏高 / the ratio error, positive means a fast jet
    _fErrCtl := _fErr + (DL_HJR_PROF_GAIN * _fProfMean) + (DL_HJR_CONS_GAIN * (_fConsFact - 1.0)); // 加横幅修正与浆浓前馈 / add the profile and consistency corrections
    IF ABS(_fErrCtl) <= DL_HJR_DEADBAND THEN _fErrCtl := 0.0; END_IF // 死区内偏差取零（不踢动）/ zero the error inside the dead band
    _bFreeze := (_bAtLimit OR (_eState = E_DL_HjrState.eIdle) OR (_eState = E_DL_HjrState.eStabilize) OR (_eState = E_DL_HjrState.eLimitHold)) OR (NOT bEnable); // R583 补 eStabilize：稳定窗内不得积分，否则开窗期已积出超调 // 冻结判据挂状态量（R99）；限位为跨拍电平量，本处取上一拍限位态，限位持续期内每拍皆冻结，单拍滞后不影响抗饱和 / the freeze verdict uses the state, the limit is a level lasting many scans
    IF NOT _bFreeze THEN // 未冻结才积分 / integrate only while unfrozen
        _fInt := _fInt + (DL_HJR_KI * _fErrCtl); // 积分项累加 [mm] / accumulate the integral [mm]
        IF _fInt > DL_HJR_INT_MAX THEN _fInt := DL_HJR_INT_MAX; ELSIF _fInt < (0.0 - DL_HJR_INT_MAX) THEN _fInt := (0.0 - DL_HJR_INT_MAX); END_IF // 积分项双向限幅 / the integral limit
    END_IF
    _fPiOut := (DL_HJR_KP * _fErrCtl) + _fInt; // PI 输出 [mm] / the PI output [mm]
    _fTarget := _fBase + _fPiOut; // 目标开度 [mm] / the target opening [mm]
    _fStep := _fTarget - _fCmd; // 本拍应走增量 [mm] / the step required this scan [mm]
    IF _fStep > DL_HJR_STEP_MM THEN _fStep := DL_HJR_STEP_MM; ELSIF _fStep < (0.0 - DL_HJR_STEP_MM) THEN _fStep := (0.0 - DL_HJR_STEP_MM); END_IF // 单拍双向限幅 / the two sided step limit
    IF NOT (_fStep = _fStep) THEN _fStep := 0.0; END_IF // 增量 NaN 兜底 / the NaN fallback
    IF (_fStep - _fStep) <> (_fStep - _fStep) THEN _fStep := 0.0; END_IF // 增量 Inf 兜底 / the Inf fallback
    _fCmd := _fCmd + _fStep; // 指令累加（唯一写入点）[mm] / the only write point of the command [mm]
    IF _fCmd > fSliceMaxMm THEN _fCmd := fSliceMaxMm; END_IF // 上限硬钳 / the hard clamp high
    IF _fCmd < fSliceMinMm THEN _fCmd := fSliceMinMm; END_IF // 下限硬钳 / the hard clamp low
    _fCmdLst := _fCmd; // 上一有效指令同步 / sync the last valid command
END_IF
_bAtLimit := (_fCmd >= (fSliceMaxMm - DL_HJR_LIMIT_BAND)) OR (_fCmd <= (fSliceMinMm + DL_HJR_LIMIT_BAND)); // 限位判据（含判定带）/ the limit verdict with its band
// 段 9｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
CASE _eState OF
E_DL_HjrState.eIdle: // 空闲相：退出条件三（失能驻留、输入不可信驻留、使能且可信进取）
    IF bEnable AND _bFinOk AND _bCfgOk THEN // 使能且双闸通过 / enabled with both gates passed
        _fBase := _fCmd; // 基准开度锁存为当前指令 [mm] / latch the base opening [mm]
        _fInt := 0.0; // 积分项无扰归零（进稳定相）/ clear the integral on entry
        _eState := E_DL_HjrState.eStabilize; // 迁稳定相 / migrate to stabilise
    END_IF
E_DL_HjrState.eStabilize: // 稳定相：退出条件四（失能、限位、稳定窗到期、偏差入死区）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_HjrState.eIdle; // 回空闲 / back to idle
    ELSIF _bAtLimit THEN // 一进入即到限 / already on a limit
        _eState := E_DL_HjrState.eLimitHold; // 迁限位相 / migrate to the limit hold
    ELSIF tonStab.Q THEN // 稳定窗到期 / the window expired
        _eState := E_DL_HjrState.eRegulate; // 迁调节相 / migrate to regulate
    ELSIF ABS(_fErrCtl) <= DL_HJR_DEADBAND THEN // 偏差已入死区（无需调节）/ the error already sits in the dead band
        _eState := E_DL_HjrState.eRegulate; // 迁调节相（保持指令）/ migrate to regulate
    END_IF
E_DL_HjrState.eRegulate: // 调节相：退出条件三（失能、限位、输入不可信）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_HjrState.eIdle; // 回空闲 / back to idle
    ELSIF _bAtLimit THEN // 开度到达限位 / the slice reached a limit
        _eState := E_DL_HjrState.eLimitHold; // 迁限位相（冻结积分）/ migrate to the limit hold
    ELSIF NOT _bFinOk THEN // 输入不可信（停在本相但不出量）/ the inputs are untrustworthy
        _eState := E_DL_HjrState.eIdle; // 回空闲等恢复 / back to idle
    END_IF
E_DL_HjrState.eLimitHold: // 限位相：退出条件二（失能、限位条件消失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_HjrState.eIdle; // 回空闲 / back to idle
    ELSIF NOT _bAtLimit THEN // 限位条件消失 / the limit condition cleared
        _eState := E_DL_HjrState.eRegulate; // 回调节相 / back to regulate
    END_IF
ELSE // 非法相位兜底（R6、R128）
    _eState := E_DL_HjrState.eIdle; // 回安全态空闲 / back to the safe idle phase
    _iErrTmp := 2905; // 信息级非法相位码 / the info grade illegal phase code
END_CASE
IF _bAtLimit AND (_iErrTmp = 0) THEN _iErrTmp := 2904; END_IF // 限位信息级码（电平位另由 xAtLimit 表达）/ the limit info code
// 段 10｜统一出口：单点映射，限位位与指令同源（R191、FB51-3）
eState := _eState; // 相位单点映射 / the single point mapping of the phase
xAtLimit := _bAtLimit; // 限位位单点映射 / the single point mapping of the limit bit
fSliceCmd := _fCmdLst; // 开度指令单点映射（无效拍保持上一有效值，边界六）/ the command mapping with the hold
fJetRatio := _fRatioLst; // 喷射比单点映射（无效拍保持上一有效值）/ the ratio mapping with the hold
fStockSpeedMpm := _fStockVel; // 浆速单点映射 [m/min] / the stock speed mapping [m/min]
fProfileMean := _fProfMean; // 横幅均值单点映射 [g/m²] / the profile mean mapping [g/m2]
fRatioErr := _fErrCtl; // 控制偏差单点映射 [比值] / the control error mapping [ratio]
fSliceStep := _fStep; // 开度增量单点映射 [mm] / the step mapping [mm]
iErrCode := _iErrTmp; // 信息级码单点映射（每拍重算，不锁存）/ the info code mapping
xValid := _bFinOk AND _bCfgOk AND _bRatioOk AND (_iErrTmp <> 2905); // 有效性：三闸通过且非非法相位（限位码 2904 不影响有效性）/ valid unless the phase is illegal
END_FUNCTION_BLOCK
