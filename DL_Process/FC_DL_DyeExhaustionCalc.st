(*
  Name: FC_DL_DyeExhaustionCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 间歇式溢流染色与丝光整理，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 上染率（竭染率）按「初始与残液浓度差」计算：
           E = (C0 − C1) / C0 * 100，C0 为初始染浴浓度、C1 为残液（或染后液）浓度，
           两者取同一稀释倍数下的分光光度换算值，故可直接相减；
           分母固定为初始浓度（上染率是「初始染料中被纤维吸收的比例」）。
        2) 派生量：fUptakeGpl 为单位液量被纤维吸收的染料量 [g/L]，
           用于核算染化料成本与残液回用价值。
        3) 双向异常判定：E < 0（残液比初始还浓，说明浓度测量错位或补料干扰）判 xNegative；
           E > 100（吸收量超过投加量，违反质量守恒）判 xOverHundred。
           两者任一成立即判无效，绝不把异常值当作合格上染率。
  边界条件：1) 非有限值闸：两路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（上染率与吸收量强制 0.0 且置负向异常位，保守侧），不得只置标志（R19）。
        2) 初始浓度零闸：fInitConcGpl 必须 > DL_EPS（上染率式的分母），
           为零则结果发散，判无效并清零，绝不输出「无穷大上染率」。
        3) 浓度非负闸：残液浓度不得为负（负浓度属分光光度计基线漂移或比色皿污染），判无效。
        4) 判据取原始值（R24）：双向异常判定使用钳制前的 _fExhaustRawPct，钳制只作用于输出。
        5) 物理域钳制：上染率钳 0.0 ~ DL_PCT_HI；吸收量钳 0.0 ~ 初始浓度（吸收不可能超过投加）。
        6) 纯函数无状态：上染率的实时趋势与「终点判定」（达 95 % 即转水洗）由上层染缸序 FB 承担。
  量纲自证：E = (g/L − g/L) / (g/L) * 100 = 无因次百分数 [%]；
           fUptakeGpl = (g/L) − (g/L) = g/L，减法两侧同量纲，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_DyeExhaustionCalc : BOOL
VAR_INPUT
    fInitConcGpl     : REAL;   // 初始染浴染料浓度 [g/L] / Initial dye bath concentration [g/L]
    fResidualConcGpl : REAL;   // 残液染料浓度 [g/L] / Residual dye concentration [g/L]
END_VAR
VAR_OUTPUT
    fExhaustPct      : REAL;   // 上染率（竭染率）[%] / Dye exhaustion [%]
    fUptakeGpl       : REAL;   // 单位液量被吸收的染料量 [g/L] / Dye taken up per litre of bath [g/L]
    xNegative        : BOOL;   // 上染率为负（方向异常）标志 [bool] / Negative exhaustion flag [bool]
    xOverHundred     : BOOL;   // 上染率超 100 %（违反守恒）标志 [bool] / Exhaustion over 100 percent flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fUptakeRawGpl   : REAL;   // 钳制前的吸收量 [g/L] / Raw uptake before limiting [g/L]
    _fExhaustRawPct  : REAL;   // 钳制前的原始上染率 [%] / Raw exhaustion before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_CONC_HI_GPL   : REAL := 200.0;     // 染料浓度量级闸上限 [g/L] / Concentration magnitude upper bound [g/L]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧置负向异常，保守侧） —— *)
IF NOT (fInitConcGpl > -DL_BIG AND fInitConcGpl < DL_BIG)
   OR NOT (fResidualConcGpl > -DL_BIG AND fResidualConcGpl < DL_BIG) THEN
    fExhaustPct := 0.0;                     // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fUptakeGpl := 0.0;                      // 吸收量强制 0.0 / Uptake forced to zero
    xNegative := TRUE;                      // 失效侧按方向异常处理 / Treat as abnormal when invalid
    xOverHundred := FALSE;                  // 失效侧超百位保持假 / Over-hundred stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_DyeExhaustionCalc := FALSE;       // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：初始浓度零闸与量级闸（分母为初始浓度） —— *)
IF (fInitConcGpl <= DL_EPS)                                       // 初始浓度不可为零
   OR (fResidualConcGpl < 0.0)                                    // 残液浓度不得为负
   OR (fInitConcGpl > DL_CONC_HI_GPL)                             // 初始浓度量级闸
   OR (fResidualConcGpl > DL_CONC_HI_GPL) THEN                    // 残液浓度量级闸
    fExhaustPct := 0.0;                     // 分母为零即不可算 / No denominator, no ratio
    fUptakeGpl := 0.0;                      // 吸收量不可算 / Uptake not computable
    xNegative := TRUE;                      // 按方向异常处理（保守侧）/ Treat as abnormal
    xOverHundred := FALSE;                  // 超百位保持假 / Over-hundred stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_DyeExhaustionCalc := FALSE;       // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fUptakeRawGpl := fInitConcGpl - fResidualConcGpl;                                // 吸收量 [g/L]
_fExhaustRawPct := _fUptakeRawGpl / fInitConcGpl * DL_PCT;                        // 上染率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xNegative := (_fExhaustRawPct < 0.0);                                             // 残液比初始还浓：方向异常
xOverHundred := (_fExhaustRawPct > DL_PCT);                                       // 超 100 %：违反质量守恒
xValid := (NOT xNegative) AND (NOT xOverHundred)                                  // 双向异常位均不成立
          AND (_fUptakeRawGpl >= 0.0);                                            // 吸收量不得为负

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fExhaustPct := LIMIT(0.0, _fExhaustRawPct, DL_PCT);                               // 上染率钳 0..100 [%]
fUptakeGpl := LIMIT(0.0, _fUptakeRawGpl, fInitConcGpl);                            // 吸收量钳 0..初始浓度 [g/L]
FC_DL_DyeExhaustionCalc := xValid;                                                // 返回码：TRUE = 计算可信

END_FUNCTION
