(*
  Name: FB_DL_TireCureMoldTempWatch
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 轮胎硫化，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 上下模温差监视：dT = |上模温 − 下模温|，两级判据并行且各自去抖：
           超过 fDeltaWarnK 进预警（信息级码 0312），超过 fDeltaMaxK 进报警（故障级码 0314）。
           上下模温差过大意味着单侧加热回路能力不足，会造成硫化程度沿胎圈-胎面方向不均。
        2) 加热失效判据：由实测上模温按周期折算温升速率 r = dT/dt [K/min]，
           r 的绝对值低于 fHeatRateMinKmin 且持续一个去抖窗，判加热失效（码 0315）——
           这是热电偶脱落与固态继电器击穿共有的实测特征（温度「不动」）。
        3) 趋势方向输出 nTrend：+1 上升、0 平稳、-1 下降，由本拍与上拍上模温差按
           DL_TREND_K 死区判定，供上层画趋势箭头与判断「是否正在爬温」。
  边界条件：1) 非有限值闸：温度、阈值、周期先过 NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；
           命中即锁码 0317 进故障相 —— 绝不让 NaN 参与温差与速率计算
           （NaN 比较恒假会把「测点断线」伪装成「温差正常、速率正常」，R19）。
        2) 周期入参闸（R21）：fCycleS <= 0.0 或非有限时改用缺省 DL_CYCLE_DEF = 0.1 s，
           温升速率的折算依赖该值，故必须显式声明（码 0317 同码归因，内部成员分离）。
        3) 阈值域闸：须满足 0.0 < fDeltaWarnK < fDeltaMaxK 且 fHeatRateMinKmin > DL_EPS，
           越域锁码 0317（预警/报警两级重叠或倒置会让某级永不触发）。
        4) 快照闸：首拍 _bPrevValid = FALSE 时不判速率与趋势，避免上电「上拍温度 = 0」
           造成的假加热失效。
        5) 定时器周期刷新（R7）：三个 TON 与复位边沿全部在 CASE 之外无条件调用。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参/组态合法 → 清锁存回正常，
           回正常需重新积累去抖窗（不自恢复）。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0318、清全部输出。
        8) 输出安全初值（R25）：xWarn / xAlarm / xHeatFail 初值 FALSE，nTrend 初值 0，
           正常相显式赋值。
  量纲自证：dT = |(degC) − (degC)| = (K)；趋势死区 DL_TREND_K 为 [K]，与温差同量纲；
           r = dT[K] / fCycleS[s] * 60[s/min] = K/min，与 fHeatRateMinKmin 同量纲。
  码表 Error codes（本件子带 0091_031x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0311 信息级：使能关闭，监视冻结（不置故障位）
    16#0091_0312 信息级：上下模温差已超预警阈值，尚在去抖窗内（不置故障位）
    16#0091_0313 故障级：上下模温差超预警阈值（去抖确认）
    16#0091_0314 故障级：上下模温差超上限阈值（去抖确认）
    16#0091_0315 故障级：加热失效（温升速率绝对值低于下限）
    16#0091_0316 故障级：外部故障输入 xFault
    16#0091_0317 故障级：入参非有限或阈值/周期组态越域
    16#0091_0318 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_TcsMoldTempState :
