(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MotorPtcThermistProtect
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LBP 深化 + 国产手册需求线）
 * 所属子库 (Sublibrary) : DL_Device / MotorProtect
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· PTC 热敏电阻绕组保护
 * 功能一句话 (Summary)  : DIN 44081 判据的 PTC 三态保护：断线/短路/跳闸 + 确认延时。
 * 边界与安全 (Boundary) : ①断线判定优先于跳闸（先判阻值域再判确认）；
 *                         ②跳闸锁存仅 bReset 可清，且 bReset 仅在阻值回落
 *                           正常带（低于跳闸阈值）后有效（防复位振荡）；
 *                         ③滤波电阻一阶惯性，NaN/负值样本拒收保持旧值；
 *                         ④确认 TON 无条件周期刷新；
 *                         ⑤跳闸态短路回路的 bReset 无效（验收向量 ③）。
 * 错误码    : 16#0003_0378 断线（阻值不低于断线阈值）——故障级（持续态）
 *             16#0003_0379 短路（阻值不高于短路阈值）——故障级（持续态）
 *             16#0003_037A 跳闸确认（阻值进入跳闸域经延时确认）——故障级（锁存）
 * 码位总账  : 16#0003_0378 用 / 16#0003_0379 用 / 16#0003_037A 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_MotorPtcThermistProtect
VAR_INPUT
    fThermRes     : LREAL; // PTC 热敏电阻实测阻值 [Ω] / Measured PTC resistance [Ω]
    bSensorOk     : BOOL;  // 传感器通道自诊断 OK / Sensor channel self-check OK
    fTripRes      : LREAL; // 跳闸阻值阈值 [Ω]，默认 3300 / Trip resistance threshold [Ω]
    fOpenRes      : LREAL; // 断线阻值阈值 [Ω]，默认 8000 / Open-circuit threshold [Ω]
    fShortRes     : LREAL; // 短路阻值阈值 [Ω]，默认 50 / Short-circuit threshold [Ω]
    tConfirmDelay : TIME;  // 跳闸确认延时 [ms] / Trip confirm delay [ms]
    bReset        : BOOL;  // 复位指令（回落正常带后有效）/ Reset command (valid only back in normal band)
END_VAR
VAR_OUTPUT
    bTrip        : BOOL; // 跳闸锁存输出，仅 bReset 可清 / Trip latch, cleared only by reset
    bWarn        : BOOL; // 预警：阻值进入预警带（0.75 倍跳闸阈）/ Warning: resistance in pre-trip band
    bSensorFault : BOOL; // 传感器故障（断线或短路或通道失效）/ Sensor fault (open, short or channel)
    fResFiltered : LREAL; // 一阶滤波阻值 [Ω] / First-order filtered resistance [Ω]
    eErr         : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cWarnRatio : LREAL := 0.75; // 预警带占跳闸阈比例 / Warning band ratio of trip threshold
    cIFilter   : LREAL := 0.2;  // 一阶滤波新样本权重 / Filter weight of new sample
END_VAR
VAR
    tonTrip  : TON;   // 跳闸确认定时器（无条件刷新）/ Trip confirm timer
    bResValid: BOOL;  // 本拍样本合法性 / Sample validity this cycle
    fResGuard: LREAL; // 本拍阻值守卫副本 / Cycle resistance guard copy
    bInTripDom: BOOL; // 阻值处于跳闸域（断线短路之间）/ Resistance in trip domain
END_VAR

// ---------- 参数与样本防御（守卫副本先行） ----------
fResGuard := fThermRes;
bResValid := bSensorOk AND (fResGuard >= 0.0) AND (fResGuard <= fOpenRes * 2.0);
IF fResGuard <> fResGuard THEN
    bResValid := FALSE;                       // NaN 拒收 / NaN rejected
END_IF

// ---------- 滤波：合法样本一阶更新，拒收保持旧值 ----------
IF bResValid THEN
    fResFiltered := fResFiltered + cIFilter * (fResGuard - fResFiltered); // 一阶惯性 / First-order lag
END_IF

// ---------- 无条件周期刷新：跳闸确认定时器 ----------
bInTripDom := bResValid AND (fResFiltered >= fTripRes) AND (fResFiltered < fOpenRes);
tonTrip(IN := bInTripDom, PT := tConfirmDelay);

// ---------- 断线判定（优先级最高） ----------
bSensorFault := FALSE;
eErr := 0;
IF NOT bSensorOk THEN
    bSensorFault := TRUE;                     // 通道自诊断失效 / Channel self-check failed
    eErr := 16#0003_0378;                     // 复用断线码（通道失效同域）/ Open code reused for channel fault
ELSIF bResValid AND (fResFiltered >= fOpenRes) THEN
    bSensorFault := TRUE;                     // 阻值达断线域 / Resistance in open domain
    eErr := 16#0003_0378;                     // 断线码 / Open-circuit code
ELSIF bResValid AND (fResFiltered <= fShortRes) THEN
    bSensorFault := TRUE;                     // 阻值达短路域 / Resistance in short domain
    eErr := 16#0003_0379;                     // 短路码 / Short-circuit code
END_IF

// ---------- 跳闸锁存：确认定时器到时置位，复位需回落正常带 ----------
IF tonTrip.Q THEN
    bTrip := TRUE;                            // 跳闸锁存置位 / Trip latch set
    eErr := 16#0003_037A;                     // 跳闸确认码 / Trip confirm code
END_IF

// ---------- 复位仲裁：阻值回落正常带（低于跳闸阈）后 bReset 才有效 ----------
IF bTrip THEN
    IF bResValid AND (fResFiltered < fTripRes) AND bReset THEN
        bTrip := FALSE;                       // 合法复位解除锁存 / Legal reset clears latch
        eErr  := 0;                           // 复位同拍清码 / Code cleared on reset
    ELSE
        eErr := 16#0003_037A;                 // 锁存态保持跳闸码（含短路态下复位被拒）/ Trip code held while latched
    END_IF
END_IF

// ---------- 预警带：介于 0.75 倍跳闸阈与跳闸阈之间 ----------
bWarn := bResValid AND (fResFiltered >= fTripRes * cWarnRatio) AND (fResFiltered < fTripRes);

END_FUNCTION_BLOCK
