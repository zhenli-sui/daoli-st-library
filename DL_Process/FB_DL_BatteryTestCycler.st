//==============================================================================
// 功能块：FB_DL_BatteryTestCycler ｜ 中文名称：单通道电池充放电工步机
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：单体电芯充放电测试工步机：静置 → 恒流充电 → 恒压充电 → 静置 → 恒流放电 →
//           静置 → 完成，逐工步按终止判据切相；充/放电容量按安时积分统计（LREAL 累加
//           防精度损失）；温度与电压安全域逐拍硬判，越限当拍断流并进故障相（锂电热失控
//           不可逆，安全路径优先级最高）。工步超时按「本工步独立计时」判定，禁跨相累计。
//           本件是单通道工步机：不调度多通道、不做通道仲裁与分配（多通道调度归
//           序号 19 的 FormationsChannelMgr），对外只以电流设定 / 电压限值与工步状态
//           布尔快照交互，两件互不包含。
// 开源溯源 (Origin)：道莅原创实现（参考 公开工程惯例 分类与参数域）
// 单位表：电压[V] / 电流[A]（放电为负）/ 温度[摄氏度] / 静置时长[min] / 工步超时[min] /
//         容量[Ah] / 容量比[百分数] / 扫描间隔[ms] / 工步已历时[ms] / 样本数[拍]
// 错误码表：16#0005_0406 信息级（工步切相提示，含「因终止判据达成而提前切相」与静置
//           到时，不置 bError）/ 16#0005_0407 信息级（容量统计饱和触顶，不置 bError）/
//           16#0005_034B 故障级（温度越上限或电压越安全域，或安全判据量（温度/电压/
//           电流）非有限——非有限按越限处置，强制断流，置 bError）/ 16#0005_034C 故障级
//           （单工步超时，工艺卡死，置 bError + 断流）/ 16#0005_034D 故障级（组态非法：
//           额定容量/电流设定/电压域/超时非正或非有限，以及状态机 ELSE 非法状态兜底）。
//           034D 的共用反证句：组态非法与非法状态在现有输出组合下不可观测出差异（均为
//           bError + fCurrentSetA = 0 + eStep 不推进 + bValid 撤），§3 未给本件独立组态槽，
//           故显式复用不越段。
// 状态机：E_DL_BatteryCycleState（eIdle=0 待机 / eRestInit=10 充电前静置 / eCcCharge=20
//           恒流充电 / eCvCharge=30 恒压充电 / eRestMid=40 放前静置 / eDiscCharge=50 恒流
//           放电 / eRestFinal=60 放后静置 / eDone=70 完成 / eFault=99 故障兜底），CASE 含
//           ELSE 兜底，ELSE 置 034D 且断流、eStep 回 eIdle。
// 边界行为：① 安全侧优先：温度 > fTempMaxC 或电压越 [fVoltMinV, fVoltMaxV] → 故障 034B
//           + fCurrentSetA := 0.0 + 进 eFault（每拍先判安全判据，先于任何工步推进）；
//           ② 单工步超 tMaxStep → 故障 034C，工步计时器在每次切相时清零（禁相内累计，
//           R40 家族）；③ 额定容量/电流/电压域/超时组态非法 → 034D 组态分支（映射见
//           错误码表反证句）；④ 容量积分 Ah += |I| x Δt/3600，LREAL 累加并饱和；⑤ CV
//           终止：|I| < fCutoffCurrentA 连续 nCvHoldSamples 拍才切相（防单点抖动误切）；
//           ⑥ bStop → 当拍 fCurrentSetA := 0 并回 eIdle（不等待工步收尾）；⑦ 失能走同一
//           安全侧路径（fCurrentSetA := 0）。bStart 取上升沿，bStepDone 为单拍脉冲。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.15）
//           v1.0.1 2026-11-17 终审补 eFault 独立 CASE 标签（对外引脚契约零变更）：原实现 eFault(99)
//           无标签，落进 ELSE 兜底支路每拍把真因码 034B/034C 覆盖成 034D「非法状态」，激励消失后
//           诊断失真（故障仍锁存、安全侧不变，属诊断保真度缺陷）。同批另有 6 件存在同类标签缺失
//           （ParticleCounterStat / CoolingTowerApproachCalc / InverterGridSync / HeatPumpDefrost /
//           DuctStaticReset / DewpointReset），已按 R106 第二档挂账下轮统一修并加机检规则。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_BatteryCycleState（归属 DL_Process，与 FB_DL_BatteryTestCycler 同文件）
 *       工步号与 §4.15 顺序一一对应；数值步长留空位便于插工步
 *----------------------------------------------------------------------------*)
