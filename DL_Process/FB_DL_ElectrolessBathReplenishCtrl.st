(*
  DL Factory R83 | FB_DL_ElectrolessBathReplenishCtrl
  功能：按受镀面积与沉积速率算金属消耗，折算补加液量并做三态补加泵时序。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
TYPE E_DL_BathSt : ( eBathIdle := 0, eBathDose := 1, eBathFault := 2 ); END_TYPE // 补加三态枚举
FUNCTION_BLOCK FB_DL_ElectrolessBathReplenishCtrl
VAR_INPUT
    fLoadDm2    : REAL; // 在线受镀面积 [dm²] / In-line plated area [dm^2]
    fRateUmH    : REAL; // 沉积速率 [µm/h] / Deposition rate [um/h]
    fConcGpl    : REAL; // 槽液金属浓度 [g/L] / Bath metal concentration [g/L]
    fSpGpl      : REAL; // 目标维持浓度 [g/L] / Target maintained concentration [g/L]
    fAddConcGpl : REAL; // 补加液金属浓度 [g/L] / Replenisher metal concentration [g/L]
    bEnable     : BOOL; // 补加使能 / Dosing enable
    bReset      : BOOL; // 复位：清锁存码并回空闲相 / Reset: clear latched code, back to idle
END_VAR
VAR_OUTPUT
    fMetalGph : REAL; // 金属消耗速率 [g/h] / Metal consumption rate [g/h]
    fAddLph   : REAL; // 补加液流量指令 [L/h] / Replenisher flow command [L/h]
    xPump     : BOOL; // 补加泵运行输出 / Replenisher pump output
    iErrCode  : INT;  // 错误码，0=无错 / Error code, 0 = no error
END_VAR
VAR
    _eState : E_DL_BathSt := eBathIdle; // 当前状态，枚举初值一律 := / Current state, enum init with :=
    _iLatch : INT;        // 故障码锁存，仅 bReset 沿清除 / Latched fault code, reset edge only
    cNiGcm3 : REAL := 8.90; // 镍密度常量 [g/cm³]，已引用（R19）/ Nickel density [g/cm^3]
END_VAR
fMetalGph := 0.0; fAddLph := 0.0; xPump := FALSE;    // 出口预置：泵停（故障安全侧）
IF bReset THEN _iLatch := 0; iErrCode := 0; _eState := eBathIdle; END_IF  // 唯一清除边（R188）
// 非有限拦截 + 量纲自检 + 补加液浓度次序闸（R20/R21）
IF NOT (fLoadDm2 > -1.0E30 AND fLoadDm2 < 1.0E30) OR NOT (fRateUmH > -1.0E30 AND fRateUmH < 1.0E30) OR NOT (fConcGpl > -1.0E30 AND fConcGpl < 1.0E30) OR NOT (fSpGpl > -1.0E30 AND fSpGpl < 1.0E30) OR NOT (fAddConcGpl > -1.0E30 AND fAddConcGpl < 1.0E30) OR fLoadDm2 < 0.0 OR fRateUmH < 0.0 OR fSpGpl <= 0.0 OR fAddConcGpl <= fSpGpl THEN
    _eState := eBathFault; _iLatch := 9201; iErrCode := _iLatch; RETURN; // 故障拍不开泵
END_IF
// 金属消耗：1 dm² = 100 cm²、1 µm = 1E-4 cm，故每 dm²·µm = 0.01 cm³；乘 ρ 得 g
fMetalGph := fLoadDm2 * fRateUmH * 0.01 * cNiGcm3;   // 金属消耗速率 [g/h] / Metal consumption [g/h]
// 补加流量：g/h ÷ (补加浓度 - 维持浓度)[g/L] = L/h，浓度差分母显式零闸（R4/R21）
IF (fAddConcGpl - fSpGpl) > 1.0E-9 THEN fAddLph := fMetalGph / (fAddConcGpl - fSpGpl); ELSE fAddLph := 0.0; END_IF
CASE _eState OF  // 三态机：浓度偏低进补加相；退出两条（失去使能 / 浓度达标）
eBathIdle:
    IF bEnable AND fConcGpl < fSpGpl THEN _eState := eBathDose; END_IF  // 浓度偏低进补加 / Low conc, dose
eBathDose:
    xPump := TRUE;                                    // 补加相开泵 / Pump on in dose state
    IF NOT bEnable OR fConcGpl >= fSpGpl THEN _eState := eBathIdle; END_IF // 退出两条合并判 / Either exit
eBathFault:
    xPump := FALSE; iErrCode := _iLatch;              // 故障相停泵，故障码锁存回放 / Latched replay
ELSE
    _eState := eBathFault; _iLatch := 9203;           // 非法状态兜底拦截（R6）/ Illegal state fallback
END_CASE
END_FUNCTION_BLOCK
