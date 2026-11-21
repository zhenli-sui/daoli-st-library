(*
  Name        : FC_DL_WetBulbCalc
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 干球温度/相对湿度的湿球温度迭代估算：以 Magnus 饱和水汽压式构造热力学方程，牛顿迭代求根（焓湿图原子补口）；/ Wet-bulb temperature estimation from dry-bulb temperature and relative humidity: Magnus saturation-vapour formulation solved by Newton iteration
  溯源        : 借 t1-2-oscat-building 的分类/参数域组织，clean-room 实现
  Boundary    : ① 入口有限性闸：任一输入 NaN（x = x 自反）或 Inf（(x-x) = (x-x) 差判）→ bValid = FALSE，返回 0.0（哨兵零点，不饱和、不外推）；
                ② 输入域钳位：干球温度钳 -40..80 °C、相对湿度钳 1..100 %、气压钳 300..1100 hPa，钳位是各自中间量的最后一次写；
                ③ 牛顿迭代：上限 20 次，步长收敛阈 DL_WBC_EPS；迭代发散（导数近零）即刻退出并置 bValid = FALSE；
                ④ 除零前置：迭代导数 |des + gamma| < eps 时不除（发散路径）；湿度换算除子为常量 100.0；
                ⑤ 返回值 = 湿球温度 [°C]，bValid = FALSE 时不得使用返回值（上层契约）。
*)
FUNCTION FC_DL_WetBulbCalc : REAL
VAR_INPUT
    fTempDry  : REAL;                        (* 干球温度 [°C] / Dry-bulb temperature *)
    fRelHum   : REAL;                        (* 相对湿度，域 1..100（越域钳位）[%] / Relative humidity, clamped *)
    fPressure : REAL := 1013.25;             (* 大气压，域 300..1100（越域钳位）[hPa] / Atmospheric pressure, clamped *)
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                        (* 结果有效标志（FALSE 时返回值为哨兵零点）[-] / Result validity flag *)
END_VAR
VAR
    _fT       : REAL;                        (* 钳位后干球温度中间量 [°C] / Clamped dry-bulb temperature *)
    _fRh      : REAL;                        (* 钳位后相对湿度中间量 [%] / Clamped relative humidity *)
    _fP       : REAL;                        (* 钳位后气压中间量 [hPa] / Clamped pressure *)
    _fEs      : REAL;                        (* 干球温度饱和水汽压 [Pa] / Saturation vapour pressure at dry bulb *)
    _fE       : REAL;                        (* 实际水汽压 [Pa] / Actual vapour pressure *)
    _fGamma   : REAL;                        (* 湿计常数 gamma = 0.00066 × P [Pa/°C 口径见实现] / Psychrometric constant *)
    _fTw      : REAL;                        (* 湿球温度迭代变量 [°C] / Wet-bulb iterate *)
    _fEsW     : REAL;                        (* 湿球温度饱和水汽压 [Pa] / Saturation vapour pressure at wet bulb *)
    _fDesW    : REAL;                        (* 饱和水汽压对湿球温度导数 [Pa/°C] / Derivative of es at wet bulb *)
    _fFv      : REAL;                        (* 方程残差 f(Tw) [Pa] / Equation residual *)
    _fDv      : REAL;                        (* 方程导数 f'(Tw) [Pa/°C] / Equation derivative *)
    _fStep    : REAL;                        (* 牛顿步长（绝对值判敛）[°C] / Newton step magnitude *)
    _nIt      : INT;                         (* 迭代计数 [次] / Iteration counter *)
    _bOk      : BOOL;                        (* 求解成功内部量 / Solve-success internal *)
END_VAR
VAR CONSTANT
    DL_WBC_EPS   : REAL := 1.0E-4;           (* 迭代收敛阈值 [°C] / Convergence threshold *)
    DL_WBC_ITMAX : INT  := 20;               (* 牛顿迭代上限 [次] / Newton iteration cap *)
    DL_WBC_A     : REAL := 17.625;           (* Magnus 系数 a [-] / Magnus coefficient a *)
    DL_WBC_B     : REAL := 243.04;           (* Magnus 系数 b [°C] / Magnus coefficient b *)
    DL_WBC_ES0   : REAL := 610.94;           (* Magnus 基准饱和水汽压 [Pa] / Magnus base saturation pressure *)
    DL_WBC_HUND  : REAL := 100.0;            (* 湿度百分数换算常量（常量除子）[-] / Percent scale constant *)
    DL_WBC_TMIN  : REAL := -40.0;            (* 干球温度钳位下限 [°C] / Dry-bulb clamp floor *)
    DL_WBC_TMAX  : REAL := 80.0;             (* 干球温度钳位上限 [°C] / Dry-bulb clamp ceiling *)
    DL_WBC_PMIN  : REAL := 300.0;            (* 气压钳位下限 [hPa] / Pressure clamp floor *)
    DL_WBC_PMAX  : REAL := 1100.0;           (* 气压钳位上限 [hPa] / Pressure clamp ceiling *)
END_VAR

(* —— 段 0：入口有限性闸（NaN 自反 + Inf 差判，三输入逐项） —— *)
bValid := TRUE;                                                                (* 有效标志预置（任一闸命中即翻 FALSE） / Validity preset *)
IF NOT ((fTempDry = fTempDry) AND ((fTempDry - fTempDry) = (fTempDry - fTempDry))) THEN
    bValid := FALSE;                                                           (* 干球温度非有限 / Dry bulb non-finite *)
END_IF
IF NOT ((fRelHum = fRelHum) AND ((fRelHum - fRelHum) = (fRelHum - fRelHum))) THEN
    bValid := FALSE;                                                           (* 相对湿度非有限 / Humidity non-finite *)
END_IF
IF NOT ((fPressure = fPressure) AND ((fPressure - fPressure) = (fPressure - fPressure))) THEN
    bValid := FALSE;                                                           (* 气压非有限 / Pressure non-finite *)
END_IF

(* —— 段 1：无效输入早退（返回哨兵零点，不饱和、不外推） —— *)
IF NOT bValid THEN
    FC_DL_WetBulbCalc := 0.0;                                                  (* 哨兵零点返回 / Sentinel zero return *)
    RETURN;
END_IF

(* —— 段 2：输入域钳位（各自中间量最后一次写，钳位不被覆盖） —— *)
_fT := fTempDry;                                                               (* 干球温度装载 / Load dry bulb *)
IF _fT < DL_WBC_TMIN THEN
    _fT := DL_WBC_TMIN;                                                        (* 下限钳位 / Lower clamp *)
END_IF
IF _fT > DL_WBC_TMAX THEN
    _fT := DL_WBC_TMAX;                                                        (* 上限钳位 / Upper clamp *)
END_IF
_fRh := fRelHum;                                                               (* 相对湿度装载 / Load humidity *)
IF _fRh < 1.0 THEN
    _fRh := 1.0;                                                               (* 湿度下限钳 1（防 0 湿度发散） / Humidity lower clamp *)
END_IF
IF _fRh > DL_WBC_HUND THEN
    _fRh := DL_WBC_HUND;                                                       (* 湿度上限钳 100 / Humidity upper clamp *)
END_IF
_fP := fPressure;                                                              (* 气压装载 / Load pressure *)
IF _fP < DL_WBC_PMIN THEN
    _fP := DL_WBC_PMIN;                                                        (* 气压下限钳位 / Pressure lower clamp *)
END_IF
IF _fP > DL_WBC_PMAX THEN
    _fP := DL_WBC_PMAX;                                                        (* 气压上限钳位 / Pressure upper clamp *)
END_IF

(* —— 段 3：热力学方程构造（Magnus + 湿计方程） —— *)
_fEs := DL_WBC_ES0 * EXP(DL_WBC_A * _fT / (_fT + DL_WBC_B));                   (* 干球温度饱和水汽压（除子 _fT+243.04 恒 > 0，域钳位保证）[Pa] / es at dry bulb *)
_fE := _fRh / DL_WBC_HUND * _fEs;                                             (* 实际水汽压（除子为常量）[Pa] / Actual vapour pressure *)
_fGamma := 0.00066 * _fP;                                                     (* 湿计常数（无除法）[hPa/°C] / Psychrometric constant *)

(* —— 段 4：牛顿迭代求湿球温度（发散与不收敛均落 bValid = FALSE，安全侧） —— *)
_fTw := _fT;                                                                   (* 迭代初值取干球温度（物理上界） / Init at dry bulb *)
_bOk := FALSE;                                                                 (* 求解成功内部量预清 / Success preset *)
_nIt := 0;                                                                     (* 迭代计数清零 / Counter clear *)
WHILE _nIt < DL_WBC_ITMAX DO
    _fEsW := DL_WBC_ES0 * EXP(DL_WBC_A * _fTw / (_fTw + DL_WBC_B));            (* 湿球温度饱和水汽压 [Pa] / es at wet bulb *)
    _fDesW := _fEsW * DL_WBC_A * DL_WBC_B / ((_fTw + DL_WBC_B) * (_fTw + DL_WBC_B));   (* Magnus 导数（除子平方项恒 > 0）[Pa/°C] / Derivative of es *)
    _fFv := _fEsW - _fGamma * (_fT - _fTw) - _fE;                              (* 残差 f(Tw) = es(Tw) - gamma·(T - Tw) - e [Pa] / Residual *)
    _fDv := _fDesW + _fGamma;                                                  (* 导数 f'(Tw)（湿计项恒正）[Pa/°C] / Derivative *)
    IF ABS(_fDv) < DL_WBC_EPS THEN
        _bOk := FALSE;                                                         (* 导数近零：发散退出（除零前置，边界③） / Diverged on near-zero derivative *)
        EXIT;
    END_IF
    _fStep := _fFv / _fDv;                                                     (* 牛顿步长（除子已过闸）[°C] / Newton step *)
    _fTw := _fTw - _fStep;                                                     (* 迭代递进 / Iterate advance *)
    IF _fTw > _fT THEN
        _fTw := _fT;                                                           (* 湿球不超干球（物理上界钳位） / Wet bulb <= dry bulb *)
    END_IF
    IF _fTw < _fT - 60.0 THEN
        _fTw := _fT - 60.0;                                                    (* 湿球下界钳位（防迭代飞逸） / Wet bulb floor *)
    END_IF
    IF ABS(_fStep) < DL_WBC_EPS THEN
        _bOk := TRUE;                                                          (* 步长收敛：求解成功 / Converged *)
        EXIT;
    END_IF
    _nIt := _nIt + 1;                                                          (* 迭代计数递进 / Counter advance *)
END_WHILE

(* —— 段 5：出口（bValid 由收敛结果定，返回湿球温度） —— *)
bValid := _bOk;                                                                (* 有效标志 = 收敛成功 / Validity = converged *)
IF bValid THEN
    FC_DL_WetBulbCalc := _fTw;                                                 (* 湿球温度返回 [°C] / Wet-bulb return *)
ELSE
    FC_DL_WetBulbCalc := 0.0;                                                  (* 未收敛返回哨兵零点（安全侧契约） / Sentinel zero on divergence *)
END_IF
END_FUNCTION
