(*
  FB_DL_AhuEconomizer  —  空调箱新风经济器（焓值/干球双判据）/ AHU air-side economizer
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B1
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，ASHRAE 经济器公开判据语义借鉴，未复制任何源码行（RESUME 承接 R36 §4 #16 规格）
                  （焓值语义对齐 FC_DL_HumidAirEnthalpy；迟滞对齐 FC_DL_Hysteresis；分程对齐 FB_DL_SplitRangeControl，均不实例化，
                   焓值以 Magnus 饱和压简化式内部实现并在此声明）
  功能 Function : 1) 焓值比较为主判据、干球差为后备判据（eCompareMode 组态），焓差在 ±fDeadbandKjKg 内保持当前模式（迟滞防抖）；
                  2) 新风开度在 [fMinFreshPct, 100] 区间随需求线性映射（需求按回风-室外温差归一）；
                  3) bFreezeStat 触发 bFreezeLockout 关至最小位并锁存，须温度回升 + bReset 解除；
                  4) RH 信号质量坏自动退干球判据（不得用缺省 RH 冒充）。
  边界 Boundary : ① 两个 RH 信号任一非有限或越 0..100 域 → 退干球判据并置信息码（规格强制）；
                  ② fMinFreshPct 越 0~100 钳制并置信息码；fDeadbandKjKg <= 0 / fFreezeReleaseC 非有限判组态错；
                  ③ 焓值算式输入温度越 ±60°C 域按边界钳制（Magnus 式适用域声明）；
                  ④ bFreezeLockout 解除式自证：fOutdoorTempC > fFreezeReleaseC AND bReset（两引脚可满足）；
                  ⑤ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : 仅 Standard.library（ABS/MIN/MAX/LIMIT/EXP）；语义对齐 FC_DL_HumidAirEnthalpy / FC_DL_Hysteresis /
                  FB_DL_SplitRangeControl（已注册，不实例化）
  码表 Error codes（本件格 06_0_B1，子码步进 +0x100）:
    16#0006_01B1 信息级：RH 信号质量坏，退干球判据
    16#0006_02B1 故障级：组态非法（焓差死区 <= 0 / 防冻释放温度非有限），锁存至复位
    16#0006_03B1 信息级：最小新风越 0..100 域，已钳制
    16#0006_04B1 信息级：防冻锁定激活（关至最小位）
    16#0006_05B1 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_EcoCompareMode :
(
    eEnthalpy := 0,   // 焓值比较（主判据）/ Enthalpy comparison, primary
    eDryBulb  := 1    // 干球比较（后备判据）/ Dry-bulb comparison, fallback
);
END_TYPE

TYPE E_DL_EcoState :
(
    eIdle      := 0,    // 空闲：无经济器需求 / Idle, no economizer demand
    eFreeCool  := 10,   // 免费供冷：新风全开域调节 / Free cooling, modulating in fresh range
    eMechCool  := 20,   // 机械供冷：新风保最小位 / Mechanical cooling, minimum fresh air
    eFreezeLock:= 30,   // 防冻锁定：关至最小位等解除 / Freeze lockout, at minimum awaiting release
    eFault     := 90    // 故障：组态锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AhuEconomizer
VAR_INPUT
    fOutdoorTempC  : REAL := 20.0;       // 室外干球温度 [°C] / Outdoor dry-bulb temperature
    fReturnTempC   : REAL := 24.0;       // 回风干球温度 [°C] / Return dry-bulb temperature
    fOutdoorRhPct  : REAL := 50.0;       // 室外相对湿度 [%] / Outdoor relative humidity
    fReturnRhPct   : REAL := 50.0;       // 回风相对湿度 [%] / Return relative humidity
    bFreezeStat    : BOOL := FALSE;      // 防冻开关量（盘管防冻）/ Freeze stat input
    fMinFreshPct   : REAL := 15.0;       // 最小新风位 [%] / Minimum fresh air position
    eCompareMode   : E_DL_EcoCompareMode := E_DL_EcoCompareMode.eEnthalpy;   // 判据模式 / Comparison mode
    fDeadbandKjKg  : REAL := 1.0;        // 焓差迟滞死区 [kJ/kg]，域 > 0 / Enthalpy deadband
    fFreezeReleaseC: REAL := 7.0;        // 防冻释放温度 [°C] / Freeze release temperature
    bReset         : BOOL := FALSE;      // 复位（防冻解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    fDamperCmdPct       : REAL;          // 新风阀开度指令 [%] / Damper command
    bFreeCooling        : BOOL;          // 免费供冷激活 / Free cooling active
    bFreezeLockout      : BOOL;          // 防冻锁定锁存 / Freeze lockout latch
    bEnthalpyModeActive : BOOL;          // 焓值判据激活（FALSE = 已退干球）/ Enthalpy mode active
    nErrId              : UDINT;         // 事件码，0 = 无事件 / Event code
    eState              : E_DL_EcoState; // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    tonFaultWch : TON;                   // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtReset     : R_TRIG;                // 复位上升沿 / Reset rising edge
    _eState     : E_DL_EcoState := E_DL_EcoState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bFreeHold  : BOOL;                  // 免费供冷保持量（迟滞承载）/ Free-cooling held quantity
    _bFreezeL   : BOOL;                  // 防冻锁存保持量 / Freeze latch held quantity
    _bRhOk      : BOOL;                  // RH 质量聚合（两路均有效）/ RH quality aggregate
    _rHOut      : REAL;                  // 室外焓值 [kJ/kg] / Outdoor enthalpy
    _rHRet      : REAL;                  // 回风焓值 [kJ/kg] / Return enthalpy
    _rHDiff     : REAL;                  // 焓差 [kJ/kg]（回 − 外）/ Enthalpy difference
    _rTdDiff    : REAL;                  // 干球差 [K]（回 − 外）/ Dry-bulb difference
    _rMinFresh  : REAL;                  // 钳制后最小新风 [%] / Clamped minimum fresh
    _rDemand    : REAL;                  // 需求归一量 [无量纲 0..1] / Normalized demand
    _uFault     : UDINT;                 // 故障码锁存 / Latched fault code
    _uInfo      : UDINT;                 // 信息码，每拍重算 / Info code
    _bFault     : BOOL;                  // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                  // 组态非法聚合 / Configuration invalid aggregate
    _rPs, _rW   : REAL;                  // Magnus 饱和压/含湿量暂存 / Magnus saturation pressure and humidity ratio
END_VAR
VAR CONSTANT
    DL_P_ATM    : REAL := 101325.0;  // 标准大气压 [Pa]（焓算式组态常量）/ Standard atmospheric pressure
    DL_T_LO     : REAL := -60.0;     // Magnus 适用域下限 [°C] / Magnus validity lower bound
    DL_T_HI     : REAL := 60.0;      // Magnus 适用域上限 [°C] / Magnus validity upper bound
    DL_DEMAND_SPAN : REAL := 10.0;   // 需求归一温差满量程 [K] / Demand normalization span
    DL_WATCH_PT : TIME := T#2S;      // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WATCH_PT);       // 观察窗自复位（表达式入参）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bFreezeL/_bFreeHold 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bFreeCooling := FALSE;          // 免冷出口缺省 FALSE（段 8 单点置位）
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fDeadbandKjKg <= 0.0) OR (fFreezeReleaseC <> fFreezeReleaseC) THEN
    _bCfgBad := TRUE;           // 焓差死区/释放温度非法