TYPE E_DL_BatteryCycleState :
(
    eIdle       := 0,   // 待机：电流设定 0，等待 bStart / Idle, current setpoint 0, waiting for start
    eRestInit   := 10,  // 充电前静置：时长 tRestCharge / Pre-charge rest, duration tRestCharge
    eCcCharge   := 20,  // 恒流充电：电流 = fCcCurrentA，终止判据 电压达 fCvVoltV / Constant-current charge
    eCvCharge   := 30,  // 恒压充电：电压限 = fCvVoltV，终止判据 电流降至 fCutoffCurrentA / Constant-voltage charge
    eRestMid    := 40,  // 放前静置：时长 tRestCharge / Pre-discharge rest, duration tRestCharge
    eDiscCharge := 50,  // 恒流放电：电流 = -fDiscCurrentA，终止判据 电压降至 fDiscCutoffV / Constant-current discharge
    eRestFinal  := 60,  // 放后静置：时长 tRestDisc / Post-discharge rest, duration tRestDisc
    eDone       := 70,  // 完成：电流设定 0，容量统计保持 / Done, current 0, capacity statistics held
    eFault      := 99   // 故障兜底：越限/超时/组态非法/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_BatteryTestCycler
 * 调用约定: 每个扫描周期无条件调用一次；uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_BatteryTestCycler
VAR_INPUT
    fVoltV          : LREAL;                       // 实测电压 [V] / Measured voltage [V]
    fCurrentA       : LREAL;                       // 实测电流 [A]，放电为负 / Measured current [A], negative while discharging
    fTempC          : LREAL;                       // 实测温度 [摄氏度] / Measured temperature [degC]
    fCcCurrentA     : LREAL;                       // 恒流充电电流设定 [A]，须 > 0 / Constant-current charge setpoint [A], must be > 0
    fCvVoltV        : LREAL;                       // 恒压充电电压点 [V] / Constant-voltage charge point [V]
    fCutoffCurrentA : LREAL;                       // 恒压段终止电流 [A]，须 >= 0 / CV termination current [A], must be >= 0
    fDiscCurrentA   : LREAL;                       // 放电电流设定 [A]，须 > 0（本件按负值下发）/ Discharge current setpoint [A], must be > 0, issued negative
    fDiscCutoffV    : LREAL;                       // 放电终止电压 [V] / Discharge termination voltage [V]
    tRestCharge     : TIME := T#10M;               // 充/放前静置时长 [min] / Pre-step rest duration [min]
    tRestDisc       : TIME := T#10M;               // 放后静置时长 [min] / Post-discharge rest duration [min]
    tMaxStep        : TIME := T#120M;              // 单工步超时 [min]，各工步独立计时 / Per-step timeout [min], timed per step
    fCapNomAh       : LREAL;                       // 额定容量 [Ah]，须 > 0（容量比分母）/ Rated capacity [Ah], must be > 0
    fVoltMaxV       : LREAL;                       // 安全域电压上限 [V] / Safety voltage ceiling [V]
    fVoltMinV       : LREAL;                       // 安全域电压下限 [V] / Safety voltage floor [V]
    fTempMaxC       : LREAL;                       // 温度上限 [摄氏度] / Temperature ceiling [degC]
    bStart          : BOOL;                        // 启动（取上升沿）/ Start, rising edge
    bStop           : BOOL;                        // 停止（电平，当拍断流）/ Stop, level, current dropped this scan
    bReset          : BOOL;                        // 复位，上升沿清故障与容量统计 / Reset, rising edge clears the fault and capacity statistics
    uDeltaTimeMs    : UDINT;                       // 扫描间隔 [ms]，调用方注入，禁系统时间函数 / Scan interval [ms], caller-injected
END_VAR
VAR_OUTPUT
    eStep           : E_DL_BatteryCycleState;      // 当前工步 / Current step
    fCurrentSetA    : LREAL;                       // 电流设定 [A]，故障拍立即 0 / Current setpoint [A], forced to 0 on any fault scan
    fVoltLimitV     : LREAL;                       // 电压限 [V]，随工步切换 / Voltage limit [V], follows the step
    fChargedAh      : LREAL;                       // 累计充电容量 [Ah]，饱和 / Accumulated charge capacity [Ah], saturating
    fDischargedAh   : LREAL;                       // 累计放电容量 [Ah]，饱和 / Accumulated discharge capacity [Ah], saturating
    fCapacityRatioPct : LREAL;                     // 容量比 [百分数] = 放电 Ah / 额定 Ah x 100 / Capacity ratio [percent]
    bStepDone       : BOOL;                        // 工步完成单拍脉冲（切相当拍 TRUE）/ Single-scan step-done pulse
    tStepElapsed    : TIME;                        // 本工步已历时 [ms] / Elapsed time of the current step [ms]
    eErr            : UDINT;                       // 错误码，0 = 无错，码位 16#0005_0406 起信息级、16#0005_034B 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                        // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                        // 工步输出可用标志，失能/故障闸显式 FALSE / Step outputs usable flag, explicit FALSE on disable/fault gates
END_VAR
VAR
    fbReset         : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    fbStart         : R_TRIG;                      // 启动上升沿检测实例 / Start rising edge detector
    uStepMs         : UDINT;                       // 本工步累计历时 [ms]，切相即清零 / Elapsed time of this step [ms], cleared on every transition
    uDtEff          : UDINT;                       // 钳位后的扫描间隔 [ms] / Clamped scan interval [ms]
    uMaxStepMs      : UDINT;                       // 工步超时门限 [ms] / Step timeout threshold [ms]
    uRestChgMs      : UDINT;                       // 充/放前静置门限 [ms] / Pre-step rest threshold [ms]
    uRestDiscMs     : UDINT;                       // 放后静置门限 [ms] / Post-discharge rest threshold [ms]
    fDtH            : LREAL;                       // 扫描间隔换算成小时 [h] / Scan interval in hours [h]
    fAbsCurrentA    : LREAL;                       // 实测电流绝对值 [A] / Absolute measured current [A]
    fAhStep         : LREAL;                       // 本拍容量增量 [Ah] / Capacity increment of this scan [Ah]
    nCvHoldCnt      : INT;                         // CV 终止判据连续满足拍数 [拍] / Consecutive CV-cutoff samples [scans]
    bCapSat         : BOOL;                        // 容量积分饱和标志 / Capacity saturation flag
    bStepChanged    : BOOL;                        // 本拍发生切相标志 / Step changed this scan
    bRestChgDone    : BOOL;                        // 静置到时（用充电侧时长）/ Rest elapsed with the charge-side duration
    bRestDiscDone   : BOOL;                        // 静置到时（用放电侧时长）/ Rest elapsed with the discharge-side duration
    bCvCutoff       : BOOL;                        // CV 终止判据满足 / CV termination criterion satisfied
    bDiscCutoff     : BOOL;                        // 放电终止判据满足 / Discharge termination criterion satisfied
    bCcReached      : BOOL;                        // CC 段电压已达 CV 点 / CC reached the CV point
    bNonFinSafe     : BOOL;                        // 安全判据量非有限标志 / Safety-class non-finite flag
    bNonFinCfg      : BOOL;                        // 组态量非有限标志 / Configuration non-finite flag
    bFirstScan      : BOOL := TRUE;                // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_BTC_CODE_INFO_1 : UDINT := 16#0005_0406;    // 信息级槽 1（工步切相提示） / info slot 1
    DL_BTC_CODE_INFO_2 : UDINT := 16#0005_0407;    // 信息级槽 2（容量统计饱和） / info slot 2
    DL_BTC_CODE_FLT_1  : UDINT := 16#0005_034B;    // 故障级槽 1（温度/电压越限，强制断流） / fault slot 1
    DL_BTC_CODE_FLT_2  : UDINT := 16#0005_034C;    // 故障级槽 2（工步超时，工艺卡死） / fault slot 2
    DL_BTC_CODE_FLT_3  : UDINT := 16#0005_034D;    // 故障级槽 3（组态非法/非法状态兜底） / fault slot 3
    DL_BTC_CV_HOLD     : INT := 5;                 // CV 终止判据连续确认拍数 [拍] / CV cutoff confirmation samples [scans]
    DL_BTC_AH_MAX      : LREAL := 100000.0;        // 容量积分饱和上限 [Ah] / Capacity saturation ceiling [Ah]
    DL_BTC_DT_MIN_MS   : UDINT := 1;               // 扫描间隔下限 [ms]，防除零与死判 / Scan interval floor [ms]
    DL_BTC_SEC_PER_H   : LREAL := 3600.0;          // 秒转小时系数 [s/h] / Seconds per hour
    DL_BTC_MS_PER_S    : LREAL := 1000.0;          // 毫秒转秒系数 [ms/s] / Milliseconds per second
    DL_BTC_PCT         : LREAL := 100.0;           // 百分数系数 [百分数] / Percent factor
    DL_BTC_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_BTC_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_BTC_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位/启动沿检测在任何分支之外周期调用；
 *       bStepDone 为单拍脉冲，逐拍先清（调用方读到的仍是本拍值）
 *----------------------------------------------------------------------------*)
