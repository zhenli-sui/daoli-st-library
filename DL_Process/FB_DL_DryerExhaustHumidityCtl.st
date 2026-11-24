(*
  FB_DL_DryerExhaustHumidityCtl  —  干燥排湿热回收风门控制 / Dryer exhaust humidity control with heat recovery dampers
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8B
  版本 Version  : 1.0.1
  溯源 Source   : OSCAT Building 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  修改记录 Hist : v1.0.1 2026-11-23 R75 修复——FC_DL_HumidAirEnthalpy 两处调用
                  补 uErrorId => 显式回执接收（R73 零回执挂账点修），新增
                  接收变量 uEnthErrFresh / uEnthErrRet，回执仅作诊断暂存，
                  主逻辑零改动
  功能 Function : 1) 以焓值判据（回风焓 − 新风焓 超过死区）决定排湿风门开度，实现排湿与热回收兼顾；
                  2) 排湿风门与混风风门互斥，同拍双开判冲突并双双回安全位；
                  3) 回风温度越上限时强制加大排湿并置码（安全侧优先，不参与焓值比较）。
  边界 Boundary : ① 焓值计算前先判干球/含湿量有效域（含湿量由焓值函数内部同口径给出，域外钳位照算）；
                  ② 排湿与混风阀开度互斥，同拍双开即判冲突并回安全位；
                  ③ 回风温度越上限强制加大排湿并置码；
                  ④ 风门输出三行同向：排湿开度 → 混风开度 → 冲突标志。
  依赖 Depends  : FC_DL_HumidAirEnthalpy（新风/回风焓值，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068B 故障级：组态非法（死区 < 0 / 开度上下限倒置 / 回风温度上限 <= 0）
    16#0002_069B 故障级：排湿与混风同时开（互斥冲突），双双回安全位
    16#0002_06AB 信息级：回风温度越上限，已强制加大排湿（不置 bError）
*)

TYPE E_DL_DehcPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCompare := 10,  // 焓值比较 / Enthalpy comparison
    eExhaust := 20,  // 排湿优先 / Exhaust priority
    eRecover := 30,  // 热回收混风 / Heat recovery mixing
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_DryerExhaustHumidityCtl
VAR_INPUT
    bEnable        : BOOL;                        // 总使能，FALSE 风门回安全位 / Master enable
    bReset         : BOOL;                        // 复位，上升沿清故障 / Reset, clears fault
    fFreshTempC    : REAL;                        // 新风干球温度 [degC]，域 −40~120 / Fresh air dry-bulb [degC]
    fFreshRhPct    : REAL;                        // 新风相对湿度 [%]，域 0~100 / Fresh air relative humidity [%]
    fReturnTempC   : REAL;                        // 回风干球温度 [degC]，域 −40~120 / Return air dry-bulb [degC]
    fReturnRhPct   : REAL;                        // 回风相对湿度 [%]，域 0~100 / Return air relative humidity [%]
    fLoadPct       : REAL;                        // 干燥负载（排湿需求）[%]，域 0~100 / Dryer load demand [%]
    fEnthDeadKJkg  : REAL := 5.0;                 // 焓差死区 [kJ/kg]，域 >= 0 / Enthalpy deadband [kJ/kg]
    fReturnTempMaxC: REAL := 90.0;                // 回风温度上限 [degC]，域 > 0 / Return temperature limit [degC]
    fDamperMinPct  : REAL := 0.0;                 // 风门开度下限 [%] / Damper opening low [%]
    fDamperMaxPct  : REAL := 100.0;               // 风门开度上限 [%] / Damper opening high [%]
    fEps           : REAL := 1.0E-6;              // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fExhaustPct    : REAL;                        // 排湿风门开度 [%] / Exhaust damper opening [%]
    fMixPct        : REAL;                        // 混风（热回收）风门开度 [%] / Mixing damper opening [%]
    fEnthFreshKJkg : REAL;                        // 新风焓值 [kJ/kg 干空气] / Fresh air enthalpy [kJ/kg dry air]
    fEnthReturnKJkg: REAL;                        // 回风焓值 [kJ/kg 干空气] / Return air enthalpy [kJ/kg dry air]
    fEnthDiffKJkg  : REAL;                        // 焓差（回风 − 新风）[kJ/kg] / Enthalpy difference [kJ/kg]
    bDamperConflict: BOOL;                        // 风门互斥冲突标志 / Damper exclusion conflict flag
    bTempForced    : BOOL;                        // 回风超温强制排湿标志 / Return over-temperature forcing flag
    bError         : BOOL;                        // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId       : UDINT;                       // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut      : E_DL_DehcPhase;              // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState        : E_DL_DehcPhase := E_DL_DehcPhase.eIdle;  // 内部状态 / Internal state
    rtrReset       : R_TRIG;                      // 复位沿 / Reset edge
    bCfgOk         : BOOL;                        // 组态合法标志 / Configuration valid
    bFreshOk       : BOOL;                        // 新风参数有效 / Fresh air parameters valid
    bReturnOk      : BOOL;                        // 回风参数有效 / Return air parameters valid
    fExhCmd        : REAL;                        // 排湿开度指令暂存 [%] / Exhaust command buffer [%]
    fMixCmd        : REAL;                        // 混风开度指令暂存 [%] / Mixing command buffer [%]
    fHFresh        : REAL;                        // 新风焓值暂存 [kJ/kg] / Fresh enthalpy buffer
    fHReturn       : REAL;                        // 回风焓值暂存 [kJ/kg] / Return enthalpy buffer
    uFault         : UDINT;                       // 锁存故障码 / Latched fault code
    uInfo          : UDINT;                       // 信息级码 / Information code
    uEnthErrFresh  : UDINT;                       // 新风焓值函数回执码（v1.0.1 新增接收）/ Fresh enthalpy FC receipt
    uEnthErrRet    : UDINT;                       // 回风焓值函数回执码（v1.0.1 新增接收）/ Return enthalpy FC receipt
