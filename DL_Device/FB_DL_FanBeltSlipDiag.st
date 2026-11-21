(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FanBeltSlipDiag
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（Building 泵风机族深化）
 * 所属子库 (Sublibrary) : DL_Device / FanDiag
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 风机皮带打滑诊断
 * 功能一句话 (Summary)  : 电机/叶轮转速比监视 + 确认延时 + 叶轮停转判据。
 * 边界与安全 (Boundary) : ①电机转速小于 1 rpm 不判定（防除零，规格口径）；
 *                         ②bMotorRun=FALSE 清确认（停机撤销判定）；
 *                         ③叶轮近零而电机运行 → 叶轮停转码；
 *                         ④转速负值或非有限 → 输入非法码；
 *                         ⑤确认 TON 无条件周期刷新；
 *                         ⑥转速比按 1:1 皮带传动基准（倍率差异属调用方换算）。
 * 错误码    : 16#0003_0381 转速比超差确认（打滑）——故障级（持续态）
 *             16#0003_0382 叶轮停转而电机运行——故障级（持续态）
 *             16#0003_0383 输入非法（负转速或非有限）——故障级（持续态）
 * 码位总账  : 16#0003_0381 用 / 16#0003_0382 用 / 16#0003_0383 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_FanBeltSlipDiag
VAR_INPUT
    fMotorRpm : LREAL; // 电机转速 [rpm] / Motor speed [rpm]
    fFanRpm   : LREAL; // 叶轮转速 [rpm] / Fan wheel speed [rpm]
    fRatioTol : LREAL; // 转速比容差 [%] / Speed ratio tolerance [%]
    tConfirm  : TIME;  // 打滑确认延时 [ms] / Slip confirm delay [ms]
    bMotorRun : BOOL;  // 电机运行反馈 / Motor running feedback
END_VAR
VAR_OUTPUT
    bSlip        : BOOL; // 打滑特征成立（计时中）/ Slip signature active
    bSlipConfirm : BOOL; // 打滑确认（延时满足）/ Slip confirmed
    fRatio       : LREAL; // 电机/叶轮转速比 / Motor-to-fan speed ratio
    eErr         : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cMinRpm : LREAL := 1.0; // 判定最小电机转速 [rpm] / Minimum judgeable motor speed
END_VAR
VAR
    tonSlip : TON;   // 打滑确认定时器（无条件刷新）/ Slip confirm timer
    bInSlip : BOOL;  // 打滑域内判据 / In-slip-domain predicate
    bInOk   : BOOL;  // 输入合法性 / Input legality
    fMotGrd : LREAL; // 电机转速守卫副本 / Motor speed guard copy
    fFanGrd : LREAL; // 叶轮转速守卫副本 / Fan speed guard copy
    fSlip   : LREAL; // 比值偏离量 [%] / Ratio deviation [%]
END_VAR

// ---------- 实时守卫副本 ----------
fMotGrd := fMotorRpm;
fFanGrd := fFanRpm;

// ---------- 输入合法性：负转速或非有限拒判 ----------
bInOk := bMotorRun AND (fMotGrd >= 0.0) AND (fFanGrd >= 0.0)
     AND (fMotGrd = fMotGrd) AND (fFanGrd = fFanGrd);
IF NOT bInOk THEN
    IF bMotorRun AND ((fMotGrd < 0.0) OR (fFanGrd < 0.0)
       OR (fMotGrd <> fMotGrd) OR (fFanGrd <> fFanGrd)) THEN
        eErr := 16#0003_0383;                 // 输入非法码 / Illegal input code
    ELSE
        eErr := 0;                            // 停机不置码（正常撤销）/ Stopped, no code
    END_IF
END_IF

// ---------- 转速比计算：电机转速小于 1 rpm 不判定（防除零） ----------
IF bInOk AND (fMotGrd >= cMinRpm) THEN
    IF fFanGrd > 0.0 THEN
        fRatio := fMotGrd / fFanGrd;          // 除法前判零 / Zero-guarded divide
        fSlip := (fRatio - 1.0) * 100.0;      // 偏离百分比 / Deviation percent
        IF fSlip < 0.0 THEN
            fSlip := -fSlip;                  // 绝对偏离 / Absolute deviation
        END_IF
        bInSlip := fSlip > fRatioTol;         // 超差判据 / Over-tolerance predicate
    ELSE
        fRatio := 0.0;                        // 叶轮停转比值缺省 / Stalled wheel default
        bInSlip := FALSE;
        eErr := 16#0003_0382;                 // 叶轮停转码 / Wheel stall code
    END_IF
ELSE
    fRatio := 0.0;                            // 不判定缺省 / Not-judged default
    bInSlip := FALSE;
END_IF

// ---------- 无条件周期刷新：打滑确认定时器 ----------
tonSlip(IN := bInSlip, PT := tConfirm);
bSlip := tonSlip.IN;                          // 计时中特征 / Signature while timing
IF tonSlip.Q THEN
    bSlipConfirm := TRUE;                     // 确认成立 / Confirmed
    eErr := 16#0003_0381;                     // 超差确认码 / Over-tolerance confirm code
ELSE
    bSlipConfirm := FALSE;                    // 未确认即撤销 / Withdrawn if unconfirmed
END_IF

END_FUNCTION_BLOCK