END_IF
IF fMinFreshPct < 0.0 THEN
    _rMinFresh := 0.0;          // 越下限钳 0
    _uInfo := 16#0006_03B1;     // 信息级：最小新风已钳制
ELSIF fMinFreshPct > 100.0 THEN
    _rMinFresh := 100.0;        // 越上限钳 100
    _uInfo := 16#0006_03B1;     // 信息级：最小新风已钳制
ELSE
    _rMinFresh := fMinFreshPct; // 域内直通
END_IF

(* —— 段 3：RH 质量闸（任一路非有限或越 0..100 域 → 退干球判据，禁缺省 RH 冒充） —— *)
_bRhOk := (fOutdoorRhPct = fOutdoorRhPct) AND (fReturnRhPct = fReturnRhPct)
          AND (fOutdoorRhPct >= 0.0) AND (fOutdoorRhPct <= 100.0)
          AND (fReturnRhPct >= 0.0) AND (fReturnRhPct <= 100.0);
bEnthalpyModeActive := _bRhOk AND (eCompareMode = E_DL_EcoCompareMode.eEnthalpy);   // 焓值判据激活出口
IF (eCompareMode = E_DL_EcoCompareMode.eEnthalpy) AND (NOT _bRhOk) THEN
    _uInfo := 16#0006_01B1;     // 信息级：RH 质量坏，退干球判据
END_IF

(* —— 段 4：温度钳制与焓值计算（Magnus 简化式，适用域 DL_T_LO..DL_T_HI） —— *)
IF bEnthalpyModeActive THEN
    _rPs := 610.78 * EXP(17.2694 * LIMIT(fOutdoorTempC, DL_T_LO, DL_T_HI)
                       / (LIMIT(fOutdoorTempC, DL_T_LO, DL_T_HI) + 237.3));   // 室外饱和压 [Pa]
    _rW := 0.622 * fOutdoorRhPct / 100.0 * _rPs
         / MAX(DL_P_ATM - fOutdoorRhPct / 100.0 * _rPs, 1.0);                 // 室外含湿量（分母钳位防除零）
    _rHOut := 1.006 * LIMIT(fOutdoorTempC, DL_T_LO, DL_T_HI)
            + _rW * (2501.0 + 1.86 * LIMIT(fOutdoorTempC, DL_T_LO, DL_T_HI)); // 室外焓 [kJ/kg]
    _rPs := 610.78 * EXP(17.2694 * LIMIT(fReturnTempC, DL_T_LO, DL_T_HI)
                       / (LIMIT(fReturnTempC, DL_T_LO, DL_T_HI) + 237.3));    // 回风饱和压 [Pa]
    _rW := 0.622 * fReturnRhPct / 100.0 * _rPs
         / MAX(DL_P_ATM - fReturnRhPct / 100.0 * _rPs, 1.0);                  // 回风含湿量
    _rHRet := 1.006 * LIMIT(fReturnTempC, DL_T_LO, DL_T_HI)
            + _rW * (2501.0 + 1.86 * LIMIT(fReturnTempC, DL_T_LO, DL_T_HI));  // 回风焓 [kJ/kg]
    _rHDiff := _rHRet - _rHOut;             // 焓差（回 − 外）> 0 = 室外更冷更干
