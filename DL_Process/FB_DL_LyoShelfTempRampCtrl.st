(*
  Name: FB_DL_LyoShelfTempRampCtrl
  Category: DL_Process
  Version: 1.0.0
  Round: R91 / 2026-11-25
  开源溯源：clean-room 自研（族 制药冻干真空冷冻干燥，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 搁板温度斜坡发生器：设定值 fSetpointC 以 fRateUpKmin / fRateDownKmin 的斜率
           逐拍逼近目标温度 fTargetC，每拍增量 = 斜率[K/min] / 60 * fCycleS[s]，
           接近目标时按「不越过目标」截断，天然消除斜坡积分超调。
        2) 超调抑制：实测温度 fActualC 越过目标温度且超出 fOverShootLimitK 并持续 DL_OV_DELAY 后，
           判超调故障并锁码 —— 这是加热回路失控（固态继电器击穿或传感器脱落）的实证判据。
        3) 斜率上下限约束：fRateUpKmin / fRateDownKmin 必须落在 (0.0, DL_RATE_HI_KMIN] 内，
           越域判故障码（斜率为零会让设定值永不到达，斜率过大会撕裂制品冰晶结构）。
  边界条件：1) 非有限值闸：目标温度、实测温度、两路斜率、周期先过 NOT(x > -DL_BIG AND x < DL_BIG)，
           同时拦 NaN 与 Inf；命中即判故障码 0213 并进故障相，
           绝不把 NaN 写进设定值（NaN 一旦进入斜坡状态量会永久污染积分链，R19）。
        2) 周期入参闸（R21）：fCycleS <= 0.0 或非有限时改用缺省 DL_CYCLE_DEF = 0.1 s 并置信息级码 0212，
           不静默改用。
        3) 斜率零闸：两路斜率均须 > DL_EPS，否则判故障码 0214（斜坡永不推进 = 温度控制静默失效）。
        4) 超调判据去抖：超调为瞬时量，必须经 tonOver 去抖后才升级为故障，避免单点尖峰误停。
        5) 单点赋值（R26）：fSetpointC 只在段 7 统一出口写一次；内部设定量 _fSpC 才是逐拍累加的对象。
        6) 故障解除路径：故障相内 xReset 上升沿 AND NOT xFault AND 入参有限 → 清锁存回待机，
           回待机后设定值跟随实测温度重新起步（无扰切换），不从零开始。
        7) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相并置码 0217、清全部输出。
  量纲自证：斜率 [K/min] / 60 [s/min] * fCycleS [s] = 每拍增量 [K]，
           与 fSetpointC / fTargetC / fOverShootLimitK 同量纲 [K]（degC 差值以 K 计），量纲合法。
  码表 Error codes（本件子带 0091_021x，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0091_0211 信息级：使能关闭，设定值冻结在当下（不置故障位）
    16#0091_0212 信息级：周期入参非法，已按缺省 0.1 s 折算（不置故障位）
    16#0091_0213 故障级：温度或斜率入参非有限（NaN / Inf）
    16#0091_0214 故障级：斜率组态越域（为零或超物理上限）
    16#0091_0215 故障级：实测温度超调越限（加热回路失控判据）
    16#0091_0216 故障级：外部故障输入 xFault
    16#0091_0217 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R91 首版
*)

