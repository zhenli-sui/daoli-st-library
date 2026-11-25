(*
  Name: FC_DL_AirCompLoadUnloadHystCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 加载/卸载压力带以目标压力为中心对称展开：加载压力 = 目标 − 回差/2，
           卸载压力 = 目标 + 回差/2。两点的间距恰为回差带宽，中心与目标压力重合，
           保证系统的长期平均压力不偏离设定值（若单侧展开会导致平均压力偏移）。
        2) 可行性判定 xViable 由三条独立条件聚合：
             a) 回差带宽不得小于「由最小循环时间反算的最小回差」：把频繁启停的成因归为
                单位时间内压力变化过快，故取经验压力变化速率 DL_RATE_BAR_PER_S 乘最小循环时间
                得到所需回差下限（bar/s × s = bar，量纲闭合），回差低于该下限判不可行；
             b) 储气罐缓冲自由空气容积（罐容积 × 回差 / 大气压）不得低于 DL_BUF_MIN，
                否则回差再大也被小罐吃掉，压力仍会抖动；
             c) 加载压力必须严格为正，否则加载点落到负压区，逻辑上永不加载。
        3) 输出加载/卸载压力供压力开关或控制器组态直接取用。
  边界条件：1) 非有限值闸：四路实值入参统一过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf，命中即拦断实值通路（两个压力输出强制 0.0、xViable 强制 FALSE）
           并置无效（R19），无效数据不得输出可组态的压力带。
        2) 分母零闸：本件除数仅为常量 2.0 与 DL_P_ATM_BAR，均为常量非零；
           但罐容积必须 > DL_EPS 才能得到有意义的缓冲容积，否则按 0 处理并判不可行。
        3) 负值闸：目标压力为负、回差为负、最小循环时间为负、罐容积为负均判无效
           （回差为负会使加载压力高于卸载压力，压力带反号，属组态错误）。
        4) 零值语义：回差为 0 表示无回差（加载点 = 卸载点，必然频繁启停），
           不判无效但 xViable 必为 FALSE，由可行性判定拦截。
        5) 饱和钳制：目标压力钳 0 ~ DL_P_MAX(40 bar)，回差钳 0 ~ DL_HYST_MAX(10 bar)，
           防组态越界把压力带推到量程外。
  量纲自证：fLoadBar = bar − bar/2 = bar；fUnloadBar = bar + bar/2 = bar，三条均为 bar；
           fHystNeedBar = (bar/s) × (s) = bar，与回差同量纲后方可比较；
           缓冲容积 = m3 × bar / bar = m3。
*)

FUNCTION FC_DL_AirCompLoadUnloadHystCalc : BOOL
VAR_INPUT
    fTargetBar      : REAL;   // 目标压力（压力带中心）[bar] / Target pressure, band centre [bar]
    fHystBar        : REAL;   // 回差带宽 [bar] / Hysteresis band width [bar]
    fMinCycleS      : REAL;   // 允许的最小循环时间 [s] / Minimum allowed cycle time [s]
    fRecvM3         : REAL;   // 储气罐有效容积 [m3] / Effective receiver volume [m3]
END_VAR
VAR_OUTPUT
    fLoadBar        : REAL;   // 加载压力 [bar] / Load pressure [bar]
    fUnloadBar      : REAL;   // 卸载压力 [bar] / Unload pressure [bar]
    fHystNeedBar    : REAL;   // 由最小循环时间反算的最小回差 [bar] / Minimum required hysteresis [bar]
    fBufferM3       : REAL;   // 回差带对应的缓冲自由空气容积 [m3] / Buffer free air volume [m3]
    xViable         : BOOL;   // 压力带可行标志 [bool] / Pressure band feasibility flag [bool]
    xValid          : BOOL;   // 计算有效标志 [bool] / Calculation valid flag [bool]
END_VAR
VAR
    _fTargetClamp   : REAL;   // 钳制后的目标压力 [bar] / Clamped target pressure [bar]
    _fHystClamp     : REAL;   // 钳制后的回差带宽 [bar] / Clamped hysteresis band [bar]
    _fHalfHyst      : REAL;   // 半回差 [bar] / Half hysteresis band [bar]
    _fLoadRawBar    : REAL;   // 未钳制的加载压力 [bar] / Raw load pressure [bar]
    _fUnloadRawBar  : REAL;   // 未钳制的卸载压力 [bar] / Raw unload pressure [bar]
END_VAR
VAR CONSTANT
    DL_EPS          : REAL := 1.0E-9;    // 分母零闸阈值 [-] / Division-zero gate threshold [-]
    DL_BIG          : REAL := 1.0E12;    // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_P_ATM_BAR    : REAL := 1.01325;   // 标准大气压 [bar] / Standard atmospheric pressure [bar]
    DL_P_MAX        : REAL := 40.0;      // 目标压力饱和上限 [bar] / Target pressure saturation ceiling [bar]
    DL_HYST_MAX     : REAL := 10.0;      // 回差带宽饱和上限 [bar] / Hysteresis saturation ceiling [bar]
    DL_RATE_BAR_S   : REAL := 0.0020;    // 经验压力变化速率 [bar/s] / Empirical pressure change rate [bar/s]
    DL_BUF_MIN      : REAL := 0.10;      // 缓冲自由空气容积下限 [m3] / Buffer free air volume lower bound [m3]
    DL_TWO          : REAL := 2.0;       // 半带宽除数（对称展开）[-] / Half-band divisor [-]