bStepDone := FALSE;                                // 单拍脉冲先清（自清机制）/ single-scan pulse cleared first
fCurrentSetA := DL_BTC_ZERO;                       // 电流设定默认 0：任何未显式赋值的路径都断流 / default 0, any unassigned path is de-energised
fVoltLimitV := DL_BTC_ZERO;                        // 电压限默认 0 / voltage limit defaults to zero
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbStart(CLK := bStart);                            // 启动沿检测无条件刷新 / start edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：清故障与容量统计
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eStep := E_DL_BatteryCycleState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    fChargedAh := DL_BTC_ZERO;                     // 充电容量清 / charge capacity cleared
    fDischargedAh := DL_BTC_ZERO;                  // 放电容量清 / discharge capacity cleared
    fCapacityRatioPct := DL_BTC_ZERO;              // 容量比清 / capacity ratio cleared
    uStepMs := 16#0000_0000;                       // 工步计时清 / step timer cleared
    nCvHoldCnt := 0;                               // CV 确认计数清 / CV hold counter cleared
    bCapSat := FALSE;                              // 饱和标志清 / saturation flag cleared
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸：安全判据量（温度/电压/电流）非有限 → 按越限处置（034B，断流）；
 *       组态量非有限 → 034D 组态分支。分两类是因为前者的正确处置是「当拍断流」，
 *       后者是「拒绝启动」
 *----------------------------------------------------------------------------*)