TYPE E_DL_LyoShelfRampState :
(
    eLyoRampIdle  := 0,     // 待机：使能关闭，设定值冻结 / Idle, disabled and setpoint frozen
    eLyoRampHeat  := 10,    // 升温：设定值按升斜率逼近目标 / Heating, setpoint ramps up to target
    eLyoRampCool  := 20,    // 降温：设定值按降斜率逼近目标 / Cooling, setpoint ramps down to target
    eLyoRampHold  := 30,    // 保持：设定值已达目标，进入保温带 / Hold, setpoint on target within the band
    eLyoRampFault := 90     // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_LyoShelfTempRampCtrl
VAR_INPUT
    xEnable        : BOOL;    // 斜坡控制使能 [bool] / Ramp control enable [bool]
    xReset         : BOOL;    // 故障复位（上升沿有效）[bool] / Fault reset, rising edge [bool]
    xFault         : BOOL;    // 外部故障汇总 [bool] / External fault aggregate [bool]
    fTargetC       : REAL;    // 搁板目标温度 [degC] / Shelf target temperature [degC]
    fActualC       : REAL;    // 搁板实测温度 [degC] / Shelf measured temperature [degC]
    fRateUpKmin    : REAL;    // 允许升温斜率 [K/min] / Permitted heating rate [K/min]
    fRateDownKmin  : REAL;    // 允许降温斜率 [K/min] / Permitted cooling rate [K/min]
    fCycleS        : REAL;    // 任务周期 [s] / Task cycle time [s]
    fBandK         : REAL;    // 到温判定带宽 [K] / At-target band width [K]
    fOverShootLimitK : REAL;  // 允许超调量 [K] / Permitted overshoot [K]
END_VAR
VAR_OUTPUT
    fSetpointC     : REAL;    // 搁板温度设定值 [degC] / Shelf temperature setpoint [degC]
    xHeating       : BOOL;    // 升温方向标志 [bool] / Heating direction flag [bool]
    xCooling       : BOOL;    // 降温方向标志 [bool] / Cooling direction flag [bool]
    xInBand        : BOOL;    // 已进入到温带 [bool] / Within the at-target band [bool]
    xOverShoot     : BOOL;    // 超调越限标志（已去抖）[bool] / Overshoot flag, debounced [bool]
    eState         : E_DL_LyoShelfRampState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId         : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonOver        : TON;     // 超调去抖定时 [TIME] / Overshoot debounce timer
    rtReset        : R_TRIG;  // 复位上升沿检测 [bool] / Reset rising edge detector
    _eState        : E_DL_LyoShelfRampState := E_DL_LyoShelfRampState.eLyoRampIdle;   // 内部相位（CASE 唯一写入目标）
    _fSpC          : REAL := 0.0;   // 内部设定值状态量（逐拍累加对象）[degC] / Internal setpoint state [degC]
    _fStepK        : REAL := 0.0;   // 本拍温度增量 [K] / Temperature increment this cycle [K]
    _fCycleUseS    : REAL := 0.1;   // 实际使用的周期值 [s] / Cycle time actually used [s]
    _bFinOk        : BOOL := FALSE; // 实值入参有限性总闸结果 / Finiteness gate aggregate result
    _bRateOk       : BOOL := FALSE; // 斜率组态域闸结果 / Ramp rate domain gate result
    _bCycleBad     : BOOL := FALSE; // 周期入参非法标志 [bool] / Cycle input invalid flag [bool]
    _bOverRaw      : BOOL := FALSE; // 超调原始判据（未去抖）[bool] / Raw overshoot criterion
    _bFault        : BOOL := FALSE; // 故障锁存位 [bool] / Latched fault flag [bool]
    _bSpInit       : BOOL := FALSE; // 设定值已初始化标志 [bool] / Setpoint initialised flag [bool]
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
    DL_RATE_HI_KMIN: REAL := 10.0;        // 允许斜率物理上限 [K/min] / Ramp rate physical upper bound [K/min]
    DL_OV_DELAY    : TIME := T#10S;       // 超调去抖窗 [TIME] / Overshoot debounce window [TIME]
    DL_T_SPAN      : REAL := 300.0;       // 温度量级闸跨度 [degC] / Temperature magnitude gate span [degC]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bSpInit 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;                     // 信息码每拍重算 / Info code recomputed
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：周期入参闸（R21：非法周期不静默，改用缺省并置信息码） —— *)
_bCycleBad := NOT (fCycleS > -DL_BIG AND fCycleS < DL_BIG)
              OR (fCycleS < DL_CYCLE_MIN) OR (fCycleS > DL_CYCLE_MAX);
IF _bCycleBad THEN
    _fCycleUseS := DL_CYCLE_DEF;            // 非法周期一律用缺省 0.1 s
    _uInfo := 16#0091_0212;                 // 信息级：周期入参非法，已用缺省（不置故障位）
ELSE
    _fCycleUseS := fCycleS;                 // 合法周期原值使用
END_IF

(* —— 段 2：非有限值闸与斜率域闸（R19：不把 NaN 写进斜坡状态量） —— *)
_bFinOk := (fTargetC > -DL_BIG) AND (fTargetC < DL_BIG)
           AND (fActualC > -DL_BIG) AND (fActualC < DL_BIG)
           AND (fRateUpKmin > -DL_BIG) AND (fRateUpKmin < DL_BIG)
           AND (fRateDownKmin > -DL_BIG) AND (fRateDownKmin < DL_BIG)
           AND (fBandK > -DL_BIG) AND (fBandK < DL_BIG)
           AND (fOverShootLimitK > -DL_BIG) AND (fOverShootLimitK < DL_BIG);
