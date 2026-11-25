(*
  Name: FC_DL_GlassThicknessCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 浮法玻璃锡槽退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 玻璃带厚度按体积守恒式反算：单位时间流出的玻璃液体积 = 玻璃带截面积 × 拉引速度，
           即 Q = 带宽 × 厚度 × 拉引速度，故厚度 = Q / (带宽 × 拉引速度)。
           全部单位先统一到 SI（m3/s、m、m/s）再计算，最后乘 1000 转 mm；
           不允许混用 m3/h 与 mm 直接相除（那会得到 3.6e6 倍的错误量级）。
        2) 该式是浮法厚度控制的基准式：改厚度只能通过改拉引速度（拉薄/拉厚）或改拉引量实现，
           带宽由拉边机约束，故厚度的可调自由度主要落在速度上。
  边界条件：1) 非有限值闸：三路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（fThickMm 强制 0.0）并置无效（R19）。
        2) 分母零闸：带宽按 DL_W_MIN_MM(1.0 mm) 下限钳制后参与除法；
           拉引速度必须 ABS > DL_EPS（速度为 0 表示带不动，厚度无定义），否则判无效。
        3) 负值闸：拉引量、带宽、拉引速度任一为负判无效（不取绝对值掩盖反向）。
        4) 零值语义：拉引量为 0（断板/停拉）时厚度为 0，属合法工况但不具选型意义，
           不判无效；带宽为 0 与速度为 0 判无效（分母不可用）。
        5) 饱和钳制：厚度结果钳 0 ~ DL_THK_MAX_MM(100 mm)，防极小带宽与极低速度组合溢出。
  量纲自证：Q = m3/h ÷ 3600 (s/h) = m3/s；带宽 = mm ÷ 1000 (mm/m) = m；
           Q / (m × m/s) = (m3/s) / (m2/s) = m；再乘 1000 (mm/m) = mm，量纲闭合。
*)

FUNCTION FC_DL_GlassThicknessCalc : BOOL
VAR_INPUT
    fPullM3h       : REAL;   // 玻璃液拉引体积流量 [m3/h] / Glass pull volumetric flow [m3/h]
    fRibbonWidthMm : REAL;   // 玻璃带宽度 [mm] / Ribbon width [mm]
    fDrawMps       : REAL;   // 玻璃带拉引速度 [m/s] / Ribbon draw speed [m/s]
END_VAR
VAR_OUTPUT
    fThickMm       : REAL;   // 玻璃带厚度 [mm] / Ribbon thickness [mm]
    fAreaM2        : REAL;   // 玻璃带截面积（观测用）[m2] / Ribbon cross-section area [m2]
    xValid         : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fPullM3s      : REAL;   // 拉引流量 [m3/s] / Pull volumetric flow [m3/s]
    _fWidthM       : REAL;   // 钳制并换算后的带宽 [m] / Clamped width in metres [m]
    _fAreaRawM2    : REAL;   // 截面积 [m2] / Cross-section area [m2]
    _fThickRawM    : REAL;   // 未饱和的厚度 [m] / Raw thickness [m]
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_S_PER_H     : REAL := 3600.0;    // h → s 换算因子 [s/h] / Hour to second factor [s/h]
    DL_MM_PER_M    : REAL := 1000.0;    // m → mm 换算因子 [mm/m] / Metre to millimetre factor [mm/m]
    DL_W_MIN_MM    : REAL := 1.0;       // 带宽下限钳制值 [mm] / Width lower clamp [mm]
    DL_THK_MAX_MM  : REAL := 100.0;     // 厚度饱和上限 [mm] / Thickness saturation ceiling [mm]
END_VAR

(* —— 段 1：非有限值闸（R19：三路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fPullM3h > -DL_BIG AND fPullM3h < DL_BIG)
   OR NOT (fRibbonWidthMm > -DL_BIG AND fRibbonWidthMm < DL_BIG)
   OR NOT (fDrawMps > -DL_BIG AND fDrawMps < DL_BIG) THEN
    fThickMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fAreaM2 := 0.0;                         // 截面积强制 0.0 / Area forced to zero
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_GlassThicknessCalc := FALSE;      // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：分母零闸（R4：拉引速度是厚度分母） —— *)
IF ABS(fDrawMps) <= DL_EPS THEN
    fThickMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fAreaM2 := 0.0;                         // 截面积强制 0.0 / Area forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassThicknessCalc := FALSE;      // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：负值闸（流量与几何量均不可为负） —— *)
IF (fPullM3h < 0.0) OR (fRibbonWidthMm < 0.0) OR (fDrawMps < 0.0) THEN
    fThickMm := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fAreaM2 := 0.0;                         // 截面积强制 0.0 / Area forced to zero
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_GlassThicknessCalc := FALSE;      // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 4：单位统一（m3/h → m3/s，mm → m，两侧都必须先换算） —— *)
_fPullM3s := fPullM3h / DL_S_PER_H;                               // 拉引流量 [m3/s]
_fWidthM := MAX(DL_W_MIN_MM, fRibbonWidthMm) / DL_MM_PER_M;       // 带宽下限钳后换算 [m]

(* —— 段 5：体积守恒主算式（R22 方向自核：流量除以「面积 = 宽 × 速度」） —— *)
_fAreaRawM2 := _fPullM3s / fDrawMps;                              // 截面积 = Q / v [m2]
_fThickRawM := _fAreaRawM2 / _fWidthM;                            // 厚度 = 面积 / 宽 [m]

(* —— 段 6：输出单点写盘（m → mm，饱和钳制） —— *)
fAreaM2 := LIMIT(0.0, _fAreaRawM2, DL_BIG);                       // 截面积 [m2]
fThickMm := LIMIT(0.0, _fThickRawM * DL_MM_PER_M, DL_THK_MAX_MM); // 厚度 [mm]

(* —— 段 7：有效位单点聚合 —— *)
xValid := (fPullM3h >= 0.0)                                       // 拉引量非负
          AND (fRibbonWidthMm >= DL_W_MIN_MM)                     // 带宽不低于下限
          AND (fDrawMps > DL_EPS);                                // 速度为正（分母可用）
FC_DL_GlassThicknessCalc := xValid;                               // 返回码：TRUE = 计算可信

END_FUNCTION