bNonFinSafe := (fVoltV <> fVoltV) OR (ABS(fVoltV) >= DL_BTC_INF)
            OR (fCurrentA <> fCurrentA) OR (ABS(fCurrentA) >= DL_BTC_INF)
            OR (fTempC <> fTempC) OR (ABS(fTempC) >= DL_BTC_INF);   // 安全判据量非有限 / safety-class non-finite
bNonFinCfg := (fCcCurrentA <> fCcCurrentA) OR (ABS(fCcCurrentA) >= DL_BTC_INF)
           OR (fCvVoltV <> fCvVoltV) OR (ABS(fCvVoltV) >= DL_BTC_INF)
           OR (fCutoffCurrentA <> fCutoffCurrentA) OR (ABS(fCutoffCurrentA) >= DL_BTC_INF)
           OR (fDiscCurrentA <> fDiscCurrentA) OR (ABS(fDiscCurrentA) >= DL_BTC_INF)
           OR (fDiscCutoffV <> fDiscCutoffV) OR (ABS(fDiscCutoffV) >= DL_BTC_INF)
           OR (fCapNomAh <> fCapNomAh) OR (ABS(fCapNomAh) >= DL_BTC_INF)
           OR (fVoltMaxV <> fVoltMaxV) OR (ABS(fVoltMaxV) >= DL_BTC_INF)
           OR (fVoltMinV <> fVoltMinV) OR (ABS(fVoltMinV) >= DL_BTC_INF)
           OR (fTempMaxC <> fTempMaxC) OR (ABS(fTempMaxC) >= DL_BTC_INF);   // 组态量非有限 / configuration non-finite
