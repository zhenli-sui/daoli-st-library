(*
  Name: FC_DL_CalenderLineLoadCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 辊压线载荷按「总轧制力摊到辊面母线长度」计算：fLineLoadNmm = 轧制力[N] / 辊宽[mm]。
           线载荷是辊压工艺的核心控制量（压实密度主要由线载荷与来料状态共同决定），
           比总轧制力更能跨机台比较，故单独输出。
        2) 总压力 fTotalN 由 kN 换算为 N（乘 1000），作为执行机构（液压/伺服压下）的力指令基准，
           与线载荷同源：两者都由同一个 kN 输入换算，不存在二次取数导致的数值不一致。
  边界条件：1) 非有限值闸：两路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：ABS(fRollWidthMm) > DL_EPS 才允许相除（辊宽为 0 时线载荷发散）。
        3) 负值闸：轧制力为负（拉辊工况不属本件）、辊宽为负均判无效（不取绝对值掩盖反向）。
        4) 零值语义：轧制力为 0 属合法（空载/开口状态），线载荷为 0，不判无效；
           辊宽为 0 判无效（组态缺失，不是工况）。
        5) 饱和钳制：总压力钳 0 ~ DL_FORCE_MAX(1.0E7 N)，线载荷钳 0 ~ DL_LOAD_MAX(5000 N/mm)，
           防极小辊宽把线载荷放大到溢出。
  量纲自证：fLineLoadNmm = N / mm = N/mm；fTotalN = kN × 1000 (N/kN) = N；
           1000 为 [N/kN] 力单位换算因子，无量纲混入。两个输出量纲独立且各自自洽。
*)

FUNCTION FC_DL_CalenderLineLoadCalc : BOOL
VAR_INPUT
    fRollForceKN   : REAL;   // 总轧制力 [kN] / Total roll force [kN]
    fRollWidthMm   : REAL;   // 辊面有效宽度 [mm] / Effective roll face width [mm]
END_VAR
VAR_OUTPUT
    fLineLoadNmm   : REAL;   // 线载荷 [N/mm] / Line load [N/mm]
    fTotalN        : REAL;   // 总压力 [N] / Total force [N]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fForceN       : REAL;   // 换算后的总压力 [N] / Converted total force [N]
    _fLineRawNmm   : REAL;   // 未饱和的线载荷 [N/mm] / Raw line load [N/mm]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_N_PER_KN    : REAL := 1000.0;    // kN → N 换算因子 [N/kN] / Kilonewton to newton factor [N/kN]
    DL_FORCE_MAX   : REAL := 1.0E7;     // 总压力饱和上限 [N] / Total force saturation ceiling [N]
    DL_LOAD_MAX    : REAL := 5000.0;    // 线载荷饱和上限 [N/mm] / Line load saturation ceiling [N/mm]
END_VAR

(* —— 段 1：非有限值闸（R19：闸断实值通路，NaN 不得进入除法） —— *)
IF NOT (fRollForceKN > -DL_BIG AND fRollForceKN < DL_BIG)
   OR NOT (fRollWidthMm > -DL_BIG AND fRollWidthMm < DL_BIG) THEN
    fLineLoadNmm := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fTotalN := 0.0;                         // 总压力强制 0.0 / Total force forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CalenderLineLoadCalc := FALSE;    // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：辊宽为 0 时线载荷发散） —— *)
IF ABS(fRollWidthMm) <= DL_EPS THEN
    fLineLoadNmm := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fTotalN := 0.0;                         // 总压力强制 0.0 / Total force forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CalenderLineLoadCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（力为负属工艺异常，辊宽为负属组态错误） —— *)
IF (fRollForceKN < 0.0) OR (fRollWidthMm < 0.0) THEN
    fLineLoadNmm := 0.0;                    // 输出强制 0.0 / Output forced to zero
    fTotalN := 0.0;                         // 总压力强制 0.0 / Total force forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CalenderLineLoadCalc := FALSE;    // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：单位换算与线载荷（R22 方向自核：力在分子、辊宽在分母） —— *)
_fForceN := fRollForceKN * DL_N_PER_KN;                          // 总压力 [N]
_fLineRawNmm := _fForceN / fRollWidthMm;                         // 线载荷 [N/mm]

(* —— 段 5：输出单点写盘（饱和钳制，两个输出同源同一次换算） —— *)
fTotalN := LIMIT(0.0, _fForceN, DL_FORCE_MAX);                   // 总压力 [N]
fLineLoadNmm := LIMIT(0.0, _fLineRawNmm, DL_LOAD_MAX);           // 线载荷 [N/mm]

(* —— 段 6：有效位单点聚合 —— *)
xValid := (fRollForceKN >= 0.0) AND (fRollWidthMm > DL_EPS);     // 有效位聚合
FC_DL_CalenderLineLoadCalc := xValid;                            // 返回码：TRUE = 计算可信

END_FUNCTION
