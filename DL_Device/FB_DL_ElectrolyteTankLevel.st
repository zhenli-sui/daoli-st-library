(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectrolyteTankLevel
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（路线图 L350 已登记 + Building 族借形）
 * 所属子库 (Sublibrary) : DL_Device / TankControl
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 电解液储罐液位双限 + 氮封监视
 * 功能一句话 (Summary)  : 液位双限告警 + 氮封微正压联锁 + 加注许可仲裁，仅监视与许可。
 * 边界与安全 (Boundary) : ①传感器失效 → 保持上次有效状态 + 压力故障 + 禁加注（安全侧）；
 *                         ②LoLo 大于等于 HiHi → 设定值非法码且禁加注；
 *                         ③液位高于 HiHi 禁加注，低于 LoLo 同禁（双侧禁注）；
 *                         ④氮封压力低于下限开氮阀，高于上限置越限码；
 *                         ⑤NaN 液位/压力拒收并按传感器失效处理（安全侧）。
 * 错误码    : 16#0003_037B 液位/压力传感器失效——故障级（持续态）
 *             16#0003_037C 氮封压力越限（高于上限或低于下限）——故障级（持续态）
 *             16#0003_037D 双限设定值非法（LoLo 不小于 HiHi）——故障级（持续态）
 * 码位总账  : 16#0003_037B 用 / 16#0003_037C 用 / 16#0003_037D 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ElectrolyteTankLevel
VAR_INPUT
    fLevel    : LREAL; // 液位 [%] / Level [%]
    fN2Press  : LREAL; // 氮封压力 [kPa] / Nitrogen blanket pressure [kPa]
    fHiHi     : LREAL; // 液位高高限 [%] / Level high-high limit [%]
    fLoLo     : LREAL; // 液位低低限 [%] / Level low-low limit [%]
    fPressLo  : LREAL; // 氮封压力下限 [kPa] / Pressure lower limit [kPa]
    fPressHi  : LREAL; // 氮封压力上限 [kPa] / Pressure upper limit [kPa]
    bSensorOk : BOOL;  // 传感器通道自诊断 OK / Sensor channel self-check OK
END_VAR
VAR_OUTPUT
    bFillPermit  : BOOL; // 加注许可仲裁输出 / Fill permit arbitration
    bN2ValveOpen : BOOL; // 氮封阀开建议（TRUE=建议开启）/ N2 valve open request
    bHiHi        : BOOL; // 液位高高告警 / Level high-high alarm
    bLoLo        : BOOL; // 液位低低告警 / Level low-low alarm
    bPressFault  : BOOL; // 氮封压力故障 / Nitrogen pressure fault
    eErr         : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    bLevelHiHiL : BOOL; // 液位高高内部判定 / Internal high-high predicate
    bLevelLoLoL : BOOL; // 液位低低内部判定 / Internal low-low predicate
    fLevelGuard : LREAL; // 液位实时守卫副本 / Level guard copy
    fPressGuard : LREAL; // 压力实时守卫副本 / Pressure guard copy
    bParamOk    : BOOL;  // 设定值合法性 / Setpoint legality
END_VAR

// ---------- 实时守卫副本（内部判定统一用，输出为锁存结论） ----------
fLevelGuard := fLevel;
fPressGuard := fN2Press;

// ---------- 设定值防御：LoLo 不小于 HiHi 即非法（含 NaN 拒收） ----------
bParamOk := (fLoLo < fHiHi) AND (fPressLo < fPressHi)
        AND (fLoLo = fLoLo) AND (fHiHi = fHiHi) AND (fPressLo = fPressLo) AND (fPressHi = fPressHi);
IF NOT bParamOk THEN
    bFillPermit := FALSE;                     // 设定非法禁加注（安全侧）/ Illegal setpoints, no fill
    eErr := 16#0003_037D;                     // 设定非法码 / Illegal setpoints code
    RETURN;
END_IF

// ---------- 传感器防御：通道失效或 NaN 均按失效处理 ----------
IF (NOT bSensorOk) OR (fLevelGuard <> fLevelGuard) OR (fPressGuard <> fPressGuard) THEN
    // 保持上次有效状态：bHiHi/bLoLo/bN2ValveOpen 锁存值不动，禁加注与压力故障置位
    bFillPermit := FALSE;                     // 禁加注（安全侧）/ Fill forbidden, safe side
    bPressFault := TRUE;                      // 压力故障置位 / Pressure fault set
    eErr := 16#0003_037B;                     // 传感器失效码 / Sensor failure code
    RETURN;
END_IF

// ---------- 双限判定（实时值判据，输出为持续态结论） ----------
bLevelHiHiL := fLevelGuard >= fHiHi;          // 高高判据 / High-high predicate
bLevelLoLoL := fLevelGuard <= fLoLo;          // 低低判据 / Low-low predicate
bHiHi := bLevelHiHiL;                         // 对外告警（持续态）/ Alarm output
bLoLo := bLevelLoLoL;

// ---------- 氮封压力监视：低于下限开氮阀，高于上限越限 ----------
bPressFault := (fPressGuard > fPressHi) OR (fPressGuard < fPressLo); // 越限判据 / Out-of-band predicate
IF fPressGuard < fPressLo THEN
    bN2ValveOpen := TRUE;                     // 压力不足开氮阀 / Low pressure: open N2 valve
    eErr := 16#0003_037C;                     // 越限码 / Out-of-band code
ELSIF fPressGuard > fPressHi THEN
    bN2ValveOpen := FALSE;                    // 超压关氮阀 / Over pressure: close N2 valve
    eErr := 16#0003_037C;                     // 越限码（复用同码）/ Out-of-band code shared
ELSE
    bN2ValveOpen := FALSE;                    // 带内保持关闭 / In-band stays closed
END_IF

// ---------- 加注许可仲裁：双限内 + 压力正常才放行 ----------
IF bHiHi OR bLoLo OR bPressFault THEN
    bFillPermit := FALSE;                     // 任一异常禁加注 / Any anomaly forbids fill
ELSE
    bFillPermit := TRUE;                      // 全部正常放行 / All normal permits fill
END_IF

END_FUNCTION_BLOCK