IF bNonFinSafe THEN
    eStep := E_DL_BatteryCycleState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_BTC_CODE_FLT_1;                   // 故障级：安全判据不可判，按越限处置 / fault: safety values undecidable, treated as out of range
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    fCurrentSetA := DL_BTC_ZERO;                   // 当拍断流（安全路径最高优先）/ current dropped this scan
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bValid := FALSE;                               // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
    RETURN;
END_IF
IF bNonFinCfg THEN
    eStep := E_DL_BatteryCycleState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_BTC_CODE_FLT_3;                   // 故障级：组态非法（映射见错误码表）/ fault: invalid configuration, mapping per the code table
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    fCurrentSetA := DL_BTC_ZERO;                   // 断流 / current dropped
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bValid := FALSE;                               // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（034D 组态分支，先判后除：容量比分母在此被证明为正）
 *----------------------------------------------------------------------------*)
IF (fCapNomAh <= DL_BTC_TOL) OR (fVoltMaxV <= fVoltMinV + DL_BTC_TOL)
   OR (fCcCurrentA <= DL_BTC_TOL) OR (fDiscCurrentA <= DL_BTC_TOL)
   OR (fCutoffCurrentA < DL_BTC_ZERO)
   OR (DINT_TO_UDINT(TIME_TO_DINT(tMaxStep)) = 16#00000000) THEN
    eStep := E_DL_BatteryCycleState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_BTC_CODE_FLT_3;                   // 故障级：组态非法 / fault: invalid configuration
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    fCurrentSetA := DL_BTC_ZERO;                   // 断流 / current dropped
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bValid := FALSE;                               // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜安全域硬判（最高优先，先于任何工步推进）：温度越上限或电压越安全域 →
 *       034B + 当拍断流 + 进故障相。故障锁存至 bReset（热失控不可逆）
 *----------------------------------------------------------------------------*)
IF (fTempC > fTempMaxC) OR (fVoltV > fVoltMaxV + DL_BTC_TOL) OR (fVoltV < fVoltMinV - DL_BTC_TOL) THEN
    eStep := E_DL_BatteryCycleState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_BTC_CODE_FLT_1;                   // 故障级：温度/电压越限 / fault: temperature or voltage out of range
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    fCurrentSetA := DL_BTC_ZERO;                   // 当拍断流（安全侧）/ current dropped this scan, safe side
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bValid := FALSE;                               // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜工步计时：仅活动工步累计（切相清零），静置/完成/待机不累计
 *----------------------------------------------------------------------------*)
IF uDeltaTimeMs < DL_BTC_DT_MIN_MS THEN
    uDtEff := DL_BTC_DT_MIN_MS;                     // 间隔过小按下限，防死等 / floored interval prevents a dead wait
ELSE
    uDtEff := uDeltaTimeMs;                         // 间隔原值 / interval as-is
END_IF
IF (eStep <> E_DL_BatteryCycleState.eIdle) AND (eStep <> E_DL_BatteryCycleState.eDone)
   AND (eStep <> E_DL_BatteryCycleState.eFault) THEN
    IF uStepMs < 16#FFFF_FFFE THEN
        uStepMs := uStepMs + uDtEff;                // 本工步累计 [ms] / accumulate the current step [ms]
    END_IF
END_IF
uMaxStepMs := DINT_TO_UDINT(TIME_TO_DINT(tMaxStep));       // 超时门限 [ms] / timeout threshold [ms]
uRestChgMs := DINT_TO_UDINT(TIME_TO_DINT(tRestCharge));    // 充/放前静置门限 [ms] / pre-step rest threshold [ms]
uRestDiscMs := DINT_TO_UDINT(TIME_TO_DINT(tRestDisc));     // 放后静置门限 [ms] / post-discharge rest threshold [ms]

(*------------------------------------------------------------------------------
 * 段 7｜工步超时（034C）：各工步独立计时，切相即清零，禁相内累计（R40 家族）
 *----------------------------------------------------------------------------*)