END_VAR
VAR CONSTANT
    DL_DEHC_TMIN   : REAL := -40.0;               // 温度域下限 [degC] / Temperature domain low
    DL_DEHC_TMAX   : REAL := 120.0;               // 温度域上限 [degC] / Temperature domain high
    DL_DEHC_FORCE  : REAL := 100.0;               // 超温强制排湿开度 [%] / Forced exhaust opening [%]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与焓值入参域闸 === *)
bCfgOk := (fEnthDeadKJkg >= 0.0) AND (fDamperMaxPct > fDamperMinPct)
          AND (fReturnTempMaxC > 0.0) AND (fEnthDeadKJkg = fEnthDeadKJkg)
          AND (fReturnTempMaxC = fReturnTempMaxC);                  // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_068B;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bDamperConflict := FALSE;                     // 冲突标志同步复位
END_IF
bFreshOk := (fFreshTempC = fFreshTempC) AND (fFreshRhPct = fFreshRhPct)
            AND (fFreshTempC >= DL_DEHC_TMIN) AND (fFreshTempC <= DL_DEHC_TMAX)
            AND (fFreshRhPct >= 0.0) AND (fFreshRhPct <= 100.0);       // 新风域闸
bReturnOk := (fReturnTempC = fReturnTempC) AND (fReturnRhPct = fReturnRhPct)
             AND (fReturnTempC >= DL_DEHC_TMIN) AND (fReturnTempC <= DL_DEHC_TMAX)
             AND (fReturnRhPct >= 0.0) AND (fReturnRhPct <= 100.0);    // 回风域闸

(* === 段 2 · 焓值函数（每拍无条件调用；域外由函数内部钳位并给出信息级码）=== *)
fHFresh := FC_DL_HumidAirEnthalpy(fTempC := fFreshTempC, fRelHum := fFreshRhPct,
                                  uErrorId => uEnthErrFresh);       // 新风焓值 + 回执显式接收（v1.0.1）
fHReturn := FC_DL_HumidAirEnthalpy(fTempC := fReturnTempC, fRelHum := fReturnRhPct,
                                   uErrorId => uEnthErrRet);        // 回风焓值 + 回执显式接收（v1.0.1）
fEnthFreshKJkg := fHFresh;                        // 新风焓值输出
fEnthReturnKJkg := fHReturn;                      // 回风焓值输出
IF (fHFresh = fHFresh) AND (fHReturn = fHReturn) THEN
    fEnthDiffKJkg := fHReturn - fHFresh;          // 焓差 = 回风 − 新风
ELSE
    fEnthDiffKJkg := 0.0;                         // 非有限：焓差不出结论
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_DehcPhase.eIdle :
    fExhCmd := fDamperMinPct;                     // 空闲排湿关（安全位）
    fMixCmd := fDamperMinPct;                     // 空闲混风关（安全位）
    bTempForced := FALSE;                         // 强制标志复位
    IF uFault <> 16#0000 THEN
        _eState := E_DL_DehcPhase.eFault;         // 故障优先
    ELSIF bEnable THEN
        _eState := E_DL_DehcPhase.eCompare;       // 进入比较相
    END_IF

