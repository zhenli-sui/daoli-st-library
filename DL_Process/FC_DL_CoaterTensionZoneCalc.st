(*
  Name: FC_DL_CoaterTensionZoneCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 锂电极片涂布辊压，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 分区总张力按「幅宽 × 单位宽度张力」计算：fTensionN = 幅宽[mm] × 单位张力[N/mm]。
           单位宽度张力是涂布机张力控制的标准口语口径（N/mm），乘幅宽即得该区的总张力设定值，
           幅宽变化时必须同步换算，不能沿用固定总张力（否则单位张力随幅宽漂移）。
        2) 辊面线压按「总张力摊到包角对应的接触弧长」计算：
             接触弧长 = 包角 × 辊半径 = DL_WRAP_RAD × (辊径/2)   [mm]
             辊面线压 = 总张力[N] / 接触弧长[mm]                  [N/mm]
           该口径的含义是「辊面单位母线长度承受的平均法向线压」，用于辊子刚度与轴承选型校核。
           归一化口径在此声明：分母是接触弧长（含辊径），不是幅宽、不是辊径本身，
           若改用幅宽会得到一个与单位张力完全相同的量（信息量为零），这是必须避免的写法。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个 REAL 输出强制 0.0）并置无效（R19）。
        2) 分母零闸：幅宽必须 ABS > DL_EPS（总张力按幅宽换算，幅宽为 0 无意义）；
           辊径经 DL_DIA_MIN_MM(1 mm) 下限钳制后参与接触弧长计算，防辊径为 0 使弧长为 0 而除零。
        3) 负值闸：幅宽、单位张力、辊径任一为负判无效（不取绝对值掩盖反向）。
        4) 饱和钳制：总张力钳 0 ~ DL_TEN_MAX(100000 N)、线压钳 0 ~ DL_PRESS_MAX(1000 N/mm)，
           防极端幅宽与辊径组合溢出。
  量纲自证：fTensionN = mm × (N/mm) = N；
           接触弧长 = [-] × mm = mm（包角为无因次弧度）；
           fLinePressNmm = N / mm = N/mm，与总张力量纲不同且各自自洽，未混算。
*)

FUNCTION FC_DL_CoaterTensionZoneCalc : BOOL
VAR_INPUT
    fWebWidthMm    : REAL;   // 极片幅宽 [mm] / Web width [mm]
    fUnitTensionNmm: REAL;   // 单位宽度张力 [N/mm] / Tension per unit width [N/mm]
    fRollDiaMm     : REAL;   // 导辊直径 [mm] / Roller diameter [mm]
END_VAR
VAR_OUTPUT
    fTensionN      : REAL;   // 分区总张力 [N] / Zone total tension [N]
    fLinePressNmm  : REAL;   // 辊面平均线压 [N/mm] / Mean roller face line pressure [N/mm]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fTensionRawN  : REAL;   // 未饱和的总张力 [N] / Raw total tension [N]
    _fDiaClampMm   : REAL;   // 钳制后的辊径 [mm] / Clamped roller diameter [mm]
    _fArcLenMm     : REAL;   // 包角对应的接触弧长 [mm] / Contact arc length [mm]
    _fPressRawNmm  : REAL;   // 未饱和的辊面线压 [N/mm] / Raw roller line pressure [N/mm]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_PI          : REAL := 3.14159265;   // 圆周率 [-] / Pi [-]
    DL_DIA_MIN_MM  : REAL := 1.0;       // 辊径下限钳制值 [mm] / Roller diameter lower clamp [mm]
    DL_TWO         : REAL := 2.0;       // 半径除数 [-] / Radius divisor [-]
    DL_TEN_MAX     : REAL := 100000.0;  // 总张力饱和上限 [N] / Total tension saturation ceiling [N]
    DL_PRESS_MAX   : REAL := 1000.0;    // 辊面线压饱和上限 [N/mm] / Line pressure saturation ceiling [N/mm]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fWebWidthMm > -DL_BIG AND fWebWidthMm < DL_BIG)
   OR NOT (fUnitTensionNmm > -DL_BIG AND fUnitTensionNmm < DL_BIG)
   OR NOT (fRollDiaMm > -DL_BIG AND fRollDiaMm < DL_BIG) THEN
    fTensionN := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fLinePressNmm := 0.0;                   // 线压强制 0.0 / Line pressure forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_CoaterTensionZoneCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：幅宽是总张力的换算基准） —— *)
IF ABS(fWebWidthMm) <= DL_EPS THEN
    fTensionN := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fLinePressNmm := 0.0;                   // 线压强制 0.0 / Line pressure forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterTensionZoneCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（幅宽/单位张力/辊径均不可为负） —— *)
IF (fWebWidthMm < 0.0) OR (fUnitTensionNmm < 0.0) OR (fRollDiaMm < 0.0) THEN
    fTensionN := 0.0;                       // 输出强制 0.0 / Output forced to zero
    fLinePressNmm := 0.0;                   // 线压强制 0.0 / Line pressure forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_CoaterTensionZoneCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：总张力（R22 方向自核：幅宽乘单位张力，不是除） —— *)
_fTensionRawN := fWebWidthMm * fUnitTensionNmm;                  // 总张力 [N]

(* —— 段 5：辊面线压（分母为包角接触弧长，含辊径；R22 归一化口径已在此声明） —— *)
_fDiaClampMm := MAX(DL_DIA_MIN_MM, fRollDiaMm);                  // 辊径下限钳 [mm]
_fArcLenMm := DL_PI * _fDiaClampMm / DL_TWO;                     // 180° 包角接触弧长 [mm]
_fPressRawNmm := _fTensionRawN / _fArcLenMm;                     // 辊面线压 [N/mm]

(* —— 段 6：输出单点写盘（饱和钳制） —— *)
fTensionN := LIMIT(0.0, _fTensionRawN, DL_TEN_MAX);              // 总张力 [N]
fLinePressNmm := LIMIT(0.0, _fPressRawNmm, DL_PRESS_MAX);        // 辊面线压 [N/mm]

(* —— 段 7：有效位单点聚合 —— *)
xValid := (fWebWidthMm > DL_EPS)                                 // 幅宽为正
          AND (fUnitTensionNmm >= 0.0)                          // 单位张力非负
          AND (fRollDiaMm > DL_EPS);                            // 辊径为正（弧长可算）
FC_DL_CoaterTensionZoneCalc := xValid;                           // 返回码：TRUE = 计算可信

END_FUNCTION
