(*
  Name: FC_DL_TireCurePressForceCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 合模力按「胶囊压力 × 轮胎投影面积」计算：
           F = p * A，其中 p 以 kPa 给出、A 以 m2 给出，则
           F[kN] = p[kPa] * 1000[Pa/kPa] * A[m2] / 1000[N/kN] = p * A，
           即数值上 kPa 与 m2 直乘即为 kN，这是本件量纲自证的要点。
        2) 机台额定上限校验：fForceLoadPct = F / fRatedKn * 100，超额定只置 xOverRated 并钳到额定值，
           不把越限值当作可执行指令下发（合模力不足会出明疤，超额定会压伤模具）。
        3) 不足判据：F < fRatedKn * fMinLoadPct / 100 时置 xUnderForce，
           表示胶囊压力不足以撑满花纹（定型不足），供上层提升一次定型压力。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（力与负荷率强制 0.0），不得只置标志（R19）。
        2) 面积零闸：轮胎投影面积 fProjectAreaM2 必须 > DL_EPS，否则力恒为零，
           会把「面积未组态」伪装成「无合模力」，因此判无效而非输出 0。
        3) 额定值域闸：fRatedKn 必须 > DL_EPS（负荷率式的分母）；fMinLoadPct 须落在 (0.0, 100.0] 内，
           越域说明阈值未组态（下限为 0 会使不足判据恒假）。
        4) 压力域闸：fPressKpa 不得为负（负表压属传感器错，不取绝对值掩盖）。
        5) 判据取原始值（R24）：超额定与不足判定均使用钳制前的 _fForceRawKn，不得先钳再判。
        6) 物理域钳制：力钳 0.0 ~ fRatedKn；负荷率钳 0.0 ~ DL_PCT_HI。
  量纲自证：p [kPa] = 1000 Pa；A [m2]；p*A = 1000 Pa*m2 = 1000 N = 1 kN，
           故 F[kN] 与 p[kPa]*A[m2] 数值相等，量纲关系合法；
           fForceLoadPct = (kN)/(kN)*100 = 无因次百分数 [%]。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_TireCurePressForceCalc : BOOL
VAR_INPUT
    fPressKpa        : REAL;   // 胶囊内蒸汽/氮气压力 [kPa] / Bladder steam or nitrogen pressure [kPa]
    fProjectAreaM2   : REAL;   // 轮胎内腔投影面积 [m2] / Tyre inner projection area [m2]
    fRatedKn         : REAL;   // 机台额定合模力 [kN] / Machine rated clamping force [kN]
    fMinLoadPct      : REAL;   // 允许最小负荷率（低于即判定型不足）[%] / Minimum load ratio [%]
END_VAR
VAR_OUTPUT
    fForceKn         : REAL;   // 合模力 [kN] / Clamping force [kN]
    fForceLoadPct    : REAL;   // 合模力对额定值的负荷率 [%] / Load ratio against the rated force [%]
    xUnderForce      : BOOL;   // 合模力不足标志 [bool] / Insufficient clamping force flag [bool]
    xOverRated       : BOOL;   // 超机台额定标志 [bool] / Over rated force flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fForceRawKn     : REAL;   // 钳制前的原始合模力 [kN] / Raw clamping force before limiting [kN]
    _fLoadRawPct     : REAL;   // 钳制前的原始负荷率 [%] / Raw load ratio before limiting [%]
    _fMinForceKn     : REAL;   // 允许最小合模力 [kN] / Minimum acceptable clamping force [kN]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 100.0;     // 负荷率物理上限 [%] / Load ratio upper bound [%]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fPressKpa > -DL_BIG AND fPressKpa < DL_BIG)
   OR NOT (fProjectAreaM2 > -DL_BIG AND fProjectAreaM2 < DL_BIG)
   OR NOT (fRatedKn > -DL_BIG AND fRatedKn < DL_BIG)
   OR NOT (fMinLoadPct > -DL_BIG AND fMinLoadPct < DL_BIG) THEN
    fForceKn := 0.0;                        // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fForceLoadPct := 0.0;                   // 负荷率强制 0.0 / Load ratio forced to zero
    xUnderForce := TRUE;                    // 失效侧按不足处理（保守侧）/ Treat as insufficient when invalid
    xOverRated := FALSE;                    // 失效侧超额定位保持假 / Over-rated stays false
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_TireCurePressForceCalc := FALSE;  // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：面积零闸与额定值域闸（面积为乘子，额定值为负荷率分母） —— *)
IF (fProjectAreaM2 <= DL_EPS)                                     // 面积不可为零
   OR (fRatedKn <= DL_EPS)                                        // 额定力必须已组态
   OR (fMinLoadPct <= DL_EPS)                                     // 最小负荷率不可为零（否则判据恒假）
   OR (fMinLoadPct > DL_PCT_HI)                                   // 最小负荷率不得超 100 %
   OR (fPressKpa < 0.0) THEN                                      // 压力不得为负
    fForceKn := 0.0;                        // 参数不可用即无合模力 / No parameter, no force
    fForceLoadPct := 0.0;                   // 负荷率不可算 / Load ratio not computable
    xUnderForce := TRUE;                    // 按不足处理（保守侧）/ Treat as insufficient
    xOverRated := FALSE;                    // 超额定位保持假 / Over-rated stays false
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_TireCurePressForceCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fForceRawKn := fPressKpa * fProjectAreaM2;                                       // 合模力 [kN]（kPa*m2 = kN）
_fLoadRawPct := _fForceRawKn / fRatedKn * DL_PCT;                                 // 负荷率 [%]
_fMinForceKn := fRatedKn * fMinLoadPct / DL_PCT;                                  // 允许最小合模力 [kN]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xUnderForce := (_fForceRawKn < _fMinForceKn);                                     // 定型不足（压力撑不满花纹）
xOverRated := (_fForceRawKn > fRatedKn);                                          // 超机台额定（压伤模具风险）
xValid := (_fForceRawKn >= 0.0)                                                   // 力不得为负
          AND (_fLoadRawPct >= 0.0)                                               // 负荷率不得为负
          AND (_fMinForceKn >= 0.0);                                              // 最小力不得为负（组态校验）

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fForceKn := LIMIT(0.0, _fForceRawKn, fRatedKn);                                   // 力钳 0..额定 [kN]
fForceLoadPct := LIMIT(0.0, _fLoadRawPct, DL_PCT_HI);                             // 负荷率钳 0..100 [%]
FC_DL_TireCurePressForceCalc := xValid;                                           // 返回码：TRUE = 计算可信

END_FUNCTION