E_DL_DehcPhase.eCompare :
    IF bReturnOk AND (fReturnTempC > fReturnTempMaxC) THEN
        fExhCmd := DL_DEHC_FORCE;                 // 回风超温：强制全开排湿
        fMixCmd := fDamperMinPct;                 // 混风关（互斥）
        bTempForced := TRUE;                      // 置位型：超温强制标志
        uInfo := 16#0002_06AB;                    // 信息级：超温强制排湿
        _eState := E_DL_DehcPhase.eExhaust;
    ELSIF (NOT bFreshOk) OR (NOT bReturnOk) THEN
        fExhCmd := fDamperMinPct;                 // 参数无效：风门回安全位
        fMixCmd := fDamperMinPct;                 // 混风回安全位
        _eState := E_DL_DehcPhase.eIdle;          // 回空闲等有效参数（本拍不推进）
    ELSIF fEnthDiffKJkg > fEnthDeadKJkg THEN
        _eState := E_DL_DehcPhase.eRecover;       // 回风焓高：优先热回收
    ELSE
        _eState := E_DL_DehcPhase.eExhaust;       // 焓差不足：排湿
    END_IF

E_DL_DehcPhase.eExhaust :
    IF fLoadPct = fLoadPct THEN
        fExhCmd := fDamperMinPct + (fDamperMaxPct - fDamperMinPct) * fLoadPct * 0.01;   // 开度随负载
    ELSE
        fExhCmd := fDamperMinPct;                 // 负载无效：开度下限
    END_IF
    IF fExhCmd > fDamperMaxPct THEN
        fExhCmd := fDamperMaxPct;                 // 上限钳位
    END_IF
    IF fExhCmd < fDamperMinPct THEN
        fExhCmd := fDamperMinPct;                 // 下限钳位
    END_IF
    fMixCmd := fDamperMinPct;                     // 排湿相混风关（互斥）
    IF bTempForced AND (fReturnTempC <= fReturnTempMaxC - 2.0) THEN
        bTempForced := FALSE;                     // 回温降回上限-2 degC：解除强制（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码清除
    END_IF
    IF (NOT bTempForced) AND (fEnthDiffKJkg > fEnthDeadKJkg) THEN
        _eState := E_DL_DehcPhase.eRecover;       // 焓差满足：可转热回收
    ELSIF NOT bEnable THEN
        _eState := E_DL_DehcPhase.eIdle;          // 失能回空闲
    END_IF

E_DL_DehcPhase.eRecover :
    fMixCmd := fDamperMinPct + (fDamperMaxPct - fDamperMinPct) * 0.5;   // 混风开度 50% 基位
    fExhCmd := fDamperMinPct;                     // 混风相排湿关（互斥）
    IF fReturnTempC > fReturnTempMaxC THEN
        bTempForced := TRUE;                      // 超温：强制排湿优先
        uInfo := 16#0002_06AB;                    // 信息级：超温强制
        _eState := E_DL_DehcPhase.eExhaust;
    ELSIF fEnthDiffKJkg <= fEnthDeadKJkg THEN
        _eState := E_DL_DehcPhase.eExhaust;       // 焓差跌破死区：转排湿
    ELSIF NOT bEnable THEN
        _eState := E_DL_DehcPhase.eIdle;          // 失能回空闲
    END_IF

E_DL_DehcPhase.eFault :
    fExhCmd := fDamperMinPct;                     // 故障态排湿回安全位
    fMixCmd := fDamperMinPct;                     // 混风回安全位
    IF uFault = 16#0000 THEN
        _eState := E_DL_DehcPhase.eIdle;          // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_DehcPhase.eFault;             // 非法状态拦截
    uFault := 16#0002_068B;                       // 故障级：相 ID 越界
    fExhCmd := fDamperMinPct;                     // 安全位
    fMixCmd := fDamperMinPct;                     // 安全位
END_CASE

(* === 段 4 · 互斥仲裁与输出（双开即判冲突，双双回安全位）=== *)
IF (fExhCmd > fDamperMinPct + fEps) AND (fMixCmd > fDamperMinPct + fEps) THEN
    fExhCmd := fDamperMinPct;                     // 冲突：排湿回安全位
    fMixCmd := fDamperMinPct;                     // 冲突：混风回安全位
    bDamperConflict := TRUE;                      // 冲突标志
    uFault := 16#0002_069B;                       // 故障级：互斥冲突
ELSE
    bDamperConflict := FALSE;                     // 无冲突：标志清零（非置位型）
END_IF
IF rtrReset.Q AND bDamperConflict THEN
    uFault := 16#0000;                            // 冲突经复位解除（复位路径可达）
END_IF
IF NOT bEnable THEN
    fExhCmd := fDamperMinPct;                     // 失能最高优先：排湿关
    fMixCmd := fDamperMinPct;                     // 混风关
END_IF
fExhaustPct := fExhCmd;                           // 排湿开度输出
fMixPct := fMixCmd;                               // 混风开度输出
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