_bRateOk := (fRateUpKmin > DL_EPS) AND (fRateUpKmin <= DL_RATE_HI_KMIN)
            AND (fRateDownKmin > DL_EPS) AND (fRateDownKmin <= DL_RATE_HI_KMIN)
            AND (fBandK > DL_EPS) AND (fOverShootLimitK > DL_EPS)
            AND (ABS(fTargetC) <= DL_T_SPAN) AND (ABS(fActualC) <= DL_T_SPAN);

(* —— 段 3：超调原始判据（仅升温方向有意义：实测高于目标且超出允许量） —— *)
_bOverRaw := _bFinOk AND _bRateOk
             AND ((fActualC - fTargetC) > fOverShootLimitK);

(* —— 段 4：边沿与定时器无条件周期刷新（R7：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := xReset);                                             // 复位上升沿，每拍必调
tonOver(IN := _bOverRaw AND (NOT _bFault), PT := DL_OV_DELAY);      // 超调去抖

(* —— 段 5：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF xFault AND (NOT _bFault) THEN
    _uFault := 16#0091_0216;                // 故障级：外部故障输入
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_LyoShelfRampState.eLyoRampFault;
END_IF
IF (NOT _bFinOk) AND (NOT _bFault) THEN
    _uFault := 16#0091_0213;                // 故障级：入参非有限（独立成因，R190）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoShelfRampState.eLyoRampFault;
END_IF
IF (NOT _bRateOk) AND _bFinOk AND (NOT _bFault) THEN
    _uFault := 16#0091_0214;                // 故障级：斜率组态越域（独立成因，R190）
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoShelfRampState.eLyoRampFault;
END_IF
IF tonOver.Q AND (NOT _bFault) THEN
    _uFault := 16#0091_0215;                // 故障级：实测温度超调越限
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoShelfRampState.eLyoRampFault;
END_IF

(* —— 段 6：设定值起步（首次使能或无扰复位时以实测温度初始化，避免设定值从零跳变） —— *)
IF (NOT _bSpInit) AND _bFinOk THEN
    _fSpC := fActualC;                      // 无扰起步：设定值跟随实测温度
    _bSpInit := TRUE;                       // 标记已初始化
END_IF

(* —— 段 7：相位机（只做迁移与内部设定值更新；出口在段 9 单点映射） —— *)
CASE _eState OF

E_DL_LyoShelfRampState.eLyoRampIdle:
    IF NOT xEnable THEN
        _uInfo := 16#0091_0211;             // 信息级：使能关闭，设定值冻结（不置故障位）
    ELSIF (fTargetC - _fSpC) > fBandK THEN
        _eState := E_DL_LyoShelfRampState.eLyoRampHeat;       // 目标高于设定值：进升温相
    ELSIF (_fSpC - fTargetC) > fBandK THEN
        _eState := E_DL_LyoShelfRampState.eLyoRampCool;       // 目标低于设定值：进降温相
    ELSE
        _eState := E_DL_LyoShelfRampState.eLyoRampHold;       // 已在带内：进保持相
    END_IF

E_DL_LyoShelfRampState.eLyoRampHeat:
    IF (NOT xEnable) OR _bFault THEN
        _uInfo := 16#0091_0211;             // 信息级：失能即冻结设定值
        _eState := E_DL_LyoShelfRampState.eLyoRampIdle;
    ELSE
        _fStepK := fRateUpKmin / DL_SEC_PER_MIN * _fCycleUseS;                 // 每拍升温增量 [K]
        _fSpC := _fSpC + _fStepK;                                             // 累加
        IF _fSpC >= fTargetC THEN
            _fSpC := fTargetC;              // 不越过目标：天然消除斜坡超调
            _eState := E_DL_LyoShelfRampState.eLyoRampHold;
        END_IF
    END_IF

E_DL_LyoShelfRampState.eLyoRampCool:
    IF (NOT xEnable) OR _bFault THEN
        _uInfo := 16#0091_0211;             // 信息级：失能即冻结设定值
        _eState := E_DL_LyoShelfRampState.eLyoRampIdle;
    ELSE
        _fStepK := fRateDownKmin / DL_SEC_PER_MIN * _fCycleUseS;               // 每拍降温增量 [K]
        _fSpC := _fSpC - _fStepK;                                             // 累减
        IF _fSpC <= fTargetC THEN
            _fSpC := fTargetC;              // 不越过目标：天然消除斜坡超调
            _eState := E_DL_LyoShelfRampState.eLyoRampHold;
        END_IF
    END_IF

E_DL_LyoShelfRampState.eLyoRampHold:
    IF (NOT xEnable) OR _bFault THEN
        _uInfo := 16#0091_0211;             // 信息级：失能即回待机
        _eState := E_DL_LyoShelfRampState.eLyoRampIdle;
    ELSIF (fTargetC - _fSpC) > fBandK THEN
        _eState := E_DL_LyoShelfRampState.eLyoRampHeat;       // 目标抬高：重返升温相（判据在钉住之前取）
    ELSIF (_fSpC - fTargetC) > fBandK THEN
        _eState := E_DL_LyoShelfRampState.eLyoRampCool;       // 目标压低：重返降温相（判据在钉住之前取）
    ELSE
        _fSpC := fTargetC;                  // 带内才钉住设定值（避免判据恒真）
    END_IF

E_DL_LyoShelfRampState.eLyoRampFault:
    IF rtReset.Q AND (NOT xFault) AND _bFinOk AND _bRateOk THEN
        _bFault := FALSE;                   // 解除路径：复位沿 + 外部故障消失 + 入参与组态合法（可达，R188）
        _uFault := 16#0000_0000;            // 清锁存码
        _bSpInit := FALSE;                  // 强制无扰重启：设定值重新跟随实测温度
        _eState := E_DL_LyoShelfRampState.eLyoRampIdle;       // 回待机
    END_IF

ELSE
    _uFault := 16#0091_0217;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_LyoShelfRampState.eLyoRampFault;          // 强制回故障相

END_CASE

(* —— 段 8：后置段（设定值域兜底：非有限或越量级一律回落到实测温度） —— *)
IF NOT (_fSpC > -DL_BIG AND _fSpC < DL_BIG) THEN
    _fSpC := fActualC;                      // 内部状态自检：非有限即回落实测值
END_IF
(* —— 段 8.5：出口值域二阶终闸（R19 二阶形态）——
   一次闸的回退源是 fActualC，而 fActualC 本身也可能是非有限值（入参 NaN/Inf），
   回退后仍为 NaN，且 ABS(NaN) > DL_T_SPAN 恒假会绕过越量级钳制，NaN 直穿设定值出口。
   故必须对「回退之后」的值再做一次判据与钳制，才真正闸断实值通路。 *)
IF NOT (_fSpC >= -DL_T_SPAN AND _fSpC <= DL_T_SPAN) THEN
    _fSpC := 0.0;                           // 双源皆非有限：0 degC 安全位 / Both sources non-finite: 0 degC safe
END_IF
IF ABS(_fSpC) > DL_T_SPAN THEN
    _fSpC := LIMIT(-DL_T_SPAN, _fSpC, DL_T_SPAN);   // 越量级钳制，防积分链发散
END_IF

(* —— 段 9：出口单点映射（名实同源；方向位由设定值与目标差导出，故障侧全清） —— *)
IF _bFault THEN
    IF (fActualC >= -DL_T_SPAN) AND (fActualC <= DL_T_SPAN) THEN
        fSetpointC := fActualC;             // 故障侧优先回落实测温度（有限时保持原语义：冻结在实测）
    ELSE
        fSetpointC := _fSpC;                // 实测非有限时回落到已过二阶终闸的安全值，绝不输出 NaN
    END_IF;
    xHeating := FALSE;                      // 故障侧方向位清零
    xCooling := FALSE;                      // 故障侧方向位清零
    xInBand := FALSE;                       // 故障侧到温位清零
ELSE
    fSetpointC := _fSpC;                    // 正常侧设定值出口
    xHeating := (_eState = E_DL_LyoShelfRampState.eLyoRampHeat);      // 升温方向位
    xCooling := (_eState = E_DL_LyoShelfRampState.eLyoRampCool);      // 降温方向位
    xInBand := (_eState = E_DL_LyoShelfRampState.eLyoRampHold)        // 到温带：保持相且实测在带内
               AND (ABS(fActualC - fTargetC) <= fBandK);
END_IF
xOverShoot := tonOver.Q;                    // 超调位出口（已去抖）
eState := _eState;                          // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
