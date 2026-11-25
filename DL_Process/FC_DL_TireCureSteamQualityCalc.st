(*
  Name: FC_DL_TireCureSteamQualityCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 蒸汽干度按焓差法估算：x = (h − h_f) / h_fg，
           h 为实测蒸汽比焓、h_f 为同压力下饱和液比焓、h_fg 为同压力下汽化潜热，
           三者单位一致（kJ/kg），故比值无因次，0 <= x <= 1 即饱和蒸汽的干度区间。
        2) 三态判别（nState）：0 = 饱和蒸汽（0.0 <= x <= 1.0）、1 = 过热蒸汽（x > 1.0）、
           2 = 湿蒸汽/带水（x < 0.0）。硫化工艺要求 x 接近 1.0 的饱和蒸汽，
           带水会显著降低传热系数并在胶囊内壁形成水锤，过热则温度失控。
        3) 干度读数同时钳到 [DL_Q_LO, DL_Q_HI]（-0.5 ~ 1.5），保留三态判别余量，
           避免极端异常值污染趋势曲线。
  边界条件：1) 非有限值闸：三路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（干度强制 0.0 且 nState 置 2 = 湿蒸汽，保守侧），不得只置标志（R19）。
        2) 分母零闸：汽化潜热 fLatentKjKg 必须 > DL_EPS（干度式分母），否则判无效并清零。
        3) 焓值量级闸：三路焓值必须落在 (0.0, DL_H_HI) 内（水的焓恒为正且不超过 4000 kJ/kg 量级），
           越域说明单位用错（J 与 kJ 混用）或测点失效，判无效。
        4) 一致性校验：h_f + h_fg 必须与 h 同量级 —— 若 h_f + h_fg <= DL_EPS，说明压力对应的
           饱和参数未组态（表查错），判无效而非硬算。
        5) 判据取原始值（R24）：三态判别使用钳制前的 _fQualityRaw，不得先钳再判。
        6) 纯函数无状态：干度的滑动平均与趋势判断由上层蒸汽品质监视模块承担。
  量纲自证：x = (kJ/kg − kJ/kg) / (kJ/kg) = 无因次 [-]，量纲合法；
           nState 为无量纲枚举等级 [level]。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCureSteamQualityCalc : BOOL
VAR_INPUT
    fEnthalpyKjKg    : REAL;   // 实测蒸汽比焓 [kJ/kg] / Measured steam specific enthalpy [kJ/kg]
    fSatLiqEnthKjKg  : REAL;   // 同压力下饱和液比焓 [kJ/kg] / Saturated liquid enthalpy at the same pressure [kJ/kg]
    fLatentKjKg      : REAL;   // 同压力下汽化潜热 [kJ/kg] / Latent heat of vaporisation at the same pressure [kJ/kg]
END_VAR
VAR_OUTPUT
    fQuality         : REAL;   // 蒸汽干度（无因次）[-] / Steam quality, dimensionless [-]
    nState           : INT;    // 三态判别 0=饱和 1=过热 2=湿蒸汽/带水 [level] / Steam state 0/1/2 [level]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fQualityRaw     : REAL;   // 钳制前的原始干度 [-]/ Raw quality before limiting [-]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_H_HI          : REAL := 4000.0;    // 焓值量级上限 [kJ/kg] / Enthalpy magnitude upper bound [kJ/kg]
    DL_Q_LO          : REAL := -0.5;      // 干度显示下限 [-]/ Quality display low bound [-]
    DL_Q_HI          : REAL := 1.5;       // 干度显示上限 [-]/ Quality display high bound [-]
    DL_Q_SAT_HI      : REAL := 1.0;       // 饱和蒸汽干度上限 [-]/ Saturated steam quality upper bound [-]
    DL_ST_SAT        : INT := 0;          // 三态：饱和蒸汽 [level] / State: saturated steam [level]
    DL_ST_SUPER      : INT := 1;          // 三态：过热蒸汽 [level] / State: superheated steam [level]
    DL_ST_WET        : INT := 2;          // 三态：湿蒸汽/带水 [level] / State: wet steam with water [level]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路；失效侧置湿蒸汽，保守侧） —— *)
IF NOT (fEnthalpyKjKg > -DL_BIG AND fEnthalpyKjKg < DL_BIG)
   OR NOT (fSatLiqEnthKjKg > -DL_BIG AND fSatLiqEnthKjKg < DL_BIG)
   OR NOT (fLatentKjKg > -DL_BIG AND fLatentKjKg < DL_BIG) THEN
    fQuality := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    nState := DL_ST_WET;                    // 失效侧按带水处理（保守侧：宁可拒用不可误用）
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCureSteamQualityCalc := FALSE;   // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（潜热为干度式分母） —— *)
IF fLatentKjKg <= DL_EPS THEN
    fQuality := 0.0;                        // 潜热缺失即不可算 / No latent heat, no quality
    nState := DL_ST_WET;                    // 按带水处理（保守侧）/ Treat as wet steam
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureSteamQualityCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：焓值量级闸与饱和参数一致性闸（防单位混用与测点失效） —— *)
IF (fEnthalpyKjKg <= 0.0) OR (fEnthalpyKjKg >= DL_H_HI)
   OR (fSatLiqEnthKjKg < 0.0) OR (fSatLiqEnthKjKg >= DL_H_HI)
   OR (fLatentKjKg >= DL_H_HI)
   OR ((fSatLiqEnthKjKg + fLatentKjKg) <= DL_EPS) THEN
    fQuality := 0.0;                        // 焓值越域即不可算 / Enthalpy out of range
    nState := DL_ST_WET;                    // 按带水处理（保守侧）/ Treat as wet steam
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCureSteamQualityCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：主算式（不钳制，先出原始值供段 5 判据使用，R24） —— *)
_fQualityRaw := (fEnthalpyKjKg - fSatLiqEnthKjKg) / fLatentKjKg;                  // 干度 [-]

(* —— 段 5：三态判别（取原始值；判别顺序由湿到过，互斥且完整） —— *)
IF _fQualityRaw < 0.0 THEN
    nState := DL_ST_WET;                    // 带水
ELSIF _fQualityRaw > DL_Q_SAT_HI THEN
    nState := DL_ST_SUPER;                  // 过热
ELSE
    nState := DL_ST_SAT;                    // 饱和
END_IF

xValid := (_fQualityRaw >= DL_Q_LO)                                               // 低于显示下限属量级异常
          AND (_fQualityRaw <= DL_Q_HI);                                          // 高于显示上限属量级异常

(* —— 段 6：输出单点写盘（钳制到显示域内，判别结果已在段 5 定案） —— *)
fQuality := LIMIT(DL_Q_LO, _fQualityRaw, DL_Q_HI);                                // 干度钳 -0.5..1.5 [-]
FC_DL_TireCureSteamQualityCalc := xValid;                                         // 返回码：TRUE = 计算可信

END_FUNCTION
