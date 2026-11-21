(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PumpDryRunProtect
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（Building 泵风机族深化）
 * 所属子库 (Sublibrary) : DL_Device / PumpProtect
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 泵干转保护
 * 功能一句话 (Summary)  : 运行态功率/流量双判据干转确认 + 确认延时 + 重启闭锁。
 * 边界与安全 (Boundary) : ①仅在运行反馈存在时判定（未运行不判）；
 *                         ②功率与流量任一达到干转特征即计时（双判据并联）；
 *                         ③流量引脚小于 0 表示未接（可选量，仅功率判据）；
 *                         ④空载阈值非正 → 参数非法码；
 *                         ⑤跳闸锁存 + 重启闭锁，需 bReset 且流程恢复才解除。
 * 错误码    : 16#0003_037E 干转确认（延时满足）——故障级（锁存）
 *             16#0003_037F 参数非法（空载阈值非正）——故障级（持续态）
 *             16#0003_0380 重启闭锁激活（跳闸未复位）——故障级（持续态）
 * 码位总账  : 16#0003_037E 用 / 16#0003_037F 用 / 16#0003_0380 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_PumpDryRunProtect
VAR_INPUT
    bPumpRunFb   : BOOL;  // 泵运行反馈 / Pump running feedback
    fMotorPower  : LREAL; // 电机功率 [kW] / Motor power [kW]
    fFlow        : LREAL; // 流量 [m3/h]，小于 0 表示未接 / Flow [m3/h], negative = not wired
    fNoLoadPower : LREAL; // 空载功率阈值 [kW] / No-load power threshold [kW]
    tDryDelay    : TIME;  // 干转确认延时 [ms] / Dry-run confirm delay [ms]
    bReset       : BOOL;  // 复位指令（跳闸后解除闭锁）/ Reset command (clears trip inhibit)
END_VAR
VAR_OUTPUT
    bDryRun        : BOOL; // 干转特征成立（计时中）/ Dry-run signature active (timing)
    bTrip          : BOOL; // 干转跳闸锁存 / Dry-run trip latch
    bRestartInhibit: BOOL; // 重启闭锁（跳闸未复位期间）/ Restart inhibit while latched
    eErr           : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    tonDry    : TON;   // 干转确认定时器（无条件刷新）/ Dry-run confirm timer
    bPowDry   : BOOL;  // 功率干转特征 / Power dry signature
    bFlowDry  : BOOL;  // 流量干转特征 / Flow dry signature
    bFlowWired: BOOL;  // 流量引脚已接判据 / Flow pin wired predicate
    fPowGuard : LREAL; // 功率守卫副本 / Power guard copy
    fFlowGuard: LREAL; // 流量守卫副本 / Flow guard copy
    bParamOk  : BOOL;  // 参数合法性 / Parameter legality
END_VAR

// ---------- 实时守卫副本 ----------
fPowGuard  := fMotorPower;
fFlowGuard := fFlow;
bFlowWired := fFlowGuard >= 0.0;              // 负值约定为未接 / Negative convention = not wired

// ---------- 参数防御：空载阈值非正或 NaN（持续态，不判定） ----------
bParamOk := (fNoLoadPower > 0.0) AND (fNoLoadPower = fNoLoadPower);
IF NOT bParamOk THEN
    eErr := 16#0003_037F;                     // 参数非法码 / Illegal parameter code
    bDryRun := FALSE;
END_IF

// ---------- 干转双判据：仅运行态判定（未运行不判） ----------
bPowDry  := FALSE;
bFlowDry := FALSE;
IF bPumpRunFb AND bParamOk THEN
    IF (fPowGuard >= 0.0) AND (fPowGuard < fNoLoadPower) THEN
        bPowDry := TRUE;                      // 功率低于空载阈 / Power below no-load threshold
    END_IF
    IF bFlowWired AND (fFlowGuard < 0.01) THEN
        bFlowDry := TRUE;                     // 流量近零 / Flow near zero
    END_IF
END_IF

// ---------- 无条件周期刷新：干转确认定时器 ----------
tonDry(IN := bPowDry OR bFlowDry, PT := tDryDelay);
bDryRun := tonDry.IN;                         // 计时中特征输出 / Signature while timing

// ---------- 跳闸锁存与重启闭锁 ----------
IF tonDry.Q THEN
    bTrip := TRUE;                            // 延时满足跳闸锁存 / Delay met, trip latch
    eErr  := 16#0003_037E;                    // 干转确认码 / Dry-run confirm code
END_IF

IF bTrip THEN
    bRestartInhibit := TRUE;                  // 闭锁激活 / Inhibit active
    eErr := 16#0003_0380;                     // 重启闭锁码（跳闸确认码 037E 已在确认拍报出）/ Inhibit code, trip code raised at confirm scan
    IF bReset THEN
        bTrip           := FALSE;             // 复位解除锁存 / Reset clears latch
        bRestartInhibit := FALSE;             // 闭锁解除 / Inhibit cleared
        eErr            := 0;                 // 复位同拍清码 / Code cleared on reset
    END_IF
ELSE
    bRestartInhibit := FALSE;                 // 无锁存无闭锁 / No latch, no inhibit
END_IF

END_FUNCTION_BLOCK
