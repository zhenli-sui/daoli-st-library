(*
  Name: FC_DL_LyoSublimationRateCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 升华速率按「传质推动力式」计算：dm/dt = K * A * (p_ice − p_chamber)，
           K 为综合传质系数（含边界层与干燥层阻力），A 为升华面积，
           p_ice 为冰面饱和蒸气压、p_chamber 为腔体实测压力；输出单位 kg/h。
        2) 压差负值为失效判据：腔体压力高于冰面饱和压力时不存在升华推动力
           （此时是凝华而非升华），输出 xNoDrive = TRUE 且速率强制 0.0，
           绝不把负速率下发给热负荷件（会把加热变成制冷指令）。
        3) 速率上限保护：速率超过 fRateMaxKgh 只置 xRateOver 并把数值钳到上限，
           用于识别「冰面暴沸/产品飞溅」风险工况。
  边界条件：1) 非有限值闸：五路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（速率与压差强制 0.0），不得只置标志（R19）。
        2) 系数零闸：传质系数 fMassCoefKghPa 与升华面积 fAreaM2 均须 > DL_EPS，
           任一为零则速率恒为零、时间估算发散，直接判无效而非输出 0。
        3) 压差方向闸：dP = p_ice − p_chamber 必须 > DL_EPS 才允许计算速率；
           零压差（平衡态）与负压差（凝华）一律判 xNoDrive 并清零速率。
        4) 压力域闸：两路压力不得为负（负绝压属传感器错），
           fRateMaxKgh 须 > DL_EPS（上限为零会使钳制把一切速率抹平）。
        5) 判据取原始值（R24）：超上限判定使用钳制前的 _fRateRawKgh，不得先钳再判。
        6) 物理域钳制：速率钳 0.0 ~ fRateMaxKgh；压差钳 0.0 ~ DL_DP_HI_PA。
  量纲自证：K [kg/(m2*h*Pa)] * A [m2] * dP [Pa] = (kg/h)，量纲链闭合；
           fDpPa = (Pa) − (Pa) = Pa，与 K 的分母同量纲。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoSublimationRateCalc : BOOL
VAR_INPUT
    fIcePressPa      : REAL;   // 冰面饱和蒸气压 [Pa] / Ice surface saturation vapour pressure [Pa]
    fChamberPressPa  : REAL;   // 腔体实测压力 [Pa] / Measured chamber pressure [Pa]
    fMassCoefKghPa   : REAL;   // 综合传质系数 [kg/(m2*h*Pa)] / Overall mass transfer coefficient [kg/(m2*h*Pa)]
    fAreaM2          : REAL;   // 有效升华面积 [m2] / Effective sublimation area [m2]
    fRateMaxKgh      : REAL;   // 允许升华速率上限 [kg/h] / Permitted sublimation rate upper limit [kg/h]
END_VAR
VAR_OUTPUT
    fRateKgh         : REAL;   // 升华速率 [kg/h] / Sublimation rate [kg/h]
    fDpPa            : REAL;   // 传质压差（冰面 − 腔体）[Pa] / Driving pressure difference [Pa]
    xNoDrive         : BOOL;   // 无升华推动力标志（压差 <= 0）[bool] / No driving force flag [bool]
    xRateOver        : BOOL;   // 速率超上限标志 [bool] / Rate overrun flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fDpRawPa        : REAL;   // 未钳制的压差 [Pa] / Unclamped pressure difference [Pa]
    _fRateRawKgh     : REAL;   // 钳制前的原始速率 [kg/h] / Raw rate before limiting [kg/h]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_DP_HI_PA      : REAL := 700.0;     // 压差物理上限 [Pa] / Pressure difference upper bound [Pa]
    DL_RATE_ABS_MAX  : REAL := 1000.0;    // 速率绝对物理上限 [kg/h] / Absolute rate upper bound [kg/h]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fIcePressPa > -DL_BIG AND fIcePressPa < DL_BIG)
   OR NOT (fChamberPressPa > -DL_BIG AND fChamberPressPa < DL_BIG)
   OR NOT (fMassCoefKghPa > -DL_BIG AND fMassCoefKghPa < DL_BIG)
   OR NOT (fAreaM2 > -DL_BIG AND fAreaM2 < DL_BIG)
   OR NOT (fRateMaxKgh > -DL_BIG AND fRateMaxKgh < DL_BIG) THEN
    fRateKgh := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fDpPa := 0.0;                           // 压差强制 0.0 / Pressure difference forced to zero
    xNoDrive := TRUE;                       // 失效侧按无推动力处理（安全侧）/ Treat as no drive on invalid
    xRateOver := FALSE;                     // 失效侧超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoSublimationRateCalc := FALSE;  // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：系数零闸（传质系数与面积为乘子，为零则速率恒零、时间估算发散） —— *)
IF (fMassCoefKghPa <= DL_EPS)                                     // 传质系数不可为零
   OR (fAreaM2 <= DL_EPS)                                         // 升华面积不可为零
   OR (fRateMaxKgh <= DL_EPS) THEN                                // 速率上限必须已组态
    fRateKgh := 0.0;                        // 参数不可用即无速率 / No parameter, no rate
    fDpPa := 0.0;                           // 压差不可用 / Difference not usable
    xNoDrive := TRUE;                       // 按无推动力处理 / Treat as no drive
    xRateOver := FALSE;                     // 超限位保持假 / Overrun stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoSublimationRateCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：压差方向闸（判断据取原始压差，R24） —— *)
_fDpRawPa := fIcePressPa - fChamberPressPa;                        // 传质压差 [Pa]
xNoDrive := (_fDpRawPa <= DL_EPS);                                 // 压差为零或为负：无升华推动力

IF xNoDrive THEN
    fRateKgh := 0.0;                        // 无推动力即零速率（不得下发负速率）
    fDpPa := 0.0;                           // 压差出口钳零 / Difference clamped to zero
    xRateOver := FALSE;                     // 超限位保持假 / Overrun stays false
    xValid := (fIcePressPa >= 0.0) AND (fChamberPressPa >= 0.0);     // 压力非负时计算本身仍可信（平衡态）
    FC_DL_LyoSublimationRateCalc := xValid; // 返回码与有效位同源
    RETURN;                                 // 平衡态/凝华态到此为止 / Stop here for equilibrium or deposition
END_IF

(* —— 段 4：主算式（不钳制，先出原始值供段 5 判据使用） —— *)
_fRateRawKgh := fMassCoefKghPa * fAreaM2 * _fDpRawPa;              // 升华速率 [kg/h]

(* —— 段 5：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xRateOver := (_fRateRawKgh > fRateMaxKgh);                         // 速率越上限（暴沸/飞溅风险）
xValid := (fIcePressPa >= 0.0)                                     // 压力不得为负（负绝压属传感器错）
          AND (fChamberPressPa >= 0.0)
          AND (fAreaM2 > 0.0)                                      // 面积已验为正
          AND (fRateMaxKgh <= DL_RATE_ABS_MAX)                     // 上限不得超绝对物理上限
          AND (_fRateRawKgh >= 0.0);                               // 速率不得为负（方向固定）

(* —— 段 6：输出单点写盘（钳制到物理域内，判定结果已在段 5 定案） —— *)
fRateKgh := LIMIT(0.0, _fRateRawKgh, fRateMaxKgh);                 // 速率钳 0..工艺上限 [kg/h]
fDpPa := LIMIT(0.0, _fDpRawPa, DL_DP_HI_PA);                       // 压差钳 0..物理上限 [Pa]
FC_DL_LyoSublimationRateCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
