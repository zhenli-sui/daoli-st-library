(*
  Name: FC_DL_LyoChamberLeakRateCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 腔体泄漏率按压力升试验法（pressure rise test）计算：
           Q = dP * V / t，dP 为隔离后腔内压力升幅 [mbar]、V 为腔体内容积 [L]、t 为测试时长 [s]，
           结果单位 mbar*L/s，是冻干机 GMP 验证的法定泄漏率指标。
        2) 合格判据：Q <= fLeakMaxMbarLs 输出 xPass；同时给出负荷率 fLeakLoadPct = Q / 上限 * 100，
           便于观察密封状态的趋势劣化（负荷率单调上升意味着门封老化）。
        3) 压力升幅方向校验：升幅必须 > 0（隔离后压力只能升，若为负说明隔离阀未关严或
           仍有抽气，测试无效），负升幅判 xValid = FALSE 而非取绝对值。
  边界条件：1) 非有限值闸：四路实值入参先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf，
           命中即闸断实值通路（泄漏率与负荷率强制 0.0），不得只置标志（R19）。
        2) 时间零闸：测试时长 fTestTimeS 必须 > DL_EPS（泄漏率式分母），
           否则判无效并清零，不得输出无穷大泄漏率。
        3) 容积零闸：腔体容积 fVolumeL 必须 > DL_EPS（乘子为零会使一切泄漏率归零，
           把「未接容积组态」伪装成「密封完好」）。
        4) 判据取原始值（R24）：合格判定使用钳制前的 _fLeakRaw，不得先钳再判。
        5) 物理域钳制：泄漏率钳 0.0 ~ DL_LEAK_HI；负荷率钳 0.0 ~ DL_PCT_HI。
        6) 纯函数无状态：本件只算一次测试结果，多次测试的平均与趋势判断由上层质量模块承担。
  量纲自证：Q = (mbar)*(L)/(s) = mbar*L/s，三个因子量纲直乘/直除，无跨量纲混算；
           fLeakLoadPct = (mbar*L/s)/(mbar*L/s)*100 = 无因次百分数 [%]，量纲合法。
  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

FUNCTION FC_DL_LyoChamberLeakRateCalc : BOOL
VAR_INPUT
    fPressRiseMbar   : REAL;   // 测试期腔内压力升幅 [mbar] / Chamber pressure rise during the test [mbar]
    fVolumeL         : REAL;   // 腔体（含管路）内容积 [L] / Chamber and piping internal volume [L]
    fTestTimeS       : REAL;   // 测试时长 [s] / Test duration [s]
    fLeakMaxMbarLs   : REAL;   // 泄漏率合格上限 [mbar*L/s] / Leak rate acceptance limit [mbar*L/s]
END_VAR
VAR_OUTPUT
    fLeakRateMbarLs  : REAL;   // 实测泄漏率 [mbar*L/s] / Measured leak rate [mbar*L/s]
    fLeakLoadPct     : REAL;   // 泄漏率对合格上限的负荷率 [%] / Leak load ratio against the limit [%]
    xPass            : BOOL;   // 合格标志 [bool] / Acceptance flag [bool]
    xValid           : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fLeakRaw        : REAL;   // 钳制前的原始泄漏率 [mbar*L/s] / Raw leak rate before limiting [mbar*L/s]
    _fLoadRawPct     : REAL;   // 钳制前的原始负荷率 [%] / Raw load ratio before limiting [%]
END_VAR
VAR CONSTANT
    DL_EPS           : REAL := 1.0E-9;    // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG           : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PCT           : REAL := 100.0;     // 百分比换算因子 [%] / Percent conversion factor [%]
    DL_PCT_HI        : REAL := 1000.0;    // 负荷率显示上限（允许超 100 % 报警）[%] / Load ratio display ceiling [%]
    DL_LEAK_HI       : REAL := 100.0;     // 泄漏率物理上限 [mbar*L/s] / Leak rate physical upper bound [mbar*L/s]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路） —— *)
IF NOT (fPressRiseMbar > -DL_BIG AND fPressRiseMbar < DL_BIG)
   OR NOT (fVolumeL > -DL_BIG AND fVolumeL < DL_BIG)
   OR NOT (fTestTimeS > -DL_BIG AND fTestTimeS < DL_BIG)
   OR NOT (fLeakMaxMbarLs > -DL_BIG AND fLeakMaxMbarLs < DL_BIG) THEN
    fLeakRateMbarLs := 0.0;                 // 输出强制 0.0，切断污染源 / Force zero, cut polluted path
    fLeakLoadPct := 0.0;                    // 负荷率强制 0.0 / Load ratio forced to zero
    xPass := FALSE;                         // 失效侧不得判合格（安全侧）/ Must not report pass when invalid
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_LyoChamberLeakRateCalc := FALSE;  // 返回码与有效位同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：时间零闸与参数域闸（时间式为分母，容积为乘子都须为正） —— *)
IF (fTestTimeS <= DL_EPS)                                         // 测试时长不可为零
   OR (fVolumeL <= DL_EPS)                                        // 容积不可为零（防「未组态」伪装成完好）
   OR (fLeakMaxMbarLs <= DL_EPS) THEN                             // 合格上限必须已组态
    fLeakRateMbarLs := 0.0;                 // 参数不可用即无泄漏率 / No parameter, no leak rate
    fLeakLoadPct := 0.0;                    // 负荷率不可算 / Load ratio not computable
    xPass := FALSE;                         // 判不合格 / Not accepted
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_LyoChamberLeakRateCalc := FALSE;  // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：主算式（不钳制，先出原始值供段 4 判据使用，R24） —— *)
_fLeakRaw := fPressRiseMbar * fVolumeL / fTestTimeS;                              // 泄漏率 [mbar*L/s]
_fLoadRawPct := _fLeakRaw / fLeakMaxMbarLs * DL_PCT;                              // 负荷率 [%]

(* —— 段 4：判据（取原始值；单点 BOOL 聚合避免多处赋 FALSE 覆盖） —— *)
xValid := (fPressRiseMbar > 0.0)                                                  // 升幅必须为正（隔离有效性）
          AND (_fLeakRaw >= 0.0)                                                  // 泄漏率不得为负
          AND (_fLeakRaw <= DL_LEAK_HI)                                           // 不得超物理上限（量级异常）
          AND (fLeakMaxMbarLs <= DL_LEAK_HI);                                     // 合格上限须在物理域内
xPass := (_fLeakRaw <= fLeakMaxMbarLs) AND xValid;                                // 不越上限且计算可信才判合格

(* —— 段 5：输出单点写盘（钳制到物理域内，判定结果已在段 4 定案） —— *)
fLeakRateMbarLs := LIMIT(0.0, _fLeakRaw, DL_LEAK_HI);                             // 泄漏率钳 0..物理上限
fLeakLoadPct := LIMIT(0.0, _fLoadRawPct, DL_PCT_HI);                              // 负荷率钳 0..显示上限 [%]
FC_DL_LyoChamberLeakRateCalc := xValid;                                           // 返回码：TRUE = 计算可信

END_FUNCTION