IF (eStep <> E_DL_BatteryCycleState.eIdle) AND (eStep <> E_DL_BatteryCycleState.eDone)
   AND (eStep <> E_DL_BatteryCycleState.eFault) AND (uStepMs > uMaxStepMs) THEN
    eStep := E_DL_BatteryCycleState.eFault;        // 进故障相 / enter fault state
    eErr   := DL_BTC_CODE_FLT_2;                   // 故障级：工步超时，工艺卡死 / fault: step timeout, process stuck
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    fCurrentSetA := DL_BTC_ZERO;                   // 断流 / current dropped
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bValid := FALSE;                               // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜容量安时积分：Ah += |I| x Δt/3600（LREAL 累加防精度损失，饱和防溢出）
 *----------------------------------------------------------------------------*)
fDtH := UDINT_TO_LREAL(uDtEff) / DL_BTC_MS_PER_S / DL_BTC_SEC_PER_H;   // 间隔换算成小时 [h] / interval in hours
fAbsCurrentA := ABS(fCurrentA);                    // 电流绝对值 [A] / absolute current [A]
fAhStep := fAbsCurrentA * fDtH;                     // 本拍容量增量 [Ah] / capacity increment [Ah]
IF (eStep = E_DL_BatteryCycleState.eCcCharge) OR (eStep = E_DL_BatteryCycleState.eCvCharge) THEN
    IF fChargedAh < DL_BTC_AH_MAX THEN
        fChargedAh := fChargedAh + fAhStep;         // 充电容量累加 [Ah] / charge capacity accumulation
        IF fChargedAh >= DL_BTC_AH_MAX THEN
            fChargedAh := DL_BTC_AH_MAX;            // 饱和钳位 [Ah] / saturation clamp
            bCapSat := TRUE;                        // 饱和标志 / saturation flag
        END_IF
    ELSE
        bCapSat := TRUE;                            // 已在饱和点 / already saturated
    END_IF
END_IF
IF eStep = E_DL_BatteryCycleState.eDiscCharge THEN
    IF fDischargedAh < DL_BTC_AH_MAX THEN
        fDischargedAh := fDischargedAh + fAhStep;   // 放电容量累加 [Ah] / discharge capacity accumulation
        IF fDischargedAh >= DL_BTC_AH_MAX THEN
            fDischargedAh := DL_BTC_AH_MAX;         // 饱和钳位 [Ah] / saturation clamp
            bCapSat := TRUE;                        // 饱和标志 / saturation flag
        END_IF
    ELSE
        bCapSat := TRUE;                            // 已在饱和点 / already saturated
    END_IF
END_IF
fCapacityRatioPct := fDischargedAh / fCapNomAh * DL_BTC_PCT;   // 容量比（除子已由段 4 证明为正）[百分数] / capacity ratio, divisor proven positive
tStepElapsed := UDINT_TO_TIME(uStepMs);            // 本工步已历时 [ms] / elapsed time of the current step

(*------------------------------------------------------------------------------
 * 段 9｜停止闸（电平，当拍生效）：断流并回待机，不等待工步收尾（安全侧）
 *----------------------------------------------------------------------------*)
IF bStop THEN
    eStep := E_DL_BatteryCycleState.eIdle;         // 回待机 / back to idle
    fCurrentSetA := DL_BTC_ZERO;                   // 当拍断流 / current dropped this scan
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    uStepMs := 16#0000_0000;                       // 工步计时清 / step timer cleared
    nCvHoldCnt := 0;                               // CV 确认计数清 / CV hold counter cleared
    eErr := 16#0000_0000;                          // 停止清信息码 / stop clears info codes
    bValid := FALSE;                               // 停止闸显式不可用（R72）/ explicit FALSE on the stop gate
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜工步状态机：CASE 含 ELSE 兜底（非法状态 → 034D + 断流 + 回待机）
 *       切相一律：uStepMs := 0（禁相内累计）+ bStepDone 单拍脉冲
 *----------------------------------------------------------------------------*)
bStepChanged := FALSE;                             // 切相标志逐拍重判 / transition flag re-judged per scan
bCcReached := (fVoltV >= fCvVoltV - DL_BTC_TOL);            // CC 段电压达 CV 点 / CC reached the CV point
bCvCutoff := (fAbsCurrentA < fCutoffCurrentA + DL_BTC_TOL);  // CV 终止判据 / CV termination predicate
bDiscCutoff := (fVoltV <= fDiscCutoffV + DL_BTC_TOL);        // 放电终止判据 / discharge termination predicate
bRestChgDone := (uStepMs >= uRestChgMs);           // 充/放前静置到时 / pre-step rest elapsed
bRestDiscDone := (uStepMs >= uRestDiscMs);         // 放后静置到时 / post-discharge rest elapsed
IF bCvCutoff THEN
    IF nCvHoldCnt < DL_BTC_CV_HOLD THEN
        nCvHoldCnt := nCvHoldCnt + 1;              // 连续满足拍数饱和自增 [拍] / saturating consecutive-sample counter
    END_IF
