(*
  Name: FC_DL_LyoResidualMoistureCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 残余水分估算按「压力升速率法」：一次干燥末期关闭隔离阀，测腔内压力升幅与时间，
           升压速率 r = dP / t [mbar/s]；残余水分与升压速率近似成正比，并用干重比归一：
           W_res% = coef * r / ratio，coef 为经方法学验证的标定系数 [%*s/mbar]，
           ratio 为干物质质量占比 [kg/kg]（干重比），用于把腔体自由水折算到制品含湿量。
        2) 合格判据：残余水分 <= fSpecMaxPct（药典/内控限度，通常 1~3 %）输出 xSpecOver = FALSE。
        3) 比值域校验：干重比必须落在 (DL_RATIO_LO, 1.0] 内（干物质不可能超过总质量，
           也不可能为零），越域判无效而非钳制 —— 钳制会严重放大或抹平结果。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（水分与速率强制 0.0 且置超限位，保守侧），不得只置标志（R19）。
        2) 时间零闸：升压时长 fRiseTimeS 必须 > DL_EPS（速率式分母），否则判无效。
        3) 比值零闸：干重比 fDryWeightRatio 必须 > DL_RATIO_LO（水分式分母），否则判无效。
        4) 标定系数域闸：fCoefPctSPerMbar 必须 > DL_EPS（系数未标定则结果无意义）。
        5) 判据取原始值（R24）：超限判定使用钳制前的 _fResRawPct，不得先钳再判。
        6) 物理域钳制：残余水分钳 0.0 ~ DL_PCT_HI；升压速率钳 0.0 ~ DL_RATE_HI。
  量纲自证：r = (mbar)/(s) = mbar/s；
           coef * r / ratio = (%*s/mbar)*(mbar/s)/(kg/kg) = %，干重比无因次，量纲链闭合。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoResidualMoistureCalc : BOOL
VAR_INPUT
    fPressRiseMbar   : REAL;   // 测试期腔内压力升幅 [mbar] / Chamber pressure rise during the test [mbar]
    fRiseTimeS       : REAL;   // 升压时长 [s] / Pressure rise duration [s]
    fDryWeightRatio  : REAL;   // 干物质质量占比（干重比）[kg/kg] / Dry matter mass ratio [kg/kg]
    fCoefPctSPerMbar : REAL;   // 标定系数 [%*s/mbar] / Calibration coefficient [%*s/mbar]
    fSpecMaxPct      : REAL;   // 残余水分内控上限 [%] / In-house residual moisture limit [%]
END_VAR
VAR_OUTPUT
    fResidualPct     : REAL;   // 估算残余水分 [%] / Estimated residual moisture [%]
    fRiseRateMbarS   : REAL;   // 压力升速率 [mbar/s] / Pressure rise rate [mbar/s]
    xSpecOver        : BOOL;   // 超内控上限标志 [bool] / Over-specification flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fRateRawMbarS   : REAL;   // 钳制前的原始升压速率 [mbar/s] / Raw rise rate before limiting [mbar/s]
    _fResRawPct      : REAL;   // 钳制前的原始残余水分 [%] / Raw residual moisture before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_RATIO_LO      : REAL := 1.0E-6;    // 干重比下限阈值 [kg/kg] / Dry-weight ratio low gate [kg/kg]
    DL_RATIO_HI      : REAL := 1.0;       // 干重比物理上限 [kg/kg] / Dry-weight ratio upper bound [kg/kg]
    DL_RATE_HI       : REAL := 100.0;     // 升压速率物理上限 [mbar/s] / Rise rate upper bound [mbar/s]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧超限位置真，保守侧） —— *)
IF NOT (fPressRiseMbar > -DL_BIG AND fPressRiseMbar < DL_BIG)
   OR NOT (fRiseTimeS > -DL_BIG AND fRiseTimeS < DL_BIG)
   OR NOT (fDryWeightRatio > -DL_BIG AND fDryWeightRatio < DL_BIG)
   OR NOT (fCoefPctSPerMbar > -DL_BIG AND fCoefPctSPerMbar < DL_BIG)
   OR NOT (fSpecMaxPct > -DL_BIG AND fSpecMaxPct < DL_BIG) THEN
    fResidualPct := 0.0;                    // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fRiseRateMbarS := 0.0;                  // 速率强制 0.0 / Rate forced to zero
    xSpecOver := TRUE;                      // 失效侧按超限处理（保守侧）/ Treat as over-spec when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoResidualMoistureCalc := FALSE; // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸与域闸（时长与干重比均为分母；标定系数须已标定） —— *)
IF (fRiseTimeS <= DL_EPS)                                         // 时长不可为零
   OR (fDryWeightRatio <= DL_RATIO_LO)                            // 干重比不可为零
   OR (fDryWeightRatio > DL_RATIO_HI)                             // 干重比不得超过 1
   OR (fCoefPctSPerMbar <= DL_EPS)                                // 标定系数必须为正
   OR (fSpecMaxPct <= DL_EPS)                                     // 内控上限必须已组态
   OR (fPressRiseMbar < 0.0) THEN                                 // 升幅不得为负（隔离后压力只升）
    fResidualPct := 0.0;                    // 参数不可用即无结果 / No parameter, no result
    fRiseRateMbarS := 0.0;                  // 速率不可算 / Rate not computable
    xSpecOver := TRUE;                      // 按超限处理（保守侧）/ Treat as over-spec
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoResidualMoistureCalc := FALSE; // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fRateRawMbarS := fPressRiseMbar / fRiseTimeS;                                    // 升压速率 [mbar/s]
_fResRawPct := fCoefPctSPerMbar * _fRateRawMbarS / fDryWeightRatio;               // 残余水分 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xSpecOver := (_fResRawPct > fSpecMaxPct);                                         // 超内控上限
xValid := (_fResRawPct >= 0.0)                                                    // 水分不得为负
          AND (_fResRawPct <= DL_PCT)                                             // 水分不得超过 100 %（量级闸）
          AND (_fRateRawMbarS <= DL_RATE_HI);                                     // 速率不得超物理上限

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fResidualPct := LIMIT(0.0, _fResRawPct, DL_PCT);                                  // 水分钳 0..100 [%]
fRiseRateMbarS := LIMIT(0.0, _fRateRawMbarS, DL_RATE_HI);                          // 速率钳 0..物理上限 [mbar/s]
FC_DL_LyoResidualMoistureCalc := xValid;                                          // 返回码：TRUE = 计算可信

END_FUNCTION