END_VAR

(* —— 段 1：非有限值闸（R19：四路入参全覆盖，拦 NaN 与 Inf） —— *)
IF NOT (fTargetBar > -DL_BIG AND fTargetBar < DL_BIG)
   OR NOT (fHystBar > -DL_BIG AND fHystBar < DL_BIG)
   OR NOT (fMinCycleS > -DL_BIG AND fMinCycleS < DL_BIG)
   OR NOT (fRecvM3 > -DL_BIG AND fRecvM3 < DL_BIG) THEN
    fLoadBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fUnloadBar := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fHystNeedBar := 0.0;                    // 最小回差强制 0.0 / Minimum hysteresis forced to zero
    fBufferM3 := 0.0;                       // 缓冲容积强制 0.0 / Buffer volume forced to zero
    xViable := FALSE;                       // 可行性强制 FALSE / Feasibility forced off
    xValid := FALSE;                        // 有效位清零 / Validity cleared
    FC_DL_AirCompLoadUnloadHystCalc := FALSE;   // 返回码同源 / Return mirrors validity
    RETURN;                                 // 立即退出 / Immediate exit
END_IF

(* —— 段 2：负值闸（回差为负会使加载压力高于卸载压力，压力带反号） —— *)
IF (fTargetBar < 0.0) OR (fHystBar < 0.0) OR (fMinCycleS < 0.0) OR (fRecvM3 < 0.0) THEN
    fLoadBar := 0.0;                        // 输出强制 0.0 / Output forced to zero
    fUnloadBar := 0.0;                      // 输出强制 0.0 / Output forced to zero
    fHystNeedBar := 0.0;                    // 最小回差强制 0.0 / Minimum hysteresis forced to zero
    fBufferM3 := 0.0;                       // 缓冲容积强制 0.0 / Buffer volume forced to zero
    xViable := FALSE;                       // 可行性强制 FALSE / Feasibility forced off
    xValid := FALSE;                        // 判无效 / Invalid
    FC_DL_AirCompLoadUnloadHystCalc := FALSE;   // 返回码同步 / Return synchronised
    RETURN;                                 // 提前退出 / Early exit
END_IF

(* —— 段 3：饱和钳制（目标压力与回差带宽各自量程） —— *)
_fTargetClamp := LIMIT(0.0, fTargetBar, DL_P_MAX);                // 目标压力钳 0..40 [bar]
_fHystClamp := LIMIT(0.0, fHystBar, DL_HYST_MAX);                 // 回差钳 0..10 [bar]

(* —— 段 4：对称展开压力带（R22 方向自核：加载在下、卸载在上，各偏半个回差） —— *)
_fHalfHyst := _fHystClamp / DL_TWO;                               // 半回差 [bar]
_fLoadRawBar := _fTargetClamp - _fHalfHyst;                       // 加载压力 = 目标 − 半回差 [bar]
_fUnloadRawBar := _fTargetClamp + _fHalfHyst;                     // 卸载压力 = 目标 + 半回差 [bar]

(* —— 段 5：可行性判据量（最小回差 / 缓冲容积） —— *)
fHystNeedBar := DL_RATE_BAR_S * fMinCycleS;                       // bar/s × s = bar
fBufferM3 := fRecvM3 * _fHystClamp / DL_P_ATM_BAR;                // m3 × bar / bar = m3

(* —— 段 6：输出单点写盘（压力带饱和钳制） —— *)
fLoadBar := LIMIT(0.0, _fLoadRawBar, DL_P_MAX);                   // 加载压力钳 0..40 [bar]
fUnloadBar := LIMIT(0.0, _fUnloadRawBar, DL_P_MAX);               // 卸载压力钳 0..40 [bar]

(* —— 段 7：有效位与可行性单点聚合 —— *)
xValid := (fTargetBar >= 0.0) AND (fTargetBar <= DL_P_MAX)        // 目标压力在量程内
          AND (fHystBar >= 0.0) AND (fHystBar <= DL_HYST_MAX)     // 回差在量程内
          AND (fMinCycleS >= 0.0)                                 // 最小循环时间非负
          AND (fRecvM3 >= 0.0);                                   // 罐容积非负
xViable := xValid                                                // 有效为前提
            AND (_fHystClamp >= fHystNeedBar)                    // 回差不低于最小回差
            AND (fBufferM3 >= DL_BUF_MIN)                        // 缓冲容积达标
            AND (fLoadBar > DL_EPS);                             // 加载点须为正压
FC_DL_AirCompLoadUnloadHystCalc := xValid;                        // 返回码：TRUE = 计算可信

END_FUNCTION