ELSE
    nCvHoldCnt := 0;                               // 判据断链即清零（防单点抖动误切）/ counter cleared on any drop-out
END_IF

CASE eStep OF

    E_DL_BatteryCycleState.eIdle:
        fCurrentSetA := DL_BTC_ZERO;               // 待机断流 / de-energised in idle
        fVoltLimitV := DL_BTC_ZERO;                // 待机无电压限 / no voltage limit in idle
        uStepMs := 16#0000_0000;                   // 待机不计时 / no timing in idle
        nCvHoldCnt := 0;                           // CV 计数清 / CV counter cleared
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        IF fbStart.Q THEN
            eStep := E_DL_BatteryCycleState.eRestInit;   // 上升沿启动：先进充电前静置 / start edge enters the pre-charge rest
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            bStepChanged := TRUE;                  // 切相标志 / transition flag
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_BatteryCycleState.eRestInit:
        fCurrentSetA := DL_BTC_ZERO;               // 静置断流 / de-energised while resting
        fVoltLimitV := DL_BTC_ZERO;                // 静置无电压限 / no voltage limit while resting
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在静置相（切相提示）/ info: resting step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF bRestChgDone THEN
            eStep := E_DL_BatteryCycleState.eCcCharge;   // 静置到时进恒流充电 / rest elapsed, enter CC charge
            uStepMs := 16#0000_0000;               // 新工步计时清零（禁相内累计）/ new step timer cleared
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eCcCharge:
        fCurrentSetA := fCcCurrentA;               // 恒流充电电流 [A] / CC charge current [A]
        fVoltLimitV := fVoltMaxV;                  // 电压限取安全域上限 [V] / voltage limit at the safety ceiling [V]
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在恒流充电相 / info: CC charge step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF bCcReached THEN
            eStep := E_DL_BatteryCycleState.eCvCharge;   // 电压达 CV 点切恒压（终止判据达成）/ CV point reached, enter CV
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            nCvHoldCnt := 0;                       // CV 计数复位 / CV counter reset
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eCvCharge:
        fCurrentSetA := fCcCurrentA;               // 恒压段电流上限仍为设定值 [A] / CV current ceiling stays at the setpoint [A]
        fVoltLimitV := fCvVoltV;                   // 恒压点 [V] / CV point [V]
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在恒压充电相 / info: CV charge step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF nCvHoldCnt >= DL_BTC_CV_HOLD THEN
            eStep := E_DL_BatteryCycleState.eRestMid;    // 电流连续 5 拍低于终止值切静置 / cutoff sustained, enter the pre-discharge rest
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            nCvHoldCnt := 0;                       // CV 计数复位 / CV counter reset
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eRestMid:
        fCurrentSetA := DL_BTC_ZERO;               // 静置断流 / de-energised while resting
        fVoltLimitV := DL_BTC_ZERO;                // 静置无电压限 / no voltage limit while resting
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在放前静置相 / info: pre-discharge rest step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF bRestChgDone THEN
            eStep := E_DL_BatteryCycleState.eDiscCharge;   // 静置到时进恒流放电 / rest elapsed, enter CC discharge
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eDiscCharge:
        fCurrentSetA := -ABS(fDiscCurrentA);       // 放电电流按负值下发（放电为负）[A] / discharge issued negative [A]
        fVoltLimitV := fDiscCutoffV;               // 放电终止电压作为下限语义的限值 [V] / discharge cut-off as the limit [V]
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在恒流放电相 / info: CC discharge step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF bDiscCutoff THEN
            eStep := E_DL_BatteryCycleState.eRestFinal;   // 电压达放电终止切静置 / cut-off reached, enter the final rest
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eRestFinal:
        fCurrentSetA := DL_BTC_ZERO;               // 静置断流 / de-energised while resting
        fVoltLimitV := DL_BTC_ZERO;                // 静置无电压限 / no voltage limit while resting
        eErr := DL_BTC_CODE_INFO_1;                // 信息级：工步在放后静置相 / info: post-discharge rest step
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        IF bRestDiscDone THEN
            eStep := E_DL_BatteryCycleState.eDone; // 放后静置到时转完成 / post-discharge rest elapsed, done
            uStepMs := 16#0000_0000;               // 新工步计时清零 / new step timer cleared
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eDone:
        fCurrentSetA := DL_BTC_ZERO;               // 完成态断流 / de-energised when done
        fVoltLimitV := DL_BTC_ZERO;                // 完成态无电压限 / no voltage limit when done
        eErr := 16#0000_0000;                      // 完成无错 / no error when done
        bError := FALSE;                           // 完成无故障 / no fault when done
        IF fbStart.Q THEN
            eStep := E_DL_BatteryCycleState.eRestInit;   // 再次启动重跑一轮 / a new start edge runs another cycle
            uStepMs := 16#0000_0000;               // 计时清零 / timer cleared
            fChargedAh := DL_BTC_ZERO;             // 容量统计重新起算 / capacity statistics restart
            fDischargedAh := DL_BTC_ZERO;          // 容量统计重新起算 / capacity statistics restart
            bStepChanged := TRUE;                  // 切相标志 / transition flag
        END_IF

    E_DL_BatteryCycleState.eFault:
        // v1.0.1 修正：eFault 是合法故障态，必须有独立 CASE 标签。原实现缺此标签，eFault(99) 每拍落进
        // ELSE 兜底支路，把段 3/4/5/7 已判定的 034B（越限断流）/034C（工步超时）覆盖成 034D（非法状态），
        // 激励消失（温度回到域内、超时条件不再成立）后真因码即丢失，诊断只能看到「非法状态」。
        // 本相只做安全侧输出与故障码保持，故障码改写一律归入口闸，零码兜底由段 11 统一处理。
        fCurrentSetA := DL_BTC_ZERO;               // 故障相断流（安全值而非上次值）/ zeroed in fault, never the last value
        fVoltLimitV := DL_BTC_ZERO;                // 电压限撤 / voltage limit dropped
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        // eErr 保持：不得在本相改写（禁 034B/034C → 034D 覆盖）

    ELSE
        eStep := E_DL_BatteryCycleState.eFault;    // 非法状态兜底 / illegal-state fallback
        eErr := DL_BTC_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        fCurrentSetA := DL_BTC_ZERO;               // 断流安全侧 / current dropped, safe side
        fVoltLimitV := DL_BTC_ZERO;                // 电压限撤 / voltage limit dropped