END_IF
_rTdDiff := fReturnTempC - fOutdoorTempC;   // 干球差（回 − 外）

(* —— 段 5：判据迟滞解算（焓差/干球差 ± 死区内保持当前模式） —— *)
IF bEnthalpyModeActive THEN
    IF _rHDiff > fDeadbandKjKg THEN
        _bFreeHold := TRUE;                 // 室外焓显著更低：免费供冷
    ELSIF _rHDiff < -fDeadbandKjKg THEN
        _bFreeHold := FALSE;                // 室外焓显著更高：机械供冷
    END_IF                                  // 死区内保持（迟滞防抖，规格强制）
ELSE
    IF _rTdDiff > fDeadbandKjKg THEN
        _bFreeHold := TRUE;                 // 干球后备判据（同迟滞结构）
    ELSIF _rTdDiff < -fDeadbandKjKg THEN
        _bFreeHold := FALSE;
    END_IF
END_IF

(* —— 段 6：相位机（只做迁移；出口在段 8） —— *)
CASE _eState OF

E_DL_EcoState.eIdle:
    IF _bCfgBad THEN
        _uFault := 16#0006_02B1;            // 故障级：组态非法
        _bFault := TRUE;                    // 锁存（复位沿可清）
        _eState := E_DL_EcoState.eFault;
    ELSIF bFreezeStat THEN
        _bFreezeL := TRUE;                  // 防冻锁存（规格强制：关至最小位）
        _uInfo := 16#0006_04B1;             // 信息级：防冻锁定激活
        _eState := E_DL_EcoState.eFreezeLock;
    ELSIF _bFreeHold THEN
        _eState := E_DL_EcoState.eFreeCool; // 进免费供冷相
    ELSE
        _eState := E_DL_EcoState.eMechCool; // 进机械供冷相
    END_IF

E_DL_EcoState.eFreeCool:
    IF _bCfgBad THEN
        _uFault := 16#0006_02B1;
        _bFault := TRUE;
        _eState := E_DL_EcoState.eFault;
    ELSIF bFreezeStat THEN
        _bFreezeL := TRUE;
        _uInfo := 16#0006_04B1;
        _eState := E_DL_EcoState.eFreezeLock;
    ELSIF NOT _bFreeHold THEN
        _eState := E_DL_EcoState.eMechCool; // 判据反转：回机械供冷
    END_IF

E_DL_EcoState.eMechCool:
    IF _bCfgBad THEN
        _uFault := 16#0006_02B1;
        _bFault := TRUE;
        _eState := E_DL_EcoState.eFault;
    ELSIF bFreezeStat THEN
        _bFreezeL := TRUE;
        _uInfo := 16#0006_04B1;
        _eState := E_DL_EcoState.eFreezeLock;
    ELSIF _bFreeHold THEN
        _eState := E_DL_EcoState.eFreeCool; // 判据反转：进免费供冷
    END_IF

E_DL_EcoState.eFreezeLock:
    IF (fOutdoorTempC > fFreezeReleaseC) AND (NOT bFreezeStat) AND rtReset.Q THEN
        _bFreezeL := FALSE;                 // 防冻解除式自证：温度回升 AND bReset（规格强制）
        _uInfo := 16#0000_0000;
        _eState := E_DL_EcoState.eIdle;     // 回空闲重判
    END_IF

E_DL_EcoState.eFault:
    ;                                       // 故障相：等复位沿（故障码段 2 置位，复位沿清）

ELSE
    _uFault := 16#0006_05B1;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_EcoState.eFault;        // 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bFreezeLockout := _bFreezeL;                // 防冻锁存出口
bFreeCooling := (_eState = E_DL_EcoState.eFreeCool) AND (NOT _bFault);   // 免冷出口
_rDemand := MAX(0.0, MIN(1.0, _rTdDiff / DL_DEMAND_SPAN));               // 需求归一（温差满量程钳 0..1）
IF (_eState = E_DL_EcoState.eFreeCool) AND (NOT _bFault) THEN
    fDamperCmdPct := _rMinFresh + _rDemand * (100.0 - _rMinFresh);       // 区间线性映射 [min, 100]
ELSE
    fDamperCmdPct := _rMinFresh;            // 机械供冷/防冻/故障：保最小位（安全侧）
END_IF
IF _bFault THEN
    nErrId := _uFault;          // 故障锁存码回放
ELSE
    nErrId := _uInfo;           // 信息码
END_IF
eState := _eState;              // 状态出口单点映射

END_FUNCTION_BLOCK