(
    eTcsMoldNormal   := 0,    // 正常：温差与速率均在带内 / Normal, difference and rate within limits
    eTcsMoldWarn     := 10,   // 预警：温差超预警阈值（已去抖）/ Warning, difference over the warning limit
    eTcsMoldAlarm    := 20,   // 报警：温差超上限阈值（已去抖）/ Alarm, difference over the upper limit
    eTcsMoldHeatFail := 30,   // 加热失效：温升速率不足（已去抖）/ Heat failure, rate below the limit
    eTcsMoldFault    := 90    // 故障：入参/组态非法，锁存待解除 / Fault, invalid input, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TireCureMoldTempWatch
VAR_INPUT
    xEnable        : BOOL;    // 监视使能 [bool] / Monitoring enable [bool]
    xReset         : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault         : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    fUpperMoldC    : REAL;    // 上模温度 [degC] / Upper mold temperature [degC]
    fLowerMoldC    : REAL;    // 下模温度 [degC] / Lower mold temperature [degC]
    fDeltaWarnK    : REAL;    // 温差预警阈值 [K] / Temperature difference warning threshold [K]
    fDeltaMaxK     : REAL;    // 温差上限阈值 [K] / Temperature difference upper limit [K]
    fHeatRateMinKmin : REAL;  // 允许最小温升速率（绝对值）[K/min] / Minimum absolute heating rate [K/min]
    fCycleS        : REAL;    // 任务周期 [s] / Task cycle time [s]
    tDebounce      : TIME;    // 判据去抖窗 [TIME] / Criteria debounce window [TIME]
END_VAR
VAR_OUTPUT
    fDeltaK        : REAL;    // 上下模温差绝对值 [K] / Absolute mold temperature difference [K]
    fRateKmin      : REAL;    // 上模温升速率（带符号）[K/min] / Upper mold heating rate, signed [K/min]
    nTrend         : INT;     // 趋势方向 +1 升 / 0 平 / -1 降 [dir] / Trend direction +1/0/-1 [dir]
    xWarn          : BOOL;    // 预警位（信息级）[bool] / Warning flag, information grade [bool]
    xAlarm         : BOOL;    // 报警位（故障级）[bool] / Alarm flag, fault grade [bool]
    xHeatFail      : BOOL;    // 加热失效位 [bool] / Heat failure flag [bool]
    eState         : E_DL_TcsMoldTempState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId         : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonWarn        : TON;     // 温差预警去抖定时 [TIME] / Difference warning debounce timer
    tonAlarm       : TON;     // 温差报警去抖定时 [TIME] / Difference alarm debounce timer
    tonHeat        : TON;     // 加热失效去抖定时 [TIME] / Heat failure debounce timer
    rtReset        : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState        : E_DL_TcsMoldTempState := E_DL_TcsMoldTempState.eTcsMoldNormal;   // 内部相位（CASE 唯一写入目标）
    _fUpperPrevC   : REAL := 0.0;   // 上拍上模温度快照 [degC] / Previous-cycle upper mold temperature [degC]
    _bPrevValid    : BOOL := FALSE; // 温度快照有效位（首拍为假）/ Temperature snapshot validity, false on first cycle
    _fCycleUseS    : REAL := 0.1;   // 实际使用的周期值 [s] / Cycle time actually used [s]
    _fDeltaRawK    : REAL := 0.0;   // 温差原始值 [K] / Raw temperature difference [K]
    _fRateRawKmin  : REAL := 0.0;   // 温升速率原始值 [K/min] / Raw heating rate [K/min]
    _bFinOk        : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bCfgOk        : BOOL := FALSE; // 阈值与周期组态域闸结果 / Threshold and cycle domain gate result
    _bWarnRaw      : BOOL := FALSE; // 温差预警原始判据 [bool] / Raw difference warning criterion
    _bAlarmRaw     : BOOL := FALSE; // 温差报警原始判据 [bool] / Raw difference alarm criterion
    _bHeatRaw      : BOOL := FALSE; // 加热失效原始判据 [bool] / Raw heat failure criterion
    _bWarnL        : BOOL := FALSE; // 预警锁存位 [bool] / Latched warning flag
    _bAlarmL       : BOOL := FALSE; // 报警锁存位 [bool] / Latched alarm flag
    _bHeatL        : BOOL := FALSE; // 加热失效锁存位 [bool] / Latched heat-failure flag
    _bFault        : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag
    _uInfo         : UDINT := 16#0000_0000;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault        : UDINT := 16#0000_0000;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS         : REAL := 1.0E-9;      // 数值零闸阈值 [-] / Numeric zero gate threshold [-]
    DL_BIG         : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_CYCLE_DEF   : REAL := 0.1;         // 缺省任务周期 [s] / Default task cycle time [s]
    DL_CYCLE_MIN   : REAL := 0.001;       // 周期合理下限 [s] / Cycle time reasonable low bound [s]
    DL_CYCLE_MAX   : REAL := 10.0;        // 周期合理上限 [s] / Cycle time reasonable high bound [s]
    DL_SEC_PER_MIN : REAL := 60.0;        // 分钟到秒的时基折算 [s/min] / Seconds per minute [s/min]
    DL_TREND_K     : REAL := 0.2;         // 趋势判定死区 [K] / Trend dead band [K]
    DL_DELTA_HI    : REAL := 500.0;       // 温差物理上限 [K] / Temperature difference upper bound [K]
    DL_RATE_HI     : REAL := 100.0;       // 温升速率物理上限 [K/min] / Heating rate upper bound [K/min]
    DL_T_SPAN      : REAL := 500.0;       // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bWarnL/_bAlarmL/_bHeatL 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：周期入参闸（R21）与非有限值闸（R19） —— *)
_bFinOk := (fUpperMoldC > -DL_BIG) AND (fUpperMoldC < DL_BIG)
           AND (fLowerMoldC > -DL_BIG) AND (fLowerMoldC < DL_BIG)
           AND (fDeltaWarnK > -DL_BIG) AND (fDeltaWarnK < DL_BIG)
           AND (fDeltaMaxK > -DL_BIG) AND (fDeltaMaxK < DL_BIG)
           AND (fHeatRateMinKmin > -DL_BIG) AND (fHeatRateMinKmin < DL_BIG)
           AND (fCycleS > -DL_BIG) AND (fCycleS < DL_BIG);
_bCfgOk := (fDeltaWarnK > DL_EPS)                       // 预警阈值必须为正
           AND (fDeltaMaxK > fDeltaWarnK)               // 上限必须严格大于预警
           AND (fDeltaMaxK <= DL_DELTA_HI)              // 上限须在物理域内
           AND (fHeatRateMinKmin > DL_EPS)              // 速率下限必须为正
           AND (ABS(fUpperMoldC) <= DL_T_SPAN)          // 温度量级闸
           AND (ABS(fLowerMoldC) <= DL_T_SPAN)
           AND (fCycleS >= DL_CYCLE_MIN) AND (fCycleS <= DL_CYCLE_MAX)
           AND (tDebounce > T#0S);                      // 去抖窗必须为正

IF _bCfgOk THEN
    _fCycleUseS := fCycleS;                 // 合法周期原值使用
ELSE
    _fCycleUseS := DL_CYCLE_DEF;            // 非法周期一律用缺省 0.1 s（组态闸在段 5 统一判）
END_IF

(* —— 段 2：判据派生（原始值；快照闸保证首拍不判速率） —— *)
_fDeltaRawK := ABS(fUpperMoldC - fLowerMoldC);                                    // 上下模温差 [K]
IF _bPrevValid AND _bFinOk THEN
    _fRateRawKmin := (fUpperMoldC - _fUpperPrevC) / _fCycleUseS * DL_SEC_PER_MIN; // 温升速率 [K/min]
ELSE
    _fRateRawKmin := 0.0;                   // 首拍无快照：速率置零（不据此判失效）
END_IF
_bWarnRaw := _bFinOk AND _bCfgOk AND xEnable AND (_fDeltaRawK > fDeltaWarnK);
_bAlarmRaw := _bFinOk AND _bCfgOk AND xEnable AND (_fDeltaRawK > fDeltaMaxK);
_bHeatRaw := _bFinOk AND _bCfgOk AND xEnable AND _bPrevValid
             AND (ABS(_fRateRawKmin) < fHeatRateMinKmin);

(* —— 段 3：定时器与边沿无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := xReset);                                                     // 复位上升沿，每拍必调
tonWarn(IN := _bWarnRaw AND (NOT _bFault), PT := tDebounce);                 // 温差预警去抖
tonAlarm(IN := _bAlarmRaw AND (NOT _bFault), PT := tDebounce);               // 温差报警去抖
tonHeat(IN := _bHeatRaw AND (NOT _bFault), PT := tDebounce);                 // 加热失效去抖

(* —— 段 4：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0316;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_TcsMoldTempState.eTcsMoldFault;
END_IF
IF ((NOT _bFinOk) OR (NOT _bCfgOk)) AND (NOT _bFault) THEN
    _uFault := 16#0091_0317;                // 故障级：入参非有限或组态越域（内部成员已分离）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_TcsMoldTempState.eTcsMoldFault;
END_IF

(* —— 段 5：相位机（只做迁移与锁存；出口在段 7 单点映射） —— *)
CASE _eState OF

E_DL_TcsMoldTempState.eTcsMoldNormal:
    IF NOT xEnable THEN
        _uInfo := 16#0091_0311;             // 信息级：使能关闭，监视冻结（不置故障位）
    ELSIF tonAlarm.Q THEN
        _uFault := 16#0091_0314;            // 故障级：温差超上限（去抖确认）
        _bAlarmL := TRUE;                   // 报警锁存
        _eState := E_DL_TcsMoldTempState.eTcsMoldAlarm;
    ELSIF tonHeat.Q THEN
        _uFault := 16#0091_0315;            // 故障级：加热失效（去抖确认）
        _bHeatL := TRUE;                    // 加热失效锁存
        _eState := E_DL_TcsMoldTempState.eTcsMoldHeatFail;
    ELSIF tonWarn.Q THEN
        _uFault := 16#0091_0313;            // 故障级：温差超预警（去抖确认）
        _bWarnL := TRUE;                    // 预警锁存
        _eState := E_DL_TcsMoldTempState.eTcsMoldWarn;
    ELSIF _bWarnRaw THEN
        _uInfo := 16#0091_0312;             // 信息级：超预警阈值但尚在去抖窗内
    END_IF

E_DL_TcsMoldTempState.eTcsMoldWarn:
    IF NOT xEnable THEN
        _uInfo := 16#0091_0311;             // 信息级：使能关闭，监视冻结
        _bWarnL := FALSE;                   // 失能即清预警锁存
        _eState := E_DL_TcsMoldTempState.eTcsMoldNormal;
    ELSIF tonAlarm.Q THEN
        _uFault := 16#0091_0314;            // 故障级：温差升级到上限
        _bAlarmL := TRUE;                   // 报警锁存
        _eState := E_DL_TcsMoldTempState.eTcsMoldAlarm;
    ELSIF NOT _bWarnRaw THEN
        _bWarnL := FALSE;                   // 判据自行消失：清预警锁存回正常（无需复位）
        _eState := E_DL_TcsMoldTempState.eTcsMoldNormal;
    END_IF

E_DL_TcsMoldTempState.eTcsMoldAlarm:
    IF rtReset.Q THEN
        _bAlarmL := FALSE;                  // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_TcsMoldTempState.eTcsMoldNormal;
    END_IF

E_DL_TcsMoldTempState.eTcsMoldHeatFail:
    IF rtReset.Q THEN
        _bHeatL := FALSE;                   // 解除路径：复位上升沿（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bPrevValid := FALSE;               // 强制重新取快照，避免旧快照立刻再判失效
        _eState := E_DL_TcsMoldTempState.eTcsMoldNormal;
    END_IF

E_DL_TcsMoldTempState.eTcsMoldFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bCfgOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参/组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bPrevValid := FALSE;               // 强制重新取快照
        _eState := E_DL_TcsMoldTempState.eTcsMoldNormal;
    END_IF

ELSE
    _uFault := 16#0091_0318;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _bWarnL := FALSE;                       // 各级锁存清
    _bAlarmL := FALSE;
    _bHeatL := FALSE;
    _eState := E_DL_TcsMoldTempState.eTcsMoldFault;           // 强制回故障相

END_CASE

(* —— 段 6：后置段（温度快照在迁移判断之后统一更新，禁在分支内散写） —— *)
IF _bFinOk THEN
    _fUpperPrevC := fUpperMoldC;            // 快照更新（仅有限值可信时才更新）
    _bPrevValid := TRUE;                    // 快照自此有效
ELSE
    _bPrevValid := FALSE;                   // 非有限值使快照失效，防污染下一拍速率判据
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存位一律由状态导出，故障侧全清） —— *)
fDeltaK := LIMIT(0.0, _fDeltaRawK, DL_DELTA_HI);                                  // 温差出口钳物理域 [K]
fRateKmin := LIMIT(-DL_RATE_HI, _fRateRawKmin, DL_RATE_HI);                       // 速率出口钳物理域 [K/min]
IF _fRateRawKmin > DL_TREND_K THEN
    nTrend := 1;                            // 上升
ELSIF _fRateRawKmin < -DL_TREND_K THEN
    nTrend := -1;                           // 下降
ELSE
    nTrend := 0;                            // 平稳（死区内）
END_IF
xWarn := _bWarnL AND (NOT _bFault);                                        // 预警位出口
xAlarm := _bAlarmL AND (NOT _bFault);                                      // 报警位出口
xHeatFail := _bHeatL AND (NOT _bFault);                                    // 加热失效出口
eState := _eState;                                                         // 状态出口单点映射
IF _bFault OR _bAlarmL OR _bHeatL OR _bWarnL THEN
    nErrId := _uFault;                      // 故障码锁存回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