END_CASE

(*------------------------------------------------------------------------------
 * 段 11｜故障相最终闸与出口收口：故障态一律断流（安全值而非上次值），
 *       切相脉冲与饱和提示在本拍出口统一落定
 *----------------------------------------------------------------------------*)
IF eStep = E_DL_BatteryCycleState.eFault THEN
    fCurrentSetA := DL_BTC_ZERO;                   // 故障拍立即 0（安全侧，不保留上次设定）/ zero on any fault scan, never the last value
    fVoltLimitV := DL_BTC_ZERO;                    // 电压限撤 / voltage limit dropped
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    IF eErr = 16#0000_0000 THEN
        eErr := DL_BTC_CODE_FLT_3;                 // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
    END_IF
    IF bReset THEN
        eStep := E_DL_BatteryCycleState.eIdle;     // 仅复位可退出故障相（热失控类故障不得自愈）/ only reset leaves the fault state
    END_IF
ELSE
    IF bCapSat THEN
        eErr := DL_BTC_CODE_INFO_2;                // 信息级：容量统计饱和（优先于切相提示）/ info: capacity saturation outranks the step hint
    END_IF
    IF bStepChanged THEN
        bStepDone := TRUE;                         // 切相当拍输出单拍脉冲 / single-scan pulse on a transition
        IF NOT bCapSat THEN
            eErr := DL_BTC_CODE_INFO_1;            // 信息级：工步切相提示 / info: step transition hint
        END_IF
    END_IF
END_IF
bValid := (eStep <> E_DL_BatteryCycleState.eFault);   // 许可类输出显式落定（R72）/ permission settled explicitly
END_FUNCTION_BLOCK
